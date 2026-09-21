import Foundation
import AppKit
import IOKit
import IOKit.hid

public protocol PanelManagerDelegate: AnyObject {
    func panelDidConnect(serial: String)
    func panelDidDisconnect()
    func panelDidReceiveMotion(_ motions: [PanelMotion])
}

public class PanelManager: ObservableObject {
    public static let shared = PanelManager()

    public static let vendorID: Int = 0x1EDB
    public static let productID: Int = 0xDA0F

    @Published public var isConnected: Bool = false
    @Published public var serialNumber: String = ""
    @Published public var lastActiveControl: String = ""
    /// True while PanaLux has let go of the panel (for DaVinci Resolve).
    @Published public private(set) var isReleased: Bool = false

    public weak var delegate: PanelManagerDelegate?

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private let decoder = PanelDecoder()
    private var inputReportBuffer = [UInt8](repeating: 0, count: 128)

    // Auto-reconnect & keepalive watchdog
    private var healthCheckTimer: Timer?
    private let healthInterval: TimeInterval = 2.0
    private var lastReportTimestamp: Date = Date()
    private var lastRearm: Date = .distantPast

    // Stable heap buffer for IOKit DMA / input reports
    private let reportBufferSize = 128
    private let reportBuffer: UnsafeMutablePointer<UInt8>

    // POSIX advisory lock to prevent multiple processes competing for panel HID
    private var lockFileDescriptor: Int32 = -1

    // LED output uses the same report ID as the button bitmap (0x02). The
    // panel often echoes that write as an input with empty bits, which used
    // to look like every hold had been released.
    private var suppressButtonInputUntil: Date = .distantPast
    private var lastLEDBits: Set<Int>? = nil
    private var lastColorLEDBits: Set<Int>? = nil
    private var wakeObserver: NSObjectProtocol?
    private var wakeWork: DispatchWorkItem?

    // Power management assertion preventing USB suspension / App Nap
    private var activityToken: NSObjectProtocol?

    public init() {
        self.reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
        self.reportBuffer.initialize(repeating: 0, count: reportBufferSize)
    }

    deinit {
        stop()
        reportBuffer.deallocate()
    }

    /// Let go of the panel so another app can use it. LEDs go dark first.
    public func release() {
        guard !isReleased else { return }
        setLEDs(activeBits: [])
        setColorLEDs(activeBits: [])
        stop()
        DispatchQueue.main.async { self.isReleased = true }
    }

    public func reclaim() {
        DispatchQueue.main.async { self.isReleased = false }
        stop()
        start()
    }

    public func start() {
        guard !AppRuntime.isRenderingStills, hidManager == nil else { return }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                // Give the USB bus a moment to come back, then put the lights where they were.
                self?.wakeWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    if let dev = self?.connectedDevice { self?.wake(device: dev) }
                    self?.rewriteLEDs()
                }
                self?.wakeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            }
        }

        // Advisory lock so a second copy of PanaLux cannot compete for the panel
        guard acquireAdvisoryLock() else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Target specifically the primary vendor-defined control interface (UsagePage 0xFF00, Usage 0x00)
        // This avoids matching all 11 sub-devices and prevents handle clobbering.
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: PanelManager.vendorID,
            kIOHIDProductIDKey as String: PanelManager.productID,
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
            kIOHIDPrimaryUsageKey as String: 0
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mySelf = Unmanaged<PanelManager>.fromOpaque(context).takeUnretainedValue()
            mySelf.deviceMatched(device: device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mySelf = Unmanaged<PanelManager>.fromOpaque(context).takeUnretainedValue()
            mySelf.deviceRemoved(device: device)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("[PanelManager] Warning: IOHIDManagerOpen returned \(openResult)")
        }

        // Initial search in case device is already attached
        searchAndAttach()

        // Start keepalive & health check watchdog
        startWatchdog()
    }

    public func stop() {
        stopWatchdog()
        wakeWork?.cancel()
        wakeWork = nil
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        if let dev = connectedDevice {
            IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, reportBufferSize, nil, nil)
            self.connectedDevice = nil
        }

        guard let manager = hidManager else { releaseAdvisoryLock(); return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = nil
        releaseAdvisoryLock()
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    private func startWatchdog() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthInterval, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    private func stopWatchdog() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    /// What the watchdog should do this tick. Split out from the IOKit call so it can
    /// be tested without a panel attached: this decision was deleted once already and
    /// nothing caught it, because the panel layer could not be exercised in a test.
    enum HealthAction: Equatable {
        /// Nothing attached. Look for it, so the panel comes back without a replug.
        case searchForDevice
        /// Connected and quiet. The firmware stops streaming on its own after an idle,
        /// so the stream-enable report is sent again or the panel goes silent while
        /// still looking connected.
        case rearmStream
        /// Connected and in use, or re-armed recently. Stay off the bus.
        case wait
    }

    static let quietBeforeRearm: TimeInterval = 5.0
    static let rearmInterval: TimeInterval = 5.0

    static func healthAction(connected: Bool, quietFor: TimeInterval, sinceRearm: TimeInterval) -> HealthAction {
        guard connected else { return .searchForDevice }
        guard quietFor >= quietBeforeRearm else { return .wait }
        guard sinceRearm >= rearmInterval else { return .wait }
        return .rearmStream
    }

    /// The old watchdog read feature report 0x0a first to decide whether to re-arm.
    /// That read is what used to tear HID down when it failed, taking the lights with
    /// it. Re-arming is a write of the same report `wake` already sends at connect, so
    /// it goes out unconditionally instead: no read, nothing to fail.
    private func performHealthCheck() {
        let now = Date()
        let action = Self.healthAction(
            connected: connectedDevice != nil,
            quietFor: now.timeIntervalSince(lastReportTimestamp),
            sinceRearm: now.timeIntervalSince(lastRearm)
        )
        switch action {
        case .searchForDevice:
            searchAndAttach()
        case .rearmStream:
            lastRearm = now
            if let dev = connectedDevice {
                wake(device: dev)
                rewriteLEDs()
            }
        case .wait:
            break
        }
    }

    public func reconnect() {
        if let dev = connectedDevice {
            IOHIDDeviceRegisterInputReportCallback(dev, reportBuffer, reportBufferSize, nil, nil)
            self.connectedDevice = nil
        }
        decoder.reset()
        suppressButtonInputUntil = .distantPast
        DispatchQueue.main.async {
            self.isConnected = false
        }
        searchAndAttach()
    }

    private func searchAndAttach() {
        guard let manager = hidManager else { return }
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }

        for dev in deviceSet {
            let vid = (IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let pid = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            let page = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
            let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0

            if vid == PanelManager.vendorID && pid == PanelManager.productID && page == 0xFF00 && usage == 0 {
                deviceMatched(device: dev)
                break
            }
        }
    }

    private func deviceMatched(device: IOHIDDevice) {
        // Avoid duplicate callback registrations if already connected to this exact device
        if let existing = self.connectedDevice, existing == device {
            wake(device: device)
            return
        }

        self.connectedDevice = device
        lastLEDBits = nil

        // Prevent system and USB from sleeping while panel is connected
        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Micro Color Panel connected"
            )
        }

        // Wake the panel - stream enable feature report 0x0a = [0x0a, 0x01]
        wake(device: device)
        setBrightness(level: Int(AppSettings.shared.backlightBrightness))

        // Read serial number if possible
        let serial = readSerial(device: device)

        // Register input report callback with stable heap buffer
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            reportBufferSize,
            { context, result, sender, type, reportID, report, reportLength in
                guard let context = context else { return }
                let mySelf = Unmanaged<PanelManager>.fromOpaque(context).takeUnretainedValue()
                mySelf.handleInputReport(reportID: UInt8(reportID), report: report, length: reportLength)
            },
            context
        )

        DispatchQueue.main.async {
            self.isConnected = true
            self.serialNumber = serial
            self.delegate?.panelDidConnect(serial: serial)
        }
        print("[PanelManager] Panel connected")
    }

    private func deviceRemoved(device: IOHIDDevice) {
        if self.connectedDevice == device {
            IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferSize, nil, nil)
            self.connectedDevice = nil
            decoder.reset()
            suppressButtonInputUntil = .distantPast

            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
                activityToken = nil
            }

            DispatchQueue.main.async {
                self.isConnected = false
                self.delegate?.panelDidDisconnect()
            }
            print("[PanelManager] Panel disconnected; watching for it to return")
        }
    }

    public func wake(device: IOHIDDevice? = nil) {
        guard let dev = device ?? connectedDevice else { return }
        var wakeReport: [UInt8] = [0x0a, 0x01]
        let result = IOHIDDeviceSetReport(
            dev,
            kIOHIDReportTypeFeature,
            CFIndex(0x0a),
            &wakeReport,
            wakeReport.count
        )
        if result != kIOReturnSuccess {
            print("[PanelManager] Note: wake report result = \(result)")
        }
    }

    public func setBrightness(level: Int) {
        guard let dev = connectedDevice else { return }
        let clamped = max(0, min(100, level))
        var payload: [UInt8] = [0x08, 0x00, UInt8(clamped)]
        let result = IOHIDDeviceSetReport(
            dev,
            kIOHIDReportTypeFeature,
            CFIndex(0x08),
            &payload,
            payload.count
        )
        if result != kIOReturnSuccess { print("[PanelManager] Note: backlight report result = \(result)") }
    }

    /// Another app (Resolve, a replug, sleep) can clear the lights without telling us, and the
    /// cache would then swallow every write that matches what we last sent. Forget it and resend.
    public func rewriteLEDs() {
        if let bits = lastLEDBits {
            lastLEDBits = nil
            setLEDs(activeBits: bits)
        }
        if let colorBits = lastColorLEDBits {
            lastColorLEDBits = nil
            setColorLEDs(activeBits: colorBits)
        }
    }

    public func setLEDs(activeBits: Set<Int>) {
        guard let dev = connectedDevice else { return }
        // Encoder pushes have no LEDs. Never write into their input-bit positions.
        let activeBits = Set(activeBits.filter { $0 >= 12 && $0 < 64 })
        guard activeBits != lastLEDBits else { return }
        lastLEDBits = activeBits
        suppressButtonInputUntil = Date().addingTimeInterval(0.02)
        var payload = [UInt8](repeating: 0, count: 9)
        payload[0] = 0x02 // Output Report ID
        for bit in activeBits {
            if bit >= 0 && bit < 64 {
                let byteIdx = 1 + (bit / 8)
                let bitIdx = bit % 8
                payload[byteIdx] |= (1 << bitIdx)
            }
        }
        _ = IOHIDDeviceSetReport(
            dev,
            kIOHIDReportTypeOutput,
            CFIndex(0x02),
            &payload,
            payload.count
        )
    }

    public func setColorLEDs(activeBits: Set<Int>) {
        guard let dev = connectedDevice else { return }
        let validBits = Set(activeBits.filter { $0 >= 0 && $0 < 48 })
        guard validBits != lastColorLEDBits else { return }
        lastColorLEDBits = validBits
        var payload = [UInt8](repeating: 0, count: 7)
        payload[0] = 0x04 // Output Report ID for color channels
        for bit in validBits {
            let byteIdx = 1 + (bit / 8)
            let bitIdx = bit % 8
            payload[byteIdx] |= (1 << bitIdx)
        }
        _ = IOHIDDeviceSetReport(
            dev,
            kIOHIDReportTypeOutput,
            CFIndex(0x04),
            &payload,
            payload.count
        )
    }

    public func setDualLEDs(whiteBits: Set<Int>, colorBits: Set<Int>) {
        setLEDs(activeBits: whiteBits)
        setColorLEDs(activeBits: colorBits)
    }

    /// True when a report 0x02 payload has no button bits set, allowing for the
    /// leading report-ID byte IOKit sometimes prefixes.
    static func isEmptyButtonReport(_ data: Data) -> Bool {
        let payload = PanelDecoder.stripReportID(reportId: 0x02, data: data)
        return payload.prefix(8).allSatisfy { $0 == 0 }
    }

    static func shouldSuppressButtonReport(_ data: Data, until: inout Date, now: Date) -> Bool {
        // Never drop button reports: the panel only sends reports on state change.
        // Dropping an empty report permanently swallows the key release, causing
        // buttons (like UNDO) to become stuck indefinitely.
        // StudioEngine handles hold debouncing safely at the layer level.
        return false
    }

    private func readSerial(device: IOHIDDevice) -> String {
        var serialBuf = [UInt8](repeating: 0, count: 33)
        var length = CFIndex(serialBuf.count)
        let res = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(0x09),
            &serialBuf,
            &length
        )
        if res == kIOReturnSuccess && length > 1 {
            let data = Data(serialBuf[1..<Int(length)])
            if let str = String(data: data, encoding: .ascii) {
                return str.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
            }
        }
        return "Unknown"
    }

    private func handleInputReport(reportID: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        lastReportTimestamp = Date()
        let data = Data(bytes: report, count: length)
        // An LED write on report 0x02 comes back as an input echo with an empty
        // bitmap, which used to read as "every key released". Ignore that echo,
        // but never ignore a report with bits set: an echo is always empty, so a
        // non-empty report inside the window is a real key and dropping it was
        // why a press sometimes had to be made twice.
        if reportID == 0x02, Self.shouldSuppressButtonReport(data, until: &suppressButtonInputUntil, now: Date()) { return }
        let motions = decoder.decode(reportId: reportID, data: data)
        if !motions.isEmpty {
            delegate?.panelDidReceiveMotion(motions)
        }
    }

    // MARK: - Advisory Locking

    private func acquireAdvisoryLock() -> Bool {
        let path = AppPaths.panelLockPath
        let fd = open(path, O_RDWR | O_CREAT, 0o666)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            print("[PanelManager] Notice: Panel lock held by another process.")
            return false
        }
        ftruncate(fd, 0)
        let pidStr = "pid \(getpid())\n"
        _ = pidStr.withCString { write(fd, $0, strlen($0)) }
        self.lockFileDescriptor = fd
        return true
    }

    private func releaseAdvisoryLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }
}
