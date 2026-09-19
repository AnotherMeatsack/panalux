import Foundation
import Network
import os

public protocol LightroomBridgeDelegate: AnyObject {
    func lightroomConnectionStateChanged(isConnected: Bool)
    func lightroomParameterDidUpdate(name: String, value: Double)
    /// Lightroom put a different photo on screen. The trail is per photo.
    func lightroomActivePhotoDidChange(id: String?)
}

public extension LightroomBridgeDelegate {
    func lightroomActivePhotoDidChange(id: String?) {}
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
    /// Which Lightroom module is in front. Open as Layers behaves differently in each.
    @Published public private(set) var currentModule: String? = nil

    private var photoRanges = PhotoParameterRanges()
    public func parameterRange(for param: String) -> ParameterRange? { photoRanges.values[param] }

    public weak var delegate: LightroomBridgeDelegate?

    /// Every value change PanaLux knows about, whoever caused it: a knob here, or a mouse in
    /// Lightroom. This is what the trail records. Always called on the main thread.
    public var onValueChanged: ((String, Double) -> Void)?
    public var onLocalValueChanged: ((String, Double) -> Void)?
    /// A settings table came back for a snapshot request, matched by the token that asked.
    public var onKeyframe: ((String, String) -> Void)?

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
    /// Settings tables arrive in pieces, keyed by the token that asked for them.
    private var keyframeChunks: [String: [String]] = [:]

    // Slider updates are coalesced: only the newest value per slider is sent, a few dozen
    // times a second. Lightroom applies each message one at a time, so sending every USB tick
    // from several knobs at once queues up work it can take many seconds to finish.
    private var pendingValues: [String: Double] = [:]
    private var pendingOrder: [String] = []
    private var flushTimer: DispatchSourceTimer?
    private var afterPreview: [() -> Void] = []
    private let previewLog = Logger(subsystem: "com.panalux.app", category: "RewindPreview")
    private var previewValues: [String: Double] = [:]
    private var previewPhotoID: String?
    private var previewUnavailable = false
    private var previewInFlight: String?
    private var previewTimeout: DispatchWorkItem?
    /// Latest acknowledgement from Lightroom, useful for non-destructive runtime diagnostics.
    @Published public private(set) var previewStatus = "No preview sent"
    private var batchInFlight = false
    private let flushInterval: DispatchTimeInterval = .milliseconds(40)

    public init() {}

    public func connect() {
        guard !AppRuntime.isRenderingStills else { return }
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
            self.previewValues.removeAll()
            self.previewInFlight = nil
            self.previewUnavailable = false
            self.afterPreview.removeAll()
            self.previewTimeout?.cancel()
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
                // The first refresh may precede the feedback socket. Resend identity now.
                self.requestFullRefresh(force: true)
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
            if line.hasPrefix("SendKey ") {
                let payload = String(line.dropFirst("SendKey ".count))
                if !isMuted { DispatchQueue.main.async { LightroomKeys.send(payload) } }
                continue
            }
            // Which photo is on screen: "PanaLuxSelection <count> <photoID> <module>".
            if line.hasPrefix("PanaLuxSelection ") {
                absorbSelection(String(line.dropFirst("PanaLuxSelection ".count)))
                continue
            }
            if line.hasPrefix("PanaLuxPreviewApplied ") {
                let fields = line.split(separator: " ").map(String.init)
                if fields.count >= 4, fields[1] == previewInFlight {
                    previewLog.notice("Lightroom preview acknowledged: \(fields[2], privacy: .public) sliders, \(fields[3], privacy: .public)")
                    previewInFlight = nil
                    previewTimeout?.cancel()
                    DispatchQueue.main.async { self.previewStatus = "Applied \(fields[2]) sliders · \(fields[3])" }
                    flushPreview()
                }
                continue
            }
            if line.hasPrefix("PanaLuxRange ") {
                let payload = String(line.dropFirst("PanaLuxRange ".count))
                DispatchQueue.main.async { self.photoRanges.accept(payload) }
                continue
            }
            // A settings table, in pieces: "PanaLuxKeyframe <token> <seq> <total> <base64>".
            if line.hasPrefix("PanaLuxKeyframe ") {
                absorbKeyframe(String(line.dropFirst("PanaLuxKeyframe ".count)))
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
                self.onValueChanged?(name, val)
            }
        }
    }

    /// "<count> <photoID> <module>". The photo id can be anything the catalog calls it,
    /// so only the count and the trailing module are split off.
    private func absorbSelection(_ payload: String) {
        let parts = payload.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return }
        let count = Int(parts[0]) ?? 0
        let module = parts[parts.count - 1]
        let id = parts[1..<(parts.count - 1)].joined(separator: " ")
        DispatchQueue.main.async {
            if self.selectedPhotoCount != count { self.selectedPhotoCount = count }
            if self.currentModule != module { self.currentModule = module }
            let resolved = id == "-" ? nil : id
            guard self.activePhotoID != resolved else { return }
            self.photoRanges.reset(photoID: resolved)
            self.activePhotoID = resolved
            self.delegate?.lightroomActivePhotoDidChange(id: resolved)
        }
    }

    /// "<token> <seq> <total> <base64>". Chunked because a settings table with masks in it is
    /// far longer than a line either side of this socket wants to carry.
    private func absorbKeyframe(_ payload: String) {
        let parts = payload.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 4, let seq = Int(parts[1]), let total = Int(parts[2]), total > 0 else { return }
        let token = parts[0]
        lock.lock()
        if seq <= 1 { keyframeChunks[token] = [] }
        keyframeChunks[token, default: []].append(parts[3])
        let assembled = keyframeChunks[token] ?? []
        let done = seq >= total && assembled.count == total
        if done { keyframeChunks[token] = nil }
        // A request Lightroom never finished answering must not pin memory forever.
        if keyframeChunks.count > 8 { keyframeChunks.removeAll() }
        lock.unlock()
        guard done else { return }
        let blob = assembled.joined()
        DispatchQueue.main.async { self.onKeyframe?(token, blob) }
    }

    private func sendRaw(_ message: String) {
        guard let data = message.data(using: .utf8), let conn = sendConnection, sendReady else { return }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }

    /// Runs on `queue`. Remember the newest value and make sure a flush is coming.
    private func enqueueValue(_ name: String, _ value: Double) {
        // A new manual edit after releasing Undo wins over an unsent preview value.
        previewValues[name] = nil
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

    /// Wait for Lightroom's apply/render acknowledgement, not just TCP acceptance. New
    /// ring packets replace pending values while a frame is being displayed.
    private func flushPreview() {
        guard previewInFlight == nil else { return }
        if previewValues.isEmpty {
            let ready = afterPreview
            afterPreview.removeAll()
            ready.forEach { $0() }
            return
        }
        guard let photoID = previewPhotoID, sendReady else { return }
        let token = UUID().uuidString
        let sentValues = previewValues
        let encoded = previewValues.sorted { $0.key < $1.key }
            .map { String(format: "%@=%.9f", $0.key, $0.value) }.joined(separator: ",")
        previewValues.removeAll(keepingCapacity: true)
        previewInFlight = token
        sendRaw("PanaLuxPreview \(token) \(photoID) \(encoded)\n")
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.previewInFlight == token else { return }
            self.previewInFlight = nil
            self.previewUnavailable = true
            let fallback = sentValues.merging(self.previewValues) { _, latest in latest }
            self.previewValues.removeAll()
            for (name, value) in fallback { self.enqueueValue(name, value) }
            DispatchQueue.main.async { self.previewStatus = "Legacy preview · reload PanaLux Bridge for smooth playback" }
            self.flushPreview()
        }
        previewTimeout = timeout
        queue.asyncAfter(deadline: .now() + 2, execute: timeout)
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
        // The plugin will not echo this back to us (it is our own move, inside the holdoff),
        // so the trail has to hear about it here.
        if let hook = onLocalValueChanged ?? onValueChanged {
            if Thread.isMainThread {
                hook(name, clamped)
            } else {
                DispatchQueue.main.async { hook(name, clamped) }
            }
        }
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

    // MARK: - Rewind

    /// Ask the plugin for a whole `getDevelopSettings()` table. The reply comes back on the
    /// value socket as `PanaLuxKeyframe <token> …` and is matched by this token.
    public func requestDevelopSnapshot(token: String) {
        guard !isMuted else { return }
        queue.async {
            self.afterPreview.append { self.sendRaw("PanaLuxSnapshot \(token)\n") }
            self.flushPreview()
        }
    }

    /// Hand a table back. This is what puts masks and crop back exactly as they were.
    public func restoreDevelopSnapshot(blob: String) {
        guard !isMuted, !blob.isEmpty else { return }
        queue.async {
            self.sendRaw("PanaLuxRestoreBegin 1.00000\n")
            var index = blob.startIndex
            while index < blob.endIndex {
                let end = blob.index(index, offsetBy: 900, limitedBy: blob.endIndex) ?? blob.endIndex
                self.sendRaw("PanaLuxRestoreChunk \(blob[index..<end])\n")
                index = end
            }
            self.sendRaw("PanaLuxRestoreEnd 1.00000\n")
        }
        markStale()
        queue.asyncAfter(deadline: .now() + 0.35) { self.requestFullRefresh(force: true) }
    }

    /// Ask the plugin to log the keys of a settings table. Used once, by hand, to check
    /// whether masks survive the round trip before anything was designed around it.
    public func probeDevelopSettings() {
        queue.async { self.sendRaw("PanaLuxProbe 1.00000\n") }
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

extension LightroomBridge: RewindOutput {
    public func rewindRange(for param: String) -> ParameterRange? { parameterRange(for: param) }
    public func rewindKnownValues() -> [String: Double] { allKnownValues() }

    public func rewindSetParameters(_ values: [String: Double]) {
        guard !isMuted, let photoID = activePhotoID else { return }
        lock.lock()
        for (name, value) in values {
            localValues[name] = value
            lastSentTime[name] = Date()
            updatedAt[name] = Date()
        }
        lock.unlock()
        queue.async {
            if self.previewUnavailable {
                for (name, value) in values { self.enqueueValue(name, value) }
                return
            }
            if self.previewPhotoID != photoID {
                self.previewValues.removeAll()
                self.previewPhotoID = photoID
            }
            self.previewValues.merge(values) { _, latest in latest }
            self.flushPreview()
        }
    }

    public func rewindSetParameter(_ name: String, value: Double) {
        setParameter(name, value: value)
    }

    public func rewindRequestSnapshot(token: String) { requestDevelopSnapshot(token: token) }

    public func rewindRestore(blob: String) { restoreDevelopSnapshot(blob: blob) }
}
