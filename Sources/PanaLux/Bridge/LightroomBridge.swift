import Foundation
import Network

public protocol LightroomBridgeDelegate: AnyObject {
    func lightroomConnectionStateChanged(isConnected: Bool)
    func lightroomParameterDidUpdate(name: String, value: Double)
}

/// Talks to the MIDI2LR plugin running inside Lightroom Classic.
/// The plugin listens on 58763 (commands in) and 58764 (values out); PanaLux is the client.
public class LightroomBridge: ObservableObject {
    public static let shared = LightroomBridge()

    public static let host = "127.0.0.1"
    public static let sendPort: UInt16 = 58763
    public static let recvPort: UInt16 = 58764

    @Published public var isConnected: Bool = false
    /// How many photos are selected in Lightroom, and which one is active. Reported by
    /// PanaLux Bridge; the stock MIDI2LR plugin does not send it, so this stays nil there.
    @Published public private(set) var selectedPhotoCount: Int? = nil
    @Published public private(set) var activePhotoID: String? = nil

    public weak var delegate: LightroomBridgeDelegate?

    private var sendConnection: NWConnection?
    private var recvConnection: NWConnection?
    private let queue = DispatchQueue(label: "com.panalux.lrbridge", qos: .userInteractive)

    private var localValues: [String: Double] = [:]
    private var lastSentTime: [String: Date] = [:]
    private var lastRefreshRequest: Date = .distantPast
    /// When a key action may have changed values Lightroom-side (Undo, Reset, presets, next photo).
    private var valuesStaleAt: Date = .distantPast
    /// Last time each value was confirmed by Lightroom or set by us.
    private var updatedAt: [String: Date] = [:]
    private let lock = NSLock()
    private let echoHoldoff: TimeInterval = 1.25
    private var retryTimer: Timer?
    private var sendReady = false
    private var recvReady = false
    private var recvBuffer = ""

    // Slider updates are coalesced: only the newest value per slider is sent, a few dozen
    // times a second. Lightroom applies each message one at a time, so sending every USB tick
    // from several knobs at once queues up work it can take many seconds to finish.
    private var pendingValues: [String: Double] = [:]
    private var pendingOrder: [String] = []
    private var flushTimer: DispatchSourceTimer?
    private var batchInFlight = false
    private let flushInterval: DispatchTimeInterval = .milliseconds(40)

    public init() {}

    public func connect() {
        teardown()
        setupSendConnection()
        setupRecvConnection()
        startRetryTimer()
    }

    public func disconnect() {
        retryTimer?.invalidate()
        retryTimer = nil
        teardown()
    }

    private func teardown() {
        sendConnection?.cancel()
        sendConnection = nil
        recvConnection?.cancel()
        recvConnection = nil
        sendReady = false
        recvReady = false
        queue.async {
            self.pendingValues.removeAll()
            self.pendingOrder.removeAll()
            self.batchInFlight = false
        }
        publishConnection()
    }

    /// Lightroom may open after PanaLux, or quit and come back. Keep knocking.
    private func startRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                if !self.sendReady || !self.recvReady {
                    self.reconnectSockets()
                }
            }
        }
        // .common, not the default mode: a timer in the default mode stops firing
        // while a menu is open or a list is being scrolled.
        if let retryTimer { RunLoop.main.add(retryTimer, forMode: .common) }
    }

    private func reconnectSockets() {
        if !sendReady {
            sendConnection?.cancel()
            setupSendConnection()
        }
        if !recvReady {
            recvConnection?.cancel()
            setupRecvConnection()
        }
    }

    private func publishConnection() {
        let connected = sendReady && recvReady
        DispatchQueue.main.async {
            guard self.isConnected != connected else { return }
            self.isConnected = connected
            self.delegate?.lightroomConnectionStateChanged(isConnected: connected)
        }
    }

    private func setupSendConnection() {
        let conn = NWConnection(
            host: NWEndpoint.Host(LightroomBridge.host),
            port: NWEndpoint.Port(rawValue: LightroomBridge.sendPort)!,
            using: .tcp
        )
        sendConnection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.sendConnection else { return }
            switch state {
            case .ready:
                self.sendReady = true
                // Relative encoders land immediately instead of waiting for soft takeover.
                self.sendRaw("Pickup 0\n")
                self.invalidateCache()
                self.requestFullRefresh(force: true)
                self.publishConnection()
            case .failed, .waiting, .cancelled:
                if self.sendReady {
                    self.sendReady = false
                    self.invalidateCache()
                    self.publishConnection()
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func setupRecvConnection() {
        let conn = NWConnection(
            host: NWEndpoint.Host(LightroomBridge.host),
            port: NWEndpoint.Port(rawValue: LightroomBridge.recvPort)!,
            using: .tcp
        )
        recvConnection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.recvConnection else { return }
            switch state {
            case .ready:
                self.recvReady = true
                self.recvBuffer = ""
                self.publishConnection()
                self.readIncomingFeedback(on: conn)
            case .failed, .waiting, .cancelled:
                if self.recvReady {
                    self.recvReady = false
                    self.publishConnection()
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func readIncomingFeedback(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] content, _, isComplete, error in
            guard let self, conn === self.recvConnection else { return }
            if let data = content, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                self.absorbFeedback(text: text)
            }
            if error == nil && !isComplete {
                self.readIncomingFeedback(on: conn)
            } else {
                // Lightroom quit or the plugin reloaded. The retry timer reconnects.
                self.recvReady = false
                self.invalidateCache()
                self.publishConnection()
            }
        }
    }

    private func absorbFeedback(text: String) {
        // TCP can split a line across packets; keep the unfinished tail.
        recvBuffer += text
        var lines = recvBuffer.components(separatedBy: "\n")
        recvBuffer = lines.removeLast()

        var updates: [String: Double] = [:]
        for line in lines {
            // Copy/Paste Settings and Key1…Key40 ask the host app to type a shortcut.
            if line.hasPrefix("PanaLuxSelection ") {
                let parts = line.dropFirst("PanaLuxSelection ".count).split(separator: " ")
                if let count = parts.first.flatMap({ Int($0) }) {
                    let id = parts.count > 1 ? String(parts[1]) : nil
                    DispatchQueue.main.async {
                        if self.selectedPhotoCount != count { self.selectedPhotoCount = count }
                        if self.activePhotoID != id { self.activePhotoID = id }
                    }
                }
                continue
            }
            if line.hasPrefix("SendKey ") {
                let payload = String(line.dropFirst("SendKey ".count))
                if !isMuted { DispatchQueue.main.async { LightroomKeys.send(payload) } }
                continue
            }
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            guard let val = Double(parts[1].trimmingCharacters(in: .whitespaces)), val >= 0.0, val <= 1.0 else { continue }

            lock.lock()
            let lastSent = lastSentTime[name] ?? .distantPast
            if Date().timeIntervalSince(lastSent) < echoHoldoff {
                lock.unlock()
                continue
            }
            localValues[name] = val
            updatedAt[name] = Date()
            lock.unlock()
            updates[name] = val
        }
        guard !updates.isEmpty else { return }
        DispatchQueue.main.async {
            for (name, val) in updates {
                self.delegate?.lightroomParameterDidUpdate(name: name, value: val)
            }
        }
    }

    private func sendRaw(_ message: String) {
        guard let data = message.data(using: .utf8), let conn = sendConnection, sendReady else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }

    /// Runs on `queue`. Remember the newest value and make sure a flush is coming.
    private func enqueueValue(_ name: String, _ value: Double) {
        if pendingValues.updateValue(value, forKey: name) == nil {
            pendingOrder.append(name)
        }
        guard flushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in self?.flushValues() }
        flushTimer = timer
        timer.resume()
    }

    /// Runs on `queue`. One write for everything that changed since the last one.
    private func flushValues(force: Bool = false) {
        guard !pendingOrder.isEmpty else {
            flushTimer?.cancel()
            flushTimer = nil
            return
        }
        // If the last batch hasn't left yet, Lightroom is behind: keep merging instead of piling on.
        if batchInFlight && !force { return }
        guard let conn = sendConnection, sendReady else {
            pendingValues.removeAll()
            pendingOrder.removeAll()
            return
        }
        var message = ""
        for name in pendingOrder {
            if let value = pendingValues[name] {
                message += String(format: "%@ %.5f\n", name, value)
            }
        }
        pendingValues.removeAll(keepingCapacity: true)
        pendingOrder.removeAll(keepingCapacity: true)
        batchInFlight = true
        conn.send(content: Data(message.utf8), completion: .contentProcessed({ [weak self] _ in
            self?.queue.async { self?.batchInFlight = false }
        }))
    }

    // MARK: - Values

    /// Forget cached values so a stale number can never be sent as an absolute position.
    public func invalidateCache() {
        lock.lock()
        localValues.removeAll()
        lastSentTime.removeAll()
        updatedAt.removeAll()
        lock.unlock()
    }

    /// Ask the plugin to resend every develop value. Rate-limited.
    public func requestFullRefresh(force: Bool = false) {
        let now = Date()
        lock.lock()
        let tooSoon = now.timeIntervalSince(lastRefreshRequest) < 1.0
        if !force && tooSoon {
            lock.unlock()
            return
        }
        lastRefreshRequest = now
        lock.unlock()
        sendRaw("FullRefresh 1.00000\n")
    }

    /// Undo, Reset, a preset, or a new photo can change values without PanaLux knowing which.
    public func markStale() {
        lock.lock()
        valuesStaleAt = Date()
        lastSentTime.removeAll()
        lock.unlock()
    }

    /// True when this value has been confirmed since the last action that could change it.
    public func isFresh(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (updatedAt[name] ?? .distantPast) >= valuesStaleAt
    }

    public var secondsSinceStale: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(valuesStaleAt)
    }

    public func hasValue(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return localValues[name] != nil
    }

    /// Copy of every develop value Lightroom has reported. Used to restore the photo after the tour.
    public func allKnownValues() -> [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        return localValues
    }

    /// Seconds since the last refresh request — lets callers wait briefly for real values.
    public var secondsSinceRefreshRequest: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastRefreshRequest)
    }

    /// While true (Settings is open) nothing reaches Lightroom, whatever the caller.
    public var isMuted: Bool {
        get { lock.lock(); defer { lock.unlock() }; return muted }
        set { lock.lock(); muted = newValue; lock.unlock() }
    }
    private var muted = false

    @discardableResult
    public func setParameter(_ name: String, value: Double) -> Double {
        if isMuted { return self.value(for: name) }
        let clamped = max(0.0, min(1.0, value))
        lock.lock()
        localValues[name] = clamped
        lastSentTime[name] = Date()
        updatedAt[name] = Date()
        lock.unlock()

        queue.async { self.enqueueValue(name, clamped) }
        return clamped
    }

    @discardableResult
    public func nudgeParameter(_ name: String, delta: Double) -> Double {
        lock.lock()
        let current = localValues[name] ?? Self.neutralValue(for: name)
        lock.unlock()
        return setParameter(name, value: current + delta)
    }

    @discardableResult
    public func setAngle(_ name: String, turns: Double) -> Double {
        var wrapped = turns.truncatingRemainder(dividingBy: 1.0)
        if wrapped < 0 { wrapped += 1.0 }
        return setParameter(name, value: wrapped)
    }

    public func fireAction(_ name: String) {
        guard !isMuted else { return }
        queue.async {
            // Keep order: slider moves made before the key press land first.
            self.flushValues(force: true)
            self.sendRaw(String(format: "%@ 1.00000\n", name))
        }
        markStale()
        // Give Lightroom a moment to apply the action, then ask for every value again.
        queue.asyncAfter(deadline: .now() + 0.15) { self.requestFullRefresh() }
        // Navigation and resets change every value. Accept the plugin's next update right away.
        lock.lock()
        lastSentTime.removeAll()
        lock.unlock()
    }

    public func value(for name: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return localValues[name] ?? Self.neutralValue(for: name)
    }

    /// Best guess when Lightroom has not reported a value yet. Crop edges are not centered.
    public static func neutralValue(for name: String) -> Double {
        switch name {
        case "CropLeft", "CropTop": return 0.0
        case "CropRight", "CropBottom": return 1.0
        default: return 0.5
        }
    }
}
