import Foundation
import Combine
import SwiftUI
import AppKit

/// Where an action is in its life. Lightroom does not report completion, so `working`
/// is shown for commands known to take a moment and then clears.
public enum ActionPhase: Equatable {
    case sent
    case working
    case done
    case failed
    case blocked
}

/// One cell of the HUD's knob-row readout.
public struct KnobCell: Equatable, Hashable {
    public let label: String
    /// Where that slider is sitting right now, when Lightroom has reported it.
    public let value: String?
    public let isOverlay: Bool

    public init(label: String, value: String? = nil, isOverlay: Bool) {
        self.label = label
        self.value = value
        self.isOverlay = isOverlay
    }
}

public enum ActiveDisplayMode: Equatable {
    case idle
    case knob(name: String, param: String, value: Double, displayValue: String, isFine: Bool, angleDegrees: Double)
    case ring(name: String, param: String, value: Double, displayValue: String, isFine: Bool, angleDegrees: Double)
    case trackball(name: String, state: TrackballState, isFine: Bool, companion: String?)
    case layerBanner(layer: String, variant: String?, hint: String?, chips: [String], latched: Bool, grid: [KnobCell])
    case action(name: String, label: String, phase: ActionPhase)
    /// Several controls moving together. two hands, or a knob plus a ball.
    case multi([LiveReading])
    /// Holding UNDO: the trail, the playhead, and the twelve knobs rolling back.
    case rewind(RewindState)
}

public class StudioEngine: ObservableObject, PanelManagerDelegate, LightroomBridgeDelegate {
    public static let shared = StudioEngine()

    @Published public var profile: Profile
    @Published public var activeLayers: Set<String> = []
    /// Layers turned on by a tap (or a mask-creating key). They stay until tapped off or Return to Base.
    @Published public var toggledLayers: Set<String> = []
    @Published public var heldModifiers: Set<String> = []
    @Published public var activeVariants: [String: String] = [:]

    // Live UI State for Notch HUD and Studio
    /// Lives in `HUDFeed` so per-packet updates don't redraw the Map window.
    public var currentDisplayMode: ActiveDisplayMode {
        get { HUDFeed.shared.latest }
        set { HUDFeed.shared.submit(newValue) }
    }
    /// The control being touched. Only changes when a different control moves.
    @Published public private(set) var activeControlHighlight: String? = nil
    /// Fires on every movement so the Map can pulse a control without redrawing.
    public let controlPulse = PassthroughSubject<String, Never>()
    public var lastAdjustmentTimestamp: Date = Date()
    @Published public var statusMessage: String = "Base"

    /// Safe Setup: idle knobs preview instead of grading. Holds and keys still send.
    @Published public var isLiveGradingEnabled: Bool = true
    /// Pause: nothing reaches Lightroom or Photoshop. The HUD says what would have happened.
    @Published public var isOutputPaused: Bool = false
    @Published public private(set) var isProgrammingButtons = false
    @Published public var isLightShowActive: Bool = false
    /// True only while a light show or the intro is genuinely driving the panel. The stored flag can be
    /// left set by an interrupted show; this cannot, so settings and reactive lights never freeze.
    public var ledsOwnedByShow: Bool { PanelLightShow.shared.isRunning || IntroLEDDirector.shared.isLive }
    @Published public private(set) var isBeforeViewActive: Bool = false
    @Published public private(set) var programmingHoldControl: String?
    private var programmingHoldWork: DispatchWorkItem?
    private var programmingPressed = Set<String>()
    @Published public var combinationEditorActive = false
    @Published public var combinationHeld: Set<String> = []
    @Published public var combinationTrigger = "PRESS_LUM_MIX"
    private var combinationInput = CombinationInput()

    public var effectiveCombinations: [ButtonCombination] { profile.combinations ?? ButtonCombination.defaults }

    public func saveCombination(command: String) {
        let item = CommandDatabase.shared.catalogCommand(for: command)
        guard !item.isParameter, !command.hasPrefix("hold_"), !command.hasPrefix("modifier:"),
              command != Self.holdCompareID else {
            mapStatusMessage = "Choose a button action, shortcut, preset or mode toggle."
            return
        }
        var binding = ButtonBinding()
        applyTapItem(&binding, item)
        guard binding.hasTapAnything else { return }
        var entries = effectiveCombinations
        let entry = ButtonCombination(held: combinationHeld.subtracting([combinationTrigger]).sorted(), trigger: combinationTrigger, binding: binding)
        guard !entry.held.isEmpty else {
            var single = profile.buttons[combinationTrigger] ?? ButtonBinding()
            applyTapItem(&single, item)
            profile.buttons[combinationTrigger] = single
            mapStatusMessage = "Saved press: " + PanelLayout.label(forControl: combinationTrigger)
            return
        }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        profile.combinations = entries
        mapStatusMessage = "Saved: " + entry.title
    }

    public func removeCombination(_ id: String) {
        profile.combinations = effectiveCombinations.filter { $0.id != id }
    }

    public func setProgrammingButtons(_ enabled: Bool) {
        if enabled { returnToBase(announce: false) }
        programmingHoldWork?.cancel()
        programmingHoldControl = nil
        programmingPressed.removeAll()
        inspectorHoldEdit = nil
        isProgrammingButtons = enabled
        if !enabled { combinationEditorActive = false }
    }

    /// Settings is on screen: the panel previews only and nothing reaches Lightroom.
    @Published public private(set) var isSettingsOpen: Bool = false

    var outputBlocked: Bool { isOutputPaused || isSettingsOpen || isProgrammingButtons }
    var blockedWord: String { isProgrammingButtons ? "Programming" : (isSettingsOpen ? "Settings open" : "Paused") }

    public func setSettingsOpen(_ open: Bool) {
        guard open != isSettingsOpen else { return }
        if open {
            // Let go of holds first so a held Compare Before gets its release.
            returnToBase(announce: false)
            for tb in trackballs.values { tb.stopInertia() }
            for tb in overlayTrackballs.values { tb.stopInertia() }
        }
        isSettingsOpen = open
        LightroomBridge.shared.isMuted = open
        updateStatusMessage()
    }

    /// A parameter temporarily parked on the focus-dial knob. Not saved to the map.
    @Published public var tempFocusParam: String? = nil
    /// Controls highlighted by "Find on Panel".
    @Published public var foundControls: [String] = []

    // Map history
    @Published public private(set) var canUndoMap = false
    @Published public private(set) var canRedoMap = false


    /// Last physical button that went down. the Map follows it.
    @Published public var lastButtonName: String? = nil
    /// Last analog control that moved. the Map follows it.
    @Published public var lastAnalogName: String? = nil
    /// Button whose tap program is currently latched (press-and-release function set).
    @Published public var latchedProgramButton: String? = nil
    /// Button whose hold program is currently overlaid.
    @Published public var heldProgramButton: String? = nil
    /// Button whose While-held card is selected in Map (drop targets follow this).
    @Published public var inspectorHoldEdit: String? = nil
    /// Last drop result shown in the inspector.
    @Published public var mapStatusMessage: String = ""
    /// Mode being edited in the Map when no key is held. nil = Base.
    @Published public var mapEditLayer: String? = nil
    /// Linear / radial / brush is on the photo: balls move the pointer, color stays off.
    @Published public private(set) var maskPlacing: Bool = false
    /// Photos gathered for the next Photoshop blend. Counted from the marks PanaLux
    /// sent, so it is a running tally rather than a reading of Lightroom's collection.
    /// Lightroom keeps the Quick Collection across launches, so this is kept too —
    /// otherwise quitting PanaLux mid-bracket would silently send the wrong photos.
    @Published public private(set) var bracketCount: Int = UserDefaults.standard.integer(forKey: "bracketCount") {
        didSet { UserDefaults.standard.set(bracketCount, forKey: "bracketCount") }
    }

    func noteBracketMark() {
        bracketCount += 1
    }

    public func clearBracketCount() {
        guard bracketCount != 0 else { return }
        bracketCount = 0
    }

    /// A copied control assignment for Paste.
    @Published public var clipboard: ControlClipboard? = nil
    /// First control of a swap; the next control selected (on screen or on the panel) completes it.
    @Published public var swapSource: String? = nil

    // Trackball engines
    public var trackballs: [String: TrackballEngine] = [:]

    // Mapping lookups
    private var slotToControl: [String: String] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var collapseTimer: Timer?

    private var undoStack: [Profile] = []
    private var redoStack: [Profile] = []
    private var historyBaseline: Profile
    private var applyingHistory = false

    private init() {
        let loaded = AppRuntime.isRenderingStills ? Profile.loadDefault() : Profile.loadUserOrDefault()
        self.profile = loaded
        self.historyBaseline = loaded
        buildLookups()
        setupTrackballs()

        guard !AppRuntime.isRenderingStills else { return }

        PanelManager.shared.delegate = self
        LightroomBridge.shared.delegate = self

        // Aligning happens long after the key press that started it, so the bridge
        // reports back rather than returning a result nobody is waiting for.
        PhotoshopBridge.shared.autoAlign = AppSettings.shared.autoAlignLayers
        PhotoshopBridge.shared.onProgress = { [weak self] message in
            self?.triggerActionDisplay(name: "GRAB_STILL", label: message, phase: .done, duration: 5)
        }

        // Rewind records every value change the plugin reports, whether a knob here or a mouse
        // in Lightroom caused it.
        let rewind = RewindEngine.shared
        rewind.output = LightroomBridge.shared
        LightroomBridge.shared.onValueChanged = { name, value in
            rewind.record(param: name, value: value)
        }
        LightroomBridge.shared.onLocalValueChanged = { name, value in
            rewind.record(param: name, value: value, userInitiated: true)
        }
        LightroomBridge.shared.onKeyframe = { token, blob in
            rewind.acceptSnapshot(token: token, blob: blob)
        }

        PanelManager.shared.start()
        LightroomBridge.shared.connect()

        // Snapshot the current map as Home the first time, so presets can return to it.
        ProfilePresets.snapshotHomeIfNeeded(profile)

        $profile
            .dropFirst()
            .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
            .sink { Profile.save($0) }
            .store(in: &cancellables)

        $profile
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] next in self?.recordHistory(next) }
            .store(in: &cancellables)

        // The playhead moves far more often than a key is pressed; let it own the readout
        // for as long as the hold lasts.
        rewind.changed
            .sink { [weak self] state in
                guard let self, RewindEngine.shared.isRewinding else { return }
                self.collapseTimer?.invalidate()
                self.currentDisplayMode = .rewind(state)
            }
            .store(in: &cancellables)

        // A tangent that starts because you edited from the past would otherwise begin in silence.
        // Say so, and say the other line is safe. (Branching by key already has its own message.)
        rewind.tangentEvents
            .sink { [weak self] event in
                guard let self, !RewindEngine.shared.isRewinding else { return }
                if case .started(let name, let parent, let at) = event {
                    self.triggerActionDisplay(
                        name: "REWIND",
                        label: "\(name) started at \(RewindEngine.clock(at)) · \(parent) is kept",
                        phase: .done,
                        duration: 4
                    )
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notif in
                guard let self else { return }
                guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let isLightroom = bundleID == "com.adobe.LightroomClassicCC7" || bundleID == "com.adobe.Lightroom"
                let isPanaLux = bundleID == Bundle.main.bundleIdentifier
                if !isLightroom && !isPanaLux {
                    if self.activeLayers.contains("REWIND") || RewindEngine.shared.isRewinding {
                        NotchHUDWindowController.shared.collapseRewind()
                        self.returnToBase(announce: false)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func buildLookups() {
        let knobMap = [
            0: "Y_LIFT", 1: "Y_GAMMA", 2: "Y_GAIN", 3: "CONTRAST",
            4: "PIVOT", 5: "MID_DETAIL", 6: "COL_BOOST", 7: "SHAD",
            8: "HI_LIGHT", 9: "SAT", 10: "HUE", 11: "LUM_MIX"
        ]
        for (slot, name) in knobMap {
            slotToControl["6:\(slot)"] = name
        }
        let ballMap = [
            0: "TB_LIFT_X", 1: "TB_LIFT_Y", 2: "RING_LIFT",
            3: "TB_GAMMA_X", 4: "TB_GAMMA_Y", 5: "RING_GAMMA",
            6: "TB_GAIN_X", 7: "TB_GAIN_Y", 8: "RING_GAIN"
        ]
        for (slot, name) in ballMap {
            slotToControl["5:\(slot)"] = name
        }
        resetVariants()
    }

    private func resetVariants() {
        activeVariants.removeAll()
        for (layerName, layerSpec) in profile.layers {
            if let def = layerSpec.default_variant {
                activeVariants[layerName] = def
            }
        }
    }

    private func setupTrackballs() {
        trackballs.removeAll()
        for (ballName, cfg) in profile.balls {
            let engine = TrackballEngine(
                name: ballName,
                hueParam: cfg.hue,
                satParam: cfg.sat,
                radius: cfg.radius,
                invertX: cfg.invert_x,
                invertY: cfg.invert_y
            )
            engine.onInertiaStep = { [weak self, weak engine] turns, sat in
                guard let self = self, let engine = engine else { return }
                if self.shouldSendToLightroom {
                    LightroomBridge.shared.setAngle(engine.hueParam, turns: turns)
                    LightroomBridge.shared.setParameter(engine.satParam, value: sat)
                }
                let state = engine.currentState
                DispatchQueue.main.async {
                    self.showBall(ballName, state, false)
                }
            }
            trackballs[ballName] = engine
        }
    }

    // MARK: - Map history & whole-map changes

    private func recordHistory(_ next: Profile) {
        defer { historyBaseline = next }
        if applyingHistory { return }
        undoStack.append(historyBaseline)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        redoStack.removeAll()
        refreshHistoryFlags()
    }

    private func refreshHistoryFlags() {
        canUndoMap = !undoStack.isEmpty
        canRedoMap = !redoStack.isEmpty
    }

    public func undoMapChange() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(profile)
        applyHistory(previous)
        mapStatusMessage = "Undid map change"
    }

    public func redoMapChange() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(profile)
        applyHistory(next)
        mapStatusMessage = "Redid map change"
    }

    private func applyHistory(_ target: Profile) {
        applyingHistory = true
        profile = target
        applyingHistory = false
        historyBaseline = target
        profileStructureChanged()
        refreshHistoryFlags()
    }

    /// Replace the whole map (preset, import, restore, reset). Always backs up first. Undoable.
    public func replaceProfile(_ next: Profile, reason: String) {
        Profile.save(profile)
        ProfileStore.backup(reason: reason)
        profile = next
        Profile.save(next)
        profileStructureChanged()
    }

    /// Balls and variants are cached; rebuild them after the map changes shape.
    public func profileStructureChanged() {
        returnToBase(announce: false)
        setupTrackballs()
        resetVariants()
    }

    // MARK: - Escape hatches

    /// Drop every hold, latch, toggle, and temporary override. The panel is back on its base map.
    public func returnToBase(announce: Bool = true) {
        referenceChordWork?.cancel()
        referenceChord.reset()
        referencePeekVisible = false
        ReferencePeekWindow.shared.setVisible(false)
        for work in holdWorkItems.values { work.cancel() }
        holdWorkItems.removeAll()
        for work in pendingHoldReleases.values { work.cancel() }
        pendingHoldReleases.removeAll()
        holdWasUsed.removeAll()
        buttonDownAt.removeAll()
        combinationInput.reset()
        resetKnobReadout = nil
        for name in engagedHolds {
            if let release = holdBinding(for: name)?.release_action, !outputBlocked {
                if RewindCommands.isRewind(release) {
                    RewindEngine.shared.setPeeking(false)
                } else if PointerCommands.isPointer(release) {
                    PointerDriver.perform(release)
                } else {
                    LightroomBridge.shared.fireAction(release)
                }
            }
        }
        cancelPicker(commit: false)
        PointerDriver.cancel()
        RewindEngine.shared.endRewind(announce: false)
        maskPlacing = false
        engagedHolds.removeAll()
        pressedButtonBits.removeAll()
        activeLayers.removeAll()
        toggledLayers.removeAll()
        heldModifiers.removeAll()
        latchedProgramButton = nil
        heldProgramButton = nil
        tempFocusParam = nil
        overlayTrackballs.removeAll()
        repeatAccumulators.removeAll()
        recentReadings.reset()
        resetVariants()
        updateStatusMessage()
        updateLeds()
        setHighlight(nil)
        collapseTimer?.invalidate()
        if announce {
            triggerActionDisplay(name: "BASE", label: "Back to base map", phase: .done)
        } else {
            currentDisplayMode = .idle
        }
    }

    public func setOutputPaused(_ paused: Bool) {
        isOutputPaused = paused
        if paused { returnToBase(announce: false) }
        triggerActionDisplay(
            name: "PAUSE",
            label: paused ? "Output paused. practice freely" : "Output live",
            phase: paused ? .blocked : .done
        )
        updateStatusMessage()
    }

    public func setTempFocus(_ param: String?) {
        tempFocusParam = param
        let knob = PanelLayout.label(forControl: AppSettings.shared.focusDialControl)
        if let param {
            triggerActionDisplay(name: "FOCUS", label: "\(CommandDatabase.shared.label(for: param)) on \(knob)", phase: .done)
        } else {
            triggerActionDisplay(name: "FOCUS", label: "\(knob) is back to normal", phase: .done)
        }
        updateStatusMessage()
    }

    // MARK: - Find on panel

    public struct ControlUse: Hashable, Identifiable {
        public var id: String { control + "|" + context }
        public let control: String
        public let context: String
    }

    /// Every place a command is mapped: base map, each layer, and button programs.
    public func uses(of commandId: String) -> [ControlUse] {
        var out: [ControlUse] = []
        func add(_ control: String, _ context: String) { out.append(ControlUse(control: control, context: context)) }
        for (c, k) in profile.knobs where k.param == commandId { add(c, "Base") }
        for (c, r) in profile.rings where r.param == commandId { add(c, "Base") }
        for (c, b) in profile.balls where b.hue == commandId || b.sat == commandId { add(c, "Base") }
        for (c, spec) in profile.buttons {
            if spec.action == commandId { add(c, "Tap") }
            if spec.hold_action == commandId { add(c, "Hold") }
            if spec.tapProgram?.focusParam == commandId { add(c, "Tap focus") }
            if spec.holdProgram?.focusParam == commandId { add(c, "Hold focus") }
            for (k, b) in spec.holdProgram?.knobs ?? [:] where b.param == commandId {
                add(k, "Hold \(PanelLayout.label(forControl: c))")
            }
            for (k, b) in spec.holdProgram?.rings ?? [:] where b.param == commandId {
                add(k, "Hold \(PanelLayout.label(forControl: c))")
            }
        }
        for (name, layer) in profile.layers {
            let title = layerTitle(name)
            for (c, k) in layer.knobs ?? [:] where k.param == commandId { add(c, title) }
            for (c, r) in layer.rings ?? [:] where r.param == commandId { add(c, title) }
            for (c, b) in layer.balls ?? [:] where b.hue == commandId || b.sat == commandId { add(c, title) }
            for (c, s) in layer.buttons ?? [:] where s.action == commandId { add(c, title) }
            for (_, v) in layer.variants ?? [:] {
                for (c, k) in v.knobs ?? [:] where k.param == commandId { add(c, title) }
            }
        }
        return out.sorted { ($0.context == "Base" ? 0 : 1, $0.control) < ($1.context == "Base" ? 0 : 1, $1.control) }
    }

    public func findOnPanel(_ commandId: String) -> [ControlUse] {
        let found = uses(of: commandId)
        foundControls = Array(Set(found.map(\.control)))
        return found
    }

    public func layerTitle(_ layer: String) -> String {
        profile.layers[layer]?.title ?? LayerNames.defaultTitle(layer)
    }

    // MARK: - PanelManagerDelegate

    public func panelDidConnect(serial: String) {
        // A replug must never resume a hold whose key-up we missed.
        returnToBase(announce: false)
        updateLeds(immediate: true)
    }

    public func panelDidDisconnect() {
        returnToBase(announce: false)
    }

    public func panelDidReceiveMotion(_ motions: [PanelMotion]) {
        // The bitmap is unordered. Process potential held controls before their triggers.
        let modifiers = Set(effectiveCombinations.flatMap(\.held))
        let ordered = motions.enumerated().sorted { lhs, rhs in
            let l = lhs.element.kind == .keyDown && modifiers.contains(HardwareMap.shared.controlName(forButtonBit: lhs.element.slot) ?? "")
            let r = rhs.element.kind == .keyDown && modifiers.contains(HardwareMap.shared.controlName(forButtonBit: rhs.element.slot) ?? "")
            return l == r ? lhs.offset < rhs.offset : l
        }
        for (_, motion) in ordered { processMotion(motion) }
    }

    private func processMotion(_ m: PanelMotion) {
        let telemetry = HardwareTelemetry.shared
        if telemetry.reportId != m.reportId { telemetry.reportId = m.reportId }
        if telemetry.slotOrBit != m.slot { telemetry.slotOrBit = m.slot }
        if m.kind == .keyDown { telemetry.timestamp = Date() }

        if m.kind == .keyDown || m.kind == .keyUp {
            let buttonName = HardwareMap.shared.controlName(forButtonBit: m.slot) ?? "UNKNOWN_BIT_\(m.slot)"
            PanelDiagnostics.record("\(m.kind.rawValue) bit=\(m.slot) control=\(buttonName)")
            handleButton(buttonName, isDown: m.kind == .keyDown)
            return
        }

        let key = "\(m.reportId):\(m.slot)"
        guard let controlName = slotToControl[key] else { return }

        resetKnobReadout = nil
        markHoldsUsed()
        setHighlight(controlName)
        if lastAnalogName != controlName { lastAnalogName = controlName }

        let units = Double(m.delta) / Double(PanelDecoder.encoderLSB)
        let isFine = heldModifiers.contains("FINE") ||
            (heldProgramButton != nil && profile.buttons[heldProgramButton ?? ""]?.modifier == "FINE")

        if activePickerButton != nil, m.kind == .knob || m.kind == .ring || m.kind == .trackball {
            handlePickerAnalog(controlName, kind: m.kind, units: units, isFine: isFine)
            return
        }

        if m.kind == .knob {
            handleKnob(controlName, deltaUnits: units, isFine: isFine)
        } else if m.kind == .ring {
            handleRing(controlName, deltaUnits: units, isFine: isFine)
        } else if m.kind == .trackball {
            handleTrackballAxis(controlName, deltaUnits: units, isFine: isFine)
        }
    }

    private var pressedButtonBits = Set<Int>()
    private var selectedHardwareButtonBit: Int? = nil
    /// How long to wait for Lightroom to report a slider before assuming the middle.
    private let readbackPatience: TimeInterval = 1.5
    private var readbackRetried: Set<String> = []
    private var readbackGaveUp: Set<String> = []
    /// Turns made while waiting for Lightroom to say where a slider is. They are applied
    /// from the real value the moment it arrives, so the first turn of an unread slider
    /// moves it by what you turned instead of jumping to the middle.
    private var pendingNudges: [String: Double] = [:]

    /// Values arrive in bursts, so the grid is redrawn once after the burst settles.
    private var holdBannerRefresh: DispatchWorkItem?
    private func scheduleHoldBannerRefresh() {
        guard case .layerBanner = currentDisplayMode else { return }
        holdBannerRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshHoldBannerIfShowing() }
        holdBannerRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private var referenceChord = ReferenceChord()
    private var referenceChordWork: DispatchWorkItem?
    @Published private(set) var referencePeekVisible = false

    private var holdWorkItems: [String: DispatchWorkItem] = [:]
    private var engagedHolds: Set<String> = []
    private var pendingHoldReleases: [String: DispatchWorkItem] = [:]
    /// A hold that engages too early drops the mode banner on an ordinary press, which
    /// reads as the panel fighting you. Half a second is a deliberate press.
    private var holdThreshold: TimeInterval { max(0.2, AppSettings.shared.holdDelay) }

    // A hold you engaged but never used is almost always a tap you were slow on.
    // Track when each key went down and whether anything happened while it was
    // held, so the release can still fire the tap instead of silently eating it.
    private var buttonDownAt: [String: Date] = [:]
    private var holdWasUsed: Set<String> = []
    /// Past this a hold was clearly meant, so the release only exits the mode. It has to
    /// sit above the hold delay or a press could never be rescued.
    private var tapRescueCeiling: TimeInterval { holdThreshold + 0.4 }

    /// Anything that makes an engaged hold "used": a knob, a ball, a ring, or
    /// another key. After this the release just exits the mode.
    private func markHoldsUsed(excluding name: String? = nil) {
        guard !engagedHolds.isEmpty else { return }
        for held in engagedHolds where held != name {
            holdWasUsed.insert(held)
        }
    }

    /// Only shape-changing holds are rescued. An instant hold (Show Before) and a
    /// picker (the mask wheel) both do their job on press or release already.
    private func holdIsRescuable(_ name: String) -> Bool {
        guard let spec = holdBinding(for: name) else { return false }
        if spec.hold_action != nil { return false }
        if spec.hold_picker != nil { return false }
        return spec.hold_layer != nil || spec.modifier != nil || spec.holdProgram != nil
    }
    private var overlayTrackballs: [String: TrackballEngine] = [:]
    private var ledWorkItem: DispatchWorkItem?
    private var analogSpinDegrees: [String: Double] = [:]
    private var recentReadings = RecentReadings()
    private var activeDialReadout: (param: String, name: String)?
    private var resetKnobReadout: (control: String, param: String)?

    /// Keep the dial visible after a press and use Lightroom's actual reset value,
    /// including defaults such as temperature that are not normalized zero/midpoint.
    func beginKnobResetReadout(control: String, param: String) {
        resetKnobReadout = (control, param)
        activeDialReadout = (param, PanelLayout.label(forControl: control))
        analogSpinDegrees[control] = 0
        recentReadings.reset()
        currentDisplayMode = .knob(name: PanelLayout.label(forControl: control),
                                  param: CommandDatabase.shared.label(for: param),
                                  value: LightroomBridge.shared.value(for: param),
                                  displayValue: "Resetting…", isFine: false, angleDegrees: 0)
        scheduleCollapse()
    }

    private func refreshKnobResetReadout(param: String, value: Double) {
        guard let reset = resetKnobReadout, reset.param == param,
              case .knob(let name, let label, _, _, _, _) = currentDisplayMode,
              name == PanelLayout.label(forControl: reset.control),
              label == CommandDatabase.shared.label(for: param) else { return }
        currentDisplayMode = .knob(name: name, param: label, value: value,
                                  displayValue: formatValue(param: param, value: value),
                                  isFine: false, angleDegrees: 0)
    }
    private var repeatAccumulators: [String: (units: Double, lastFire: Date)] = [:]
    private var readbackAttempts: [String: Date] = [:]
    private var lastNoticeAt: Date = .distantPast
    private var activePickerButton: String?
    private var pickerRingAcc: Double = 0
    private var pickerLastStep: Date = .distantPast
    private var lastPickerIndex: Int = 0
    private var lastPickerCombine: MaskCombine = .create
    private var pickerCombineAcc: Double = 0

    private func bumpSpin(for key: String, delta: Double, gain: Double, cap: Double) -> Double {
        // Knobs are detented and dump a HID burst per click; rings stream smoothly.
        // Cap is per packet so a burst cannot accumulate into a full turn.
        let increment = min(cap, max(-cap, delta * gain))
        analogSpinDegrees[key, default: 0] += increment
        return analogSpinDegrees[key] ?? 0
    }

    private func setHighlight(_ control: String?) {
        if activeControlHighlight != control { activeControlHighlight = control }
        if let control { controlPulse.send(control) }
    }

    /// One control shows its full readout; several moving together share one readout.
    private func publishAnalogHUD(name: String, param: String, display: String, mode: ActiveDisplayMode) {
        let moving = recentReadings.record(LiveReading(control: name, param: param, value: display))
        currentDisplayMode = moving.count > 1 ? .multi(Array(moving.prefix(6))) : mode
        scheduleCollapse()
    }

    /// Safe Setup mutes idle knobs, but a physical hold is the user grading. send it.
    private var shouldSendToLightroom: Bool {
        guard !outputBlocked else { return false }
        return isLiveGradingEnabled || !activeLayers.isEmpty || heldProgramButton != nil || !heldModifiers.isEmpty
            || latchedProgramButton != nil || tempFocusParam != nil
    }

    public func highlightHardwareControl(_ name: String?) {
        guard let n = name, AppSettings.shared.highlightHardwareOnSelect else {
            selectedHardwareButtonBit = nil
            updateLeds()
            return
        }
        selectedHardwareButtonBit = HardwareMap.shared.buttonBit(forControl: n)
        updateLeds()
    }

    private func handleButton(_ name: String, isDown: Bool) {
        if Thread.isMainThread {
            applyButton(name, isDown: isDown)
        } else {
            DispatchQueue.main.async { self.applyButton(name, isDown: isDown) }
        }
    }

    private func applyButton(_ name: String, isDown: Bool) {
        // The combination editor must still be able to capture either physical key.
        guard !isProgrammingButtons else { applyMappedButton(name, isDown: isDown); return }
        let wasVisible = referenceChord.visible
        let events = referenceChord.receive(name, down: isDown)
        referenceChordWork?.cancel()
        referenceChordWork = nil
        if referenceChord.pending != nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.referenceChordWork = nil
                for event in self.referenceChord.flush() { self.applyMappedButton(event.name, isDown: event.down) }
            }
            referenceChordWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + ReferenceChord.grace, execute: work)
        }
        if wasVisible != referenceChord.visible {
            referencePeekVisible = referenceChord.visible
            ReferencePeekWindow.shared.setVisible(referencePeekVisible)
        }
        for event in events { applyMappedButton(event.name, isDown: event.down) }
    }

    private func applyMappedButton(_ name: String, isDown: Bool) {
        if isDown { resetKnobReadout = nil }
        if isProgrammingButtons {
            if isDown {
                if combinationEditorActive {
                    combinationHeld = programmingPressed
                    combinationTrigger = name
                    programmingPressed.insert(name)
                    mapStatusMessage = "Captured. Release the panel and drop an action below."
                    return
                }
                programmingPressed.insert(name)
                lastButtonName = name
                programmingHoldControl = nil
                inspectorHoldEdit = nil
                programmingHoldWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isProgrammingButtons, self.programmingPressed.contains(name) else { return }
                    self.programmingHoldControl = name
                    self.inspectorHoldEdit = name
                    self.mapStatusMessage = "Drop an action on \(PanelLayout.label(forControl: name)) to set While held."
                }
                programmingHoldWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
            } else {
                programmingPressed.remove(name)
                programmingHoldWork?.cancel()
            }
            return
        }

        let decision = combinationInput.receive(name, down: isDown, combinations: effectiveCombinations)
        if case .fire(let combination) = decision {
            PanelDiagnostics.record("combination \(combination.id)")
            for member in combination.held + [name] {
                holdWorkItems.removeValue(forKey: member)?.cancel()
                holdWasUsed.insert(member)
            }
            setHighlight(name)
            performTap(name, override: combination.binding)
            return
        }
        if case .suppress = decision {
            holdWorkItems.removeValue(forKey: name)?.cancel()
            if !isDown {
                if engagedHolds.contains(name) { disengageHold(name) }
                if let bit = HardwareMap.shared.buttonBit(forControl: name) { pressedButtonBits.remove(bit) }
                updateLeds()
            }
            return
        }
        if case .deferTap = decision {
            // A possible modifier must not fire its single press before the chord is known.
            if !(holdBinding(for: name)?.hasHoldFunctionSet ?? false) { return }
        }
        if case .tap = decision, !(holdBinding(for: name)?.hasHoldFunctionSet ?? false) {
            performTap(name)
            return
        }

        if isDown {
            pendingHoldReleases[name]?.cancel()
            pendingHoldReleases[name] = nil
        }

        setHighlight(isDown ? name : (engagedHolds.contains(name) ? name : nil))
        if isDown {
            if lastButtonName != name { lastButtonName = name }
            buttonDownAt[name] = Date()
            markHoldsUsed(excluding: name)
            GuideController.shared.hardwareEvent(.buttonDown(name))
        }

        if let bit = HardwareMap.shared.buttonBit(forControl: name) {
            if isDown {
                pressedButtonBits.insert(bit)
            } else if !engagedHolds.contains(name) {
                pressedButtonBits.remove(bit)
            }
            updateLeds(immediate: true)
        }

        let baseSpec = profile.buttons[name] ?? ButtonBinding()
        let layerOverride = layerButtonOverride(for: name)
        let overlayHasHold = layerOverride?.hasHoldFunctionSet == true
        let holdSpec = overlayHasHold ? (layerOverride ?? baseSpec) : baseSpec
        let tapSpec = layerOverride ?? baseSpec
        let needsHoldDelay = tapSpec.hasTapAnything && holdSpec.hasHoldFunctionSet

        if activePickerButton != nil, let combine = MaskCombine.buttonMap[name] {
            if isDown {
                ToolWheelSession.shared.combine = combine
                ToolWheelSession.shared.tick += 1
                lastPickerCombine = combine
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                updateStatusMessage()
                updateLeds()
            }
            return
        }

        if isDown {
            // Layer overlays remap other keys (USER+AUTO_COLOR → Upright Auto).
            // Never treat the hold key itself as a layer tap, or USER would no-op.
            // A mode that gives the key its own hold (Masks · Loop = click-and-drag)
            // must not take this shortcut.
            if layerOverride != nil && !isHoldActivator(name) && !overlayHasHold {
                performTap(name)
                updateLeds()
                return
            }
            if engagedHolds.contains(name) {
                updateLeds()
                return
            }
            if needsHoldDelay {
                holdWorkItems[name]?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.holdWorkItems[name] = nil
                    self.engageHold(name)
                }
                holdWorkItems[name] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
                updateLeds()
                return
            }
            if holdSpec.hasHoldFunctionSet {
                engageHold(name)
                updateLeds()
                return
            }
            performTap(name)
            updateLeds()
            return
        }

        holdWorkItems[name]?.cancel()
        let hadPendingHold = holdWorkItems.removeValue(forKey: name) != nil

        if layerOverride != nil && !isHoldActivator(name) && !overlayHasHold {
            updateLeds()
            return
        }

        if engagedHolds.contains(name) {
            let heldFor = buttonDownAt[name].map { Date().timeIntervalSince($0) } ?? .infinity
            let unused = !holdWasUsed.contains(name)
            let rescueTap = unused
                && heldFor < tapRescueCeiling
                && holdIsRescuable(name)
                && (resolvedButtonBinding(for: name)?.hasTapAnything ?? false)

            // LED output lives on the same 0x02 report as buttons. The panel can
            // echo an empty bitmap for one frame; wait before dropping the hold.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.pendingHoldReleases[name] = nil
                if let bit = HardwareMap.shared.buttonBit(forControl: name) {
                    self.pressedButtonBits.remove(bit)
                }
                self.disengageHold(name)
                if rescueTap { self.performTap(name) }
                self.updateLeds()
            }
            pendingHoldReleases[name] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            holdWasUsed.remove(name)
            return
        }

        if hadPendingHold {
            performTap(name)
            updateLeds()
            return
        }

        updateLeds()
    }

    private func isHoldActivator(_ name: String) -> Bool {
        if engagedHolds.contains(name) { return true }
        if heldProgramButton == name { return true }
        if activePickerButton == name { return true }
        if profile.buttons[name]?.hold_picker != nil { return true }
        if let layer = profile.buttons[name]?.hold_layer, activeLayers.contains(layer) {
            return true
        }
        if let layer = profile.buttons[name]?.layer, toggledLayers.contains(layer) {
            return true
        }
        return false
    }

    /// Held layers win over toggled ones, so holding USER while Masks is on still gives Upright.
    private var layerPriority: [String] {
        let held = activeLayers.subtracting(toggledLayers).sorted()
        let toggled = activeLayers.intersection(toggledLayers).sorted()
        return held + toggled
    }

    private func layerButtonOverride(for name: String) -> ButtonBinding? {
        for layer in layerPriority {
            if let binding = profile.layers[layer]?.buttons?[name] {
                return binding
            }
        }
        return nil
    }

    private func resolvedButtonBinding(for name: String) -> ButtonBinding? {
        layerButtonOverride(for: name) ?? profile.buttons[name] ??
            (name.hasPrefix("PRESS_") ? ButtonBinding(action: "reset_knob:" + String(name.dropFirst(6))) : nil)
    }

    private func performTap(_ name: String, override: ButtonBinding? = nil) {
        let spec = override ?? resolvedButtonBinding(for: name)

        guard let spec, spec.hasTapAnything else {
            triggerActionDisplay(name: name, label: "Not assigned. set it in Map", phase: .blocked)
            return
        }

        if let tapProgram = spec.tapProgram {
            toggleLatchedProgram(button: name, program: tapProgram)
            return
        }

        if let toggleLayer = spec.layer {
            if toggledLayers.contains(toggleLayer) {
                if toggleLayer == "MASK" { endMaskPlacing(announce: false) }
                if toggleLayer == "REWIND" { RewindEngine.shared.endRewind() }
                toggledLayers.remove(toggleLayer)
                activeLayers.remove(toggleLayer)
                collapseToIdle()
                triggerActionDisplay(name: name, label: "\(layerTitle(toggleLayer)) off", phase: .done)
            } else {
                toggledLayers.insert(toggleLayer)
                activeLayers.insert(toggleLayer)
                if toggleLayer == "REWIND" {
                    beginRewind()
                } else {
                    triggerLayerBanner(layer: toggleLayer)
                }
            }
            updateLeds()
            updateStatusMessage()
            return
        }

        if let newVariant = spec.set_variant {
            for layer in layerPriority {
                if profile.layers[layer]?.variants?[newVariant] != nil {
                    activeVariants[layer] = newVariant
                    triggerLayerBanner(layer: layer, variant: newVariant)
                    updateStatusMessage()
                    return
                }
            }
            triggerActionDisplay(name: name, label: "Bank \(newVariant) needs its layer held", phase: .blocked)
            return
        }

        if outputBlocked {
            let what = spec.ps != nil ? "Photoshop round-trip" : CommandDatabase.shared.label(for: spec.action ?? "")
            triggerActionDisplay(name: name, label: "\(blockedWord) · \(what)", phase: .blocked)
            return
        }

        if let action = spec.action, RewindCommands.isRewind(action) {
            performRewindKey(action, key: name)
            return
        }

        if let action = spec.action, KeyCommands.isKey(action) {
            typeKey(action, name: name)
            return
        }

        if let action = spec.action, PointerCommands.isPointer(action) {
            if !LightroomAccessibility.isTrusted(prompt: true) {
                triggerActionDisplay(name: name, label: "Allow Accessibility to click", phase: .blocked, duration: 4)
                return
            }
            PointerDriver.perform(action)
            triggerActionDisplay(name: name, label: CommandDatabase.shared.label(for: action), phase: .sent)
            return
        }

        if let psAction = spec.ps {
            runPhotoshopAction(psAction, name: name)
            return
        }

        // Button actions always fire. Safe Setup only mutes knobs, rings, and balls
        // so mapping a control cannot accidentally grade the photo. but Export, Next,
        // Upright, and Grab Still still work.
        if let action = spec.action, action.hasPrefix("reset_knob:") {
            let knob = String(action.dropFirst("reset_knob:".count))
            guard let param = currentHelpProfile().knobs[knob]?.param,
                  CommandDatabase.shared.commands["Reset" + param] != nil else {
                triggerActionDisplay(name: name, label: "This knob has no parameter reset", phase: .blocked)
                return
            }
            guard LightroomBridge.shared.isConnected else {
                triggerActionDisplay(name: name, label: "Lightroom isn’t connected", phase: .blocked)
                return
            }
            pendingNudges[param] = nil
            for tb in trackballs.values { tb.stopInertia() }
            for tb in overlayTrackballs.values { tb.stopInertia() }
            PanelDiagnostics.record("knob reset \(knob) parameter=\(param)")
            LightroomBridge.shared.fireAction("Reset" + param)
            RewindEngine.shared.noteStructuralEdit("Reset" + param, label: CommandDatabase.shared.label(for: "Reset" + param))
            // Stay in the knob view so SwiftUI can animate from the previous position.
            beginKnobResetReadout(control: knob, param: param)
            return
        }
        if let action = spec.action, action.hasPrefix(WheelReset.prefix) {
            resetWheel(String(action.dropFirst(WheelReset.prefix.count)), key: name)
            return
        }

        if let action = spec.action, LightroomMenuActions.item(action) != nil {
            runMenuAction(action, key: name)
            return
        }

        if let action = spec.action {
            let label = CommandDatabase.shared.label(for: action)
            guard LightroomBridge.shared.isConnected else {
                triggerActionDisplay(name: name, label: "\(label) · Lightroom isn’t connected", phase: .blocked)
                return
            }
            // Undo, Reset, Paste…: a coasting trackball must not re-apply the old grade.
            for tb in trackballs.values { tb.stopInertia() }
            for tb in overlayTrackballs.values { tb.stopInertia() }
            LightroomBridge.shared.fireAction(action)
            // A mask, a crop, a preset, a paste: the value stream cannot describe these, so the
            // trail takes a whole settings table around them instead.
            RewindEngine.shared.noteStructuralEdit(action, label: label)
            if action == BracketCommands.mark {
                noteBracketMark()
                triggerActionDisplay(
                    name: name,
                    label: "Bracket · \(bracketCount) photo\(bracketCount == 1 ? "" : "s") · Grab Still sends them",
                    phase: .sent,
                    duration: 3
                )
            } else if SlowCommands.isSlow(action) {
                triggerActionDisplay(name: name, label: "\(label) · Lightroom is working…", phase: .working, duration: 3)
            } else {
                triggerActionDisplay(name: name, label: label, phase: .sent)
            }
            if let enter = spec.enter_layer {
                toggledLayers.insert(enter)
                activeLayers.insert(enter)
                updateLeds()
                updateStatusMessage()
            }
            noteMaskCommand(action)
        }
    }

    private func runPhotoshopAction(_ psAction: String, name: String) {
            let returning = PhotoshopBridge.shared.isPhotoshopLikelyHoldingDocument()
            // Grab Still means "send the bracket" once photos have been gathered, so
            // the blend workflow needs no second key.
            let sendsBracket = !returning && bracketCount > 0 && psAction == "smart_roundtrip"
            let resolved = sendsBracket ? "bracket_roundtrip" : psAction
            let opening = sendsBracket
                ? "Sending \(bracketCount) photo\(bracketCount == 1 ? "" : "s") to Photoshop…"
                : "Sending to Photoshop…"
            triggerActionDisplay(
                name: name,
                label: returning ? "Saving back to Lightroom…" : opening,
                phase: .working,
                hold: true
            )
            PhotoshopBridge.shared.autoAlign = AppSettings.shared.autoAlignLayers
            if sendsBracket { clearBracketCount() }
            PhotoshopBridge.shared.executeAction(resolved) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let message):
                        self.triggerActionDisplay(name: name, label: message, phase: .done)
                    case .failure(let error):
                        self.triggerActionDisplay(name: name, label: error.localizedDescription, phase: .failed, duration: 8)
                    }
                }
            }
    }

    /// Keys and the command palette both come through here.
    public func runKeyCommand(_ id: String, key: String = "PALETTE") {
        guard !outputBlocked else { return }
        if Self.photoshopActionIDs.contains(id) {
            runPhotoshopAction(id, name: key)
        } else if LightroomMenuActions.item(id) != nil {
            runMenuAction(id, key: key)
        } else if id.hasPrefix(WheelReset.prefix) {
            resetWheel(String(id.dropFirst(WheelReset.prefix.count)), key: key)
        } else if RewindCommands.isRewind(id) {
            performRewindKey(id, key: key)
        } else if KeyCommands.isKey(id) {
            typeKey(id, name: key)
        } else {
            LightroomBridge.shared.fireAction(id)
            RewindEngine.shared.noteStructuralEdit(id, label: CommandDatabase.shared.label(for: id))
            noteMaskCommand(id)
        }
    }

    /// Type a key into Lightroom. It needs Accessibility, like every other thing PanaLux does by
    /// posting events, so say so plainly instead of doing nothing when it is missing.
    private func typeKey(_ id: String, name: String, hold: Bool = false) {
        let title = CommandDatabase.shared.label(for: id)
        guard let parsed = KeyCommands.parse(id) else {
            triggerActionDisplay(name: name, label: "\(id) isn’t a key PanaLux can type", phase: .failed, duration: 4)
            return
        }
        guard LightroomAccessibility.isTrusted(prompt: true) else {
            triggerActionDisplay(name: name, label: "Allow Accessibility to type keys", phase: .blocked, duration: 4)
            return
        }
        guard LightroomKeys.lightroomPID != nil else {
            triggerActionDisplay(name: name, label: "\(title) · Lightroom isn’t running", phase: .blocked)
            return
        }
        let sent = LightroomKeys.press(parsed.key, flags: parsed.flags)
        if id == "key:\\" || name == "BYPASS" {
            isBeforeViewActive.toggle()
            updateLEDs()
        }
        triggerActionDisplay(name: name, label: title, phase: sent ? .sent : .failed, hold: hold)
    }

    private func runMenuAction(_ action: String, key: String) {
        let title = LightroomMenuActions.title(action) ?? action
        triggerActionDisplay(name: key, label: "\(title)…", phase: .working, hold: true)
        LightroomMenuActions.run(action) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .done(let text):
                if action == BracketCommands.clearAction { self.clearBracketCount() }
                self.triggerActionDisplay(name: key, label: text, phase: .done)
                LightroomBridge.shared.markStale()
                LightroomBridge.shared.requestFullRefresh(force: true)
            case .failed(let text):
                self.triggerActionDisplay(name: key, label: text, phase: .failed, duration: 4)
            }
        }
    }

    private func holdBinding(for name: String) -> ButtonBinding? {
        if let overlay = layerButtonOverride(for: name), overlay.hasHoldFunctionSet {
            return overlay
        }
        return profile.buttons[name]
    }

    private func engageHold(_ name: String) {
        engagedHolds.insert(name)
        let spec = holdBinding(for: name)
        GuideController.shared.hardwareEvent(.holdEngaged(name))

        if let press = spec?.hold_action {
            if RewindCommands.isRewind(press) {
                performRewindKey(press, key: name)
                updateStatusMessage()
                return
            }
            if outputBlocked {
                triggerActionDisplay(name: name, label: "Paused · \(CommandDatabase.shared.label(for: press))", phase: .blocked, hold: true)
            } else if Self.photoshopActionIDs.contains(press) || LightroomMenuActions.item(press) != nil || press.hasPrefix(WheelReset.prefix) {
                runKeyCommand(press, key: name)
            } else if KeyCommands.isKey(press) {
                typeKey(press, name: name, hold: true)
            } else if PointerCommands.isPointer(press) {
                PointerDriver.perform(press)
                triggerActionDisplay(name: name, label: CommandDatabase.shared.label(for: press), phase: .sent, hold: true)
            } else {
                LightroomBridge.shared.fireAction(press)
                triggerActionDisplay(name: name, label: "\(CommandDatabase.shared.label(for: press)) while held", phase: .sent, hold: true)
            }
            updateStatusMessage()
            return
        }

        if let picker = spec?.hold_picker, MaskToolPicker.supports(picker) {
            beginPicker(button: name)
            return
        }

        if spec?.holdProgram != nil {
            heldProgramButton = name
            presentHoldHUD()
            updateLeds()
            updateStatusMessage()
            return
        }

        if let holdLayer = spec?.hold_layer {
            activeLayers.insert(holdLayer)
            if holdLayer == "REWIND" { beginRewind() }
            presentHoldHUD()
            updateLeds()
            updateStatusMessage()
            return
        }

        if let mod = spec?.modifier {
            heldModifiers.insert(mod)
            presentHoldHUD()
            updateStatusMessage()
        }
    }

    private func disengageHold(_ name: String) {
        engagedHolds.remove(name)
        let spec = holdBinding(for: name)

        if spec?.hold_action != nil {
            if let release = spec?.release_action, !outputBlocked {
                if RewindCommands.isRewind(release) {
                    performRewindKey(release, key: name)
                } else if KeyCommands.isKey(release) {
                    typeKey(release, name: name)
                } else if PointerCommands.isPointer(release) {
                    PointerDriver.perform(release)
                } else {
                    LightroomBridge.shared.fireAction(release)
                }
            }
            collapseToIdle()
            updateStatusMessage()
            return
        }

        if spec?.hold_picker != nil && activePickerButton == name {
            commitPicker()
            return
        }

        if spec?.holdProgram != nil && heldProgramButton == name {
            heldProgramButton = nil
            if latchedProgramButton == nil {
                collapseToIdle()
            }
            updateLeds()
            updateStatusMessage()
            return
        }

        if let holdLayer = spec?.hold_layer {
            // A layer that was also tapped on stays on after the hold ends.
            if !toggledLayers.contains(holdLayer) {
                activeLayers.remove(holdLayer)
                if holdLayer == "MASK" { endMaskPlacing(announce: false) }
                // Letting go leaves the photo wherever the playhead is. That is the point.
                if holdLayer == "REWIND" { RewindEngine.shared.endRewind() }
            }
            collapseToIdle()
            updateLeds()
            updateStatusMessage()
            return
        }

        if let mod = spec?.modifier {
            heldModifiers.remove(mod)
            collapseToIdle()
            updateStatusMessage()
        }
    }

    private func toggleLatchedProgram(button: String, program: AnalogProgram) {
        if latchedProgramButton == button {
            latchedProgramButton = nil
            collapseToIdle()
        } else {
            latchedProgramButton = button
            collapseTimer?.invalidate()
            currentDisplayMode = .layerBanner(
                layer: PanelLayout.label(forControl: button),
                variant: nil,
                hint: holdSubtitle(for: program),
                chips: connectionChips(forProgram: program),
                latched: true,
                grid: knobGrid(forProgram: program)
            )
        }
        updateLeds()
        updateStatusMessage()
    }

    public func currentAnalogProgram() -> AnalogProgram? {
        if let held = heldProgramButton, let program = profile.buttons[held]?.holdProgram {
            return program
        }
        if let latched = latchedProgramButton, let program = profile.buttons[latched]?.tapProgram {
            return program
        }
        return nil
    }

    public func currentProgramButton() -> String? {
        heldProgramButton ?? latchedProgramButton
    }

    private func currentProgramLabel() -> String {
        if let name = currentProgramButton() {
            return PanelLayout.label(forControl: name)
        }
        return "Program"
    }

    /// Map a function-set focus name (Y Lift, Blacks, hardware ids) to a MIDI2LR param.
    func resolveProgramParam(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if CommandDatabase.shared.commands[trimmed] != nil {
            return trimmed
        }
        let compact = trimmed.uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        let aliases: [String: String] = [
            "Y_LIFT": "Blacks", "YLIFT": "Blacks", "BLACKS": "Blacks",
            "Y_GAMMA": "Whites", "YGAMMA": "Whites", "WHITES": "Whites",
            "Y_GAIN": "Exposure", "YGAIN": "Exposure", "EXPOSURE": "Exposure",
            "VIGNETTE": "VignetteAmount", "VIGNETTEAMOUNT": "VignetteAmount", "VIGNETTE_AMOUNT": "VignetteAmount",
            "TEMPERATURE": "Temperature", "TEMP": "Temperature",
            "TINT": "Tint", "CONTRAST": "Contrast", "HIGHLIGHTS": "Highlights",
            "SHADOWS": "Shadows", "SATURATION": "Saturation", "VIBRANCE": "Vibrance"
        ]
        return aliases[compact] ?? trimmed
    }

    private func handleKnob(_ name: String, deltaUnits: Double, isFine: Bool) {
        TrackballLightAnimator.shared.noteKnob(name)
        var binding: KnobBinding? = nil
        var context: String? = nil

        if let temp = tempFocusParam, name == AppSettings.shared.focusDialControl {
            binding = KnobBinding(param: temp)
            context = "Focus dial"
        }

        if binding == nil, let program = currentAnalogProgram(), program.appliesToKnobs {
            if program.scope == "focus", let param = program.focusParam, !param.isEmpty {
                binding = KnobBinding(param: resolveProgramParam(param))
                context = currentProgramLabel()
            } else if let b = program.knobs?[name] {
                binding = b
                context = currentProgramLabel()
            }
        }

        if binding == nil {
            for layer in layerPriority {
                if let b = knobsForLayer(layer, variant: activeVariants[layer])?[name] {
                    binding = b
                    if let variant = activeVariants[layer], !(layer == "MASK" && AppSettings.shared.mirrorMaskToBase) {
                        context = "\(layerTitle(layer)) · \(variant)"
                    } else {
                        context = layerTitle(layer)
                    }
                    break
                }
            }
        }
        if binding == nil {
            if overlayLayerName == "MASK" {
                notice(name, "Not assigned in Masks")
                return
            }
            binding = profile.knobs[name]
        }

        guard let b = binding else {
            notice(name, "Not assigned. set it in Map")
            return
        }
        if RewindCommands.isRewind(b.param) {
            driveRewind(b.param, control: name, deltaUnits: deltaUnits)
            return
        }
        guard !RewindEngine.shared.isRewinding else { return }
        GuideController.shared.hardwareEvent(.analogMoved(name))
        driveAnalog(control: name, param: b.param, scale: b.scale, deltaUnits: deltaUnits, isFine: isFine, isRing: false, context: context)
    }

    private func handleRing(_ name: String, deltaUnits: Double, isFine: Bool) {
        var binding: RingBinding? = nil
        var context: String? = nil

        if maskPlacing, let b = profile.layers["MASK"]?.rings?[name] {
            binding = b
            context = "Place"
        }

        if binding == nil, let program = currentAnalogProgram(), program.appliesToWheels {
            if program.scope == "focus", let param = program.focusParam, !param.isEmpty {
                binding = RingBinding(param: resolveProgramParam(param))
                context = currentProgramLabel()
            } else if let b = program.rings?[name] {
                binding = b
                context = currentProgramLabel()
            }
        }

        if binding == nil {
            for layer in layerPriority {
                if let b = profile.layers[layer]?.rings?[name] {
                    binding = b
                    context = layerTitle(layer)
                    break
                }
            }
        }
        if binding == nil {
            if overlayLayerName == "MASK" {
                notice(name, "Not assigned in Masks")
                return
            }
            binding = profile.rings[name]
        }
        guard let b = binding else {
            notice(name, "Not assigned. set it in Map")
            return
        }
        if RewindCommands.isRewind(b.param) {
            driveRewind(b.param, control: name, deltaUnits: deltaUnits)
            return
        }
        if PointerCommands.isSize(b.param) {
            drivePointerResize(control: name, delta: deltaUnits)
            return
        }
        guard !RewindEngine.shared.isRewinding else { return }
        GuideController.shared.hardwareEvent(.analogMoved(name))
        driveAnalog(control: name, param: b.param, scale: b.scale, deltaUnits: deltaUnits, isFine: isFine, isRing: true, context: context)
    }

    /// Shared path for knobs and rings: repeat commands, readback, preview, and the HUD.
    private func driveAnalog(control name: String, param: String, scale: Double, deltaUnits: Double,
                             isFine: Bool, isRing: Bool, context: String?) {
        if PointerCommands.isPointer(param) { return }
        let label = CommandDatabase.shared.label(for: param)
        let who = context.map { "\($0) · \(PanelLayout.label(forControl: name))" } ?? PanelLayout.label(forControl: name)
        activeDialReadout = (param, who)
        let angle = isRing
            ? bumpSpin(for: name, delta: deltaUnits, gain: 2.5, cap: 8.0)
            : bumpSpin(for: name, delta: deltaUnits, gain: 0.08, cap: 0.4)

        func show(_ value: Double, _ text: String, _ paramText: String) {
            let mode: ActiveDisplayMode = isRing
                ? .ring(name: who, param: paramText, value: value, displayValue: text, isFine: isFine, angleDegrees: angle)
                : .knob(name: who, param: paramText, value: value, displayValue: text, isFine: isFine, angleDegrees: angle)
            publishAnalogHUD(name: name, param: paramText, display: text, mode: mode)
        }

        if let pair = RepeatCommands.pair(for: param) {
            driveRepeat(control: name, pair: pair, deltaUnits: deltaUnits, isRing: isRing, show: { text in show(0.5, text, label) })
            return
        }

        guard shouldSendToLightroom else {
            let current = LightroomBridge.shared.value(for: param)
            let suffix = outputBlocked ? blockedWord : "Preview"
            show(current, formatValue(param: param, value: current), "\(label) (\(suffix))")
            return
        }

        guard LightroomBridge.shared.isConnected else {
            notice(name, "\(label) · Lightroom isn’t connected")
            return
        }

        // Never send an absolute value we have not read from Lightroom yet.
        let bridge = LightroomBridge.shared
        if bridge.hasValue(param), !bridge.isFresh(param), bridge.secondsSinceStale < 0.7 {
            // Just after Undo or Reset: wait for Lightroom's new value instead of reverting it.
            show(bridge.value(for: param), "…", "\(label) (Updating)")
            return
        }
        let fineFactor = isFine ? AppSettings.shared.fineMultiplier : 1.0
        let step = deltaUnits * scale * fineFactor * ParameterFeel.travel(for: param, range: LightroomBridge.shared.parameterRange(for: param))

        if !bridge.hasValue(param) {
            let now = Date()
            // Hold on to the turn rather than dropping it. Nothing is sent until
            // Lightroom says where the slider is, and then this is applied from there.
            pendingNudges[param, default: 0] += step

            guard let asked = readbackAttempts[param] else {
                readbackAttempts[param] = now
                bridge.requestFullRefresh(force: true)
                show(0.5, "…", "\(label) (Reading)")
                return
            }
            let waited = now.timeIntervalSince(asked)
            if waited < readbackPatience {
                // One refresh can be missed while Lightroom is busy importing or rendering.
                if waited > 0.6, !readbackRetried.contains(param) {
                    readbackRetried.insert(param)
                    bridge.requestFullRefresh(force: true)
                }
                show(0.5, "…", "\(label) (Reading)")
                return
            }
            // Lightroom never reported this one. MIDI2LR only takes absolute positions,
            // so the only way left is to assume the middle. Say so once first.
            if !readbackGaveUp.contains(param) {
                readbackGaveUp.insert(param)
                notice(name, "\(label) · Lightroom didn’t report a value. starting from the middle")
                return
            }
            pendingNudges[param] = nil
        }

        let newVal = bridge.nudgeParameter(param, delta: step)
        lastAdjustmentTimestamp = Date()
        show(newVal, formatValue(param: param, value: newVal), label)
    }

    // MARK: - Rewind

    private var scrubAutoEndTimer: DispatchWorkItem?

    private func scheduleScrubAutoEnd() {
        guard !activeLayers.contains("REWIND") else { return }
        scrubAutoEndTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !self.activeLayers.contains("REWIND"), RewindEngine.shared.isRewinding {
                RewindEngine.shared.endRewind(announce: false)
                self.collapseToIdle()
            }
        }
        scrubAutoEndTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// A knob or ring mapped to the trail. Like every other binding, this is whatever the
    /// map says it is — the factory map puts scrub on the right, landmarks on the left and tangents in the center.
    private func driveRewind(_ command: String, control: String, deltaUnits: Double) {
        GuideController.shared.hardwareEvent(.analogMoved(control))
        RewindLEDAnimator.shared.noteWheelDelta(command: command, deltaUnits: deltaUnits)
        RewindEdgeAnimator.shared.noteWheelDelta(command: command, deltaUnits: deltaUnits)
        let rewind = RewindEngine.shared
        if !rewind.isRewinding {
            beginRewind()
        }
        if !activeLayers.contains("REWIND") {
            scheduleScrubAutoEnd()
        }
        guard rewind.isRewinding else {
            notice(control, activeLayers.contains("REWIND") ? "Waiting for Lightroom’s photo · check PanaLux Bridge" : "Hold Undo to rewind")
            return
        }
        guard !outputBlocked else {
            notice(control, "\(blockedWord) · \(RewindCommands.title(command))")
            return
        }
        // The feel is a setting, so it is read every turn: change it and the next click obeys.
        rewind.clickUnits = AppSettings.shared.rewindClickUnits
        rewind.acceleration = AppSettings.shared.rewindAcceleration
        switch command {
        case RewindCommands.landmarks, RewindCommands.tangents:
            var accumulator = repeatAccumulators[control] ?? (0, .distantPast)
            if accumulator.units * deltaUnits < 0 { accumulator.units = 0 }
            accumulator.units += deltaUnits
            let steps = Int(accumulator.units / max(1, rewind.clickUnits))
            accumulator.units -= Double(steps) * max(1, rewind.clickUnits)
            repeatAccumulators[control] = accumulator
            for _ in 0..<min(32, abs(steps)) {
                if command == RewindCommands.landmarks { rewind.step(forward: steps > 0) }
                else { rewind.hopTangent(forward: steps > 0) }
            }
        case RewindCommands.speed: rewind.adjustSpeed(units: deltaUnits, fine: false)
        case RewindCommands.speedFine: rewind.adjustSpeed(units: deltaUnits, fine: true)
        default: rewind.scrub(units: deltaUnits)
        }
    }

    /// Start the hold: the readout takes over and the playhead parks on the tip.
    private func beginRewind() {
        let rewind = RewindEngine.shared
        rewind.knobParams = currentKnobParams()
        if rewind.photoID == nil, let id = LightroomBridge.shared.activePhotoID {
            rewind.setActivePhoto(id)
        }
        if rewind.photoID == nil {
            LightroomBridge.shared.requestFullRefresh()
            let fallbackID = LightroomBridge.shared.activePhotoID ?? "current_photo"
            rewind.setActivePhoto(fallbackID)
        }
        rewind.beginRewind()
        collapseTimer?.invalidate()
        guard rewind.isRewinding else {
            // No trail yet: Lightroom has not said which photo is on screen, which an older
            // PanaLux Bridge never does.
            triggerActionDisplay(name: "UNDO", label: rewind.historyUnavailableMessage ?? "Rewind is waiting for Lightroom", phase: .blocked, hold: true)
            return
        }
        currentDisplayMode = .rewind(rewind.state)
    }

    /// A key mapped to the trail.
    private func performRewindKey(_ command: String, key: String) {
        let rewind = RewindEngine.shared
        if command == RewindCommands.mark || command == RewindCommands.branch {
            // Marking and branching are worth doing whether or not the hold is on.
            if command == RewindCommands.mark {
                rewind.mark()
                triggerActionDisplay(name: key, label: "Marked · Rewind snaps here", phase: .done)
            } else {
                rewind.startBranch(reason: "Branched")
                triggerActionDisplay(name: key, label: "New branch · nothing was lost", phase: .done)
            }
            return
        }
        guard rewind.isRewinding else {
            triggerActionDisplay(name: key, label: "Hold Undo to rewind", phase: .blocked)
            return
        }
        switch command {
        case RewindCommands.tip: rewind.jumpToTip()
        case RewindCommands.play: rewind.play(forward: true)
        case RewindCommands.playReverse: rewind.play(forward: false)
        case RewindCommands.pause: rewind.pausePlayback()
        case RewindCommands.tangentPrevious: rewind.hopTangent(forward: false)
        case RewindCommands.tangentNext: rewind.hopTangent(forward: true)
        case RewindCommands.previous: rewind.step(forward: false)
        case RewindCommands.next: rewind.step(forward: true)
        case RewindCommands.peek: rewind.setPeeking(true)
        case RewindCommands.unpeek: rewind.setPeeking(false)
        default: break
        }
    }

    private func driveRepeat(control: String, pair: RepeatCommands.Pair, deltaUnits: Double, isRing: Bool, show: (String) -> Void) {
        let threshold = isRing ? 40.0 : 16.0
        var acc = repeatAccumulators[control] ?? (0, .distantPast)
        if (acc.units > 0) != (deltaUnits > 0) { acc.units = 0 }
        acc.units += deltaUnits
        let now = Date()
        guard abs(acc.units) >= threshold, now.timeIntervalSince(acc.lastFire) > 0.06 else {
            repeatAccumulators[control] = acc
            return
        }
        let clockwise = acc.units > 0
        acc.units -= clockwise ? threshold : -threshold
        acc.lastFire = now
        repeatAccumulators[control] = acc
        let command = clockwise ? pair.clockwise : pair.counterClockwise
        let stepLabel = CommandDatabase.shared.label(for: command)
        if !shouldSendToLightroom {
            show(outputBlocked ? blockedWord : "Preview")
            return
        }
        guard LightroomBridge.shared.isConnected else {
            notice(control, "Lightroom isn’t connected")
            return
        }
        LightroomBridge.shared.fireAction(command)
        show(clockwise ? "\(stepLabel) ›" : "‹ \(stepLabel)")
    }

    private func handleTrackballAxis(_ axisName: String, deltaUnits: Double, isFine: Bool) {
        guard !RewindEngine.shared.isRewinding else { return }
        guard let lastUnderscore = axisName.lastIndex(of: "_") else { return }
        let ballName = String(axisName[..<lastUnderscore])
        let axis = String(axisName[axisName.index(after: lastUnderscore)...])
        let fineFactor = isFine ? AppSettings.shared.fineMultiplier : 1.0
        let scaledDelta = deltaUnits * fineFactor
        GuideController.shared.hardwareEvent(.analogMoved(ballName))
        if AppSettings.shared.trackballRadiantLighting {
            TrackballLightAnimator.shared.noteMotion(ballName: ballName, axis: axis, delta: scaledDelta)
        }

        if maskPlacing || overlayLayerName == "MASK" {
            handleMaskBall(ballName: ballName, axis: axis, scaledDelta: scaledDelta, isFine: isFine)
            return
        }

        if let program = currentAnalogProgram(), program.appliesToWheels,
           program.scope == "focus", let param = program.focusParam, !param.isEmpty {
            let signed = (axis == "Y") ? scaledDelta : scaledDelta * 0.35
            applyFocusedAnalog(param: resolveProgramParam(param), step: signed * 0.0003, isFine: isFine)
            return
        }

        if let program = currentAnalogProgram(), program.appliesToWheels,
           let ball = program.balls?[ballName], let param = ball.param {
            if drivePointerIfNeeded(ballName: ballName, param: param, axis: axis, scaledDelta: scaledDelta, binding: ball) { return }
            applyFocusedAnalog(param: resolveProgramParam(param), step: ballSliderStep(axis, scaledDelta), isFine: isFine)
            return
        }

        if let program = currentAnalogProgram(), program.appliesToWheels,
           let ball = program.balls?[ballName] {
            applyProgramBall(named: ballName, binding: ball, axis: axis, scaledDelta: scaledDelta, isFine: isFine)
            return
        }

        for layer in layerPriority {
            if let ball = profile.layers[layer]?.balls?[ballName] {
                if let param = ball.param {
                    if drivePointerIfNeeded(ballName: ballName, param: param, axis: axis, scaledDelta: scaledDelta, binding: ball) { return }
                    applyFocusedAnalog(param: param, step: ballSliderStep(axis, scaledDelta), isFine: isFine, title: layerTitle(layer))
                    return
                }
                applyProgramBall(named: ballName, binding: ball, axis: axis, scaledDelta: scaledDelta, isFine: isFine, keyPrefix: layer, title: layerTitle(layer))
                return
            }
        }

        if let param = profile.balls[ballName]?.param {
            if drivePointerIfNeeded(ballName: ballName, param: param, axis: axis, scaledDelta: scaledDelta, binding: profile.balls[ballName]!) { return }
            applyFocusedAnalog(param: param, step: ballSliderStep(axis, scaledDelta), isFine: isFine,
                               title: PanelLayout.label(forControl: ballName))
            return
        }

        guard let engine = trackballs[ballName] else {
            notice(ballName, "Not assigned. set it in Map")
            return
        }

        let dx = (axis == "X") ? scaledDelta : 0.0
        let dy = (axis == "Y") ? scaledDelta : 0.0
        let (turns, sat) = engine.push(dx: dx, dy: dy)

        if shouldSendToLightroom {
            LightroomBridge.shared.setAngle(engine.hueParam, turns: turns)
            LightroomBridge.shared.setParameter(engine.satParam, value: sat)
        }

        showBall(ballName, engine.currentState, isFine)
    }

    private func showBall(_ name: String, _ state: TrackballState, _ isFine: Bool) {
        let hue = Int((state.hueAngle * 360).rounded())
        let sat = Int((state.saturation * 100).rounded())
        let control = PanelLayout.balls.contains(name) ? name : "TB_PROGRAM"
        let title: String
        switch name {
        case "TB_LIFT": title = "Shadows"
        case "TB_GAMMA": title = "Midtones"
        case "TB_GAIN": title = "Highlights"
        default: title = name
        }
        publishAnalogHUD(
            name: control,
            param: title,
            display: "\(hue)° · \(sat)%",
            mode: .trackball(name: name, state: state, isFine: isFine, companion: nil)
        )
    }

    // MARK: - Program analog helpers

    /// A ball bound to one slider: rolling up/down is the main axis, sideways is gentler.
    private func ballSliderStep(_ axis: String, _ scaledDelta: Double) -> Double {
        ((axis == "Y") ? scaledDelta : scaledDelta * 0.35) * 0.0003
    }

    private func applyFocusedAnalog(param: String, step: Double, isFine: Bool, title: String? = nil) {
        let label = CommandDatabase.shared.label(for: param)
        let angle = bumpSpin(for: param, delta: step * 40, gain: 0.08, cap: 0.4)
        if shouldSendToLightroom {
            let newVal = LightroomBridge.shared.nudgeParameter(param, delta: step)
            currentDisplayMode = .knob(
                name: title ?? currentProgramLabel(), param: label, value: newVal,
                displayValue: formatValue(param: param, value: newVal), isFine: isFine, angleDegrees: angle
            )
        } else {
            let currentVal = LightroomBridge.shared.value(for: param)
            currentDisplayMode = .knob(
                name: title ?? currentProgramLabel(), param: "\(label) (\(outputBlocked ? blockedWord : "Preview"))", value: currentVal,
                displayValue: formatValue(param: param, value: currentVal), isFine: isFine, angleDegrees: angle
            )
        }
        scheduleCollapse()
    }

    private func applyProgramBall(named ballName: String, binding: BallBinding, axis: String, scaledDelta: Double,
                                  isFine: Bool, keyPrefix: String? = nil, title: String? = nil) {
        let key = "\(keyPrefix ?? currentProgramButton() ?? "p"):\(ballName)"
        let engine: TrackballEngine
        if let existing = overlayTrackballs[key],
           existing.hueParam == binding.hue,
           existing.satParam == binding.sat {
            engine = existing
        } else {
            engine = TrackballEngine(
                name: ballName,
                hueParam: binding.hue,
                satParam: binding.sat,
                radius: binding.radius,
                invertX: binding.invert_x,
                invertY: binding.invert_y
            )
            overlayTrackballs[key] = engine
        }

        let dx = (axis == "X") ? scaledDelta : 0.0
        let dy = (axis == "Y") ? scaledDelta : 0.0
        let (turns, sat) = engine.push(dx: dx, dy: dy)
        if shouldSendToLightroom {
            LightroomBridge.shared.setAngle(engine.hueParam, turns: turns)
            LightroomBridge.shared.setParameter(engine.satParam, value: sat)
        }
        showBall(title ?? currentProgramLabel(), engine.currentState, isFine)
    }

    /// Masks never fall through to Base color wheels. While placing, every ball is the pointer.
    private func handleMaskBall(ballName: String, axis: String, scaledDelta: Double, isFine: Bool) {
        if maskPlacing {
            _ = drivePointerIfNeeded(
                ballName: ballName,
                param: PointerCommands.move,
                axis: axis,
                scaledDelta: scaledDelta,
                binding: maskPlaceBinding()
            )
            return
        }
        guard let ball = profile.layers["MASK"]?.balls?[ballName] else {
            notice(ballName, "Idle while Masks is on")
            return
        }
        if let param = ball.param {
            if drivePointerIfNeeded(ballName: ballName, param: param, axis: axis, scaledDelta: scaledDelta, binding: ball) {
                return
            }
            applyFocusedAnalog(param: param, step: ballSliderStep(axis, scaledDelta), isFine: isFine, title: layerTitle("MASK"))
            return
        }
        applyProgramBall(
            named: ballName,
            binding: ball,
            axis: axis,
            scaledDelta: scaledDelta,
            isFine: isFine,
            keyPrefix: "MASK",
            title: layerTitle("MASK")
        )
    }

    private func maskPlaceBinding() -> BallBinding {
        let src = profile.layers["MASK"]?.balls?["TB_GAIN"]
            ?? profile.layers["MASK"]?.balls?["TB_LIFT"]
        var binding = BallBinding.slider(PointerCommands.move)
        binding.invert_x = src?.invert_x ?? true
        binding.invert_y = src?.invert_y ?? true
        binding.radius = src?.radius ?? 3000
        return binding
    }

    private func noteMaskCommand(_ action: String) {
        guard action.hasPrefix("Mask") else { return }
        toggledLayers.insert("MASK")
        activeLayers.insert("MASK")
        endMaskPlacing(announce: false)
        updateLeds()
        updateStatusMessage()
    }

    private func beginMaskPlacing() {
        maskPlacing = true
        triggerActionDisplay(
            name: "MASK",
            label: "Place · balls move · rings size · Loop clicks · tap Add Node to grade",
            phase: .sent,
            duration: 4.2
        )
        updateStatusMessage()
    }

    private func endMaskPlacing(announce: Bool = true) {
        guard maskPlacing else { return }
        maskPlacing = false
        PointerDriver.cancel()
        if announce {
            triggerActionDisplay(
                name: "MASK",
                label: "Mask parked · knobs and balls grade it",
                phase: .done,
                duration: 3
            )
        }
        updateStatusMessage()
    }

    // MARK: - Mask tool wheel

    private func beginPicker(button: String) {
        collapseTimer?.invalidate()
        currentDisplayMode = .idle
        activePickerButton = button
        pickerRingAcc = 0
        pickerCombineAcc = 0
        pickerAimReset()
        let index = lastPickerIndex
        ToolWheelSession.shared.present(
            ownerLabel: PanelLayout.label(forControl: button),
            index: index,
            combine: lastPickerCombine
        )
        updateLeds()
        updateStatusMessage()
    }

    private func commitPicker() {
        let session = ToolWheelSession.shared
        let tool = MaskToolPicker.tool(at: session.selectedIndex)
        guard let command = tool.command(combine: session.combine) else {
            let label = "\(session.combine.title) \(tool.title) isn’t available · choose another mask tool"
            cancelPicker(commit: false)
            triggerActionDisplay(name: "ADD_NODE", label: label, phase: .blocked, duration: 4)
            updateLeds()
            updateStatusMessage()
            return
        }
        lastPickerIndex = session.selectedIndex
        lastPickerCombine = session.combine
        let label = "\(session.combine.title) \(tool.title)"
        cancelPicker(commit: false)
        if outputBlocked {
            triggerActionDisplay(name: command, label: "\(blockedWord) · \(label)", phase: .blocked)
            updateLeds()
            updateStatusMessage()
            return
        }
        guard LightroomBridge.shared.isConnected else {
            triggerActionDisplay(name: command, label: "\(label) · Lightroom isn’t connected", phase: .blocked)
            updateLeds()
            updateStatusMessage()
            return
        }
        LightroomBridge.shared.fireAction(command)
        toggledLayers.insert("MASK")
        activeLayers.insert("MASK")
        endMaskPlacing(announce: false)
        if SlowCommands.isSlow(command) {
            triggerActionDisplay(name: command, label: "\(label) · Lightroom is working…", phase: .working, duration: 3)
        } else if tool.placesWithPointer {
            triggerActionDisplay(
                name: command,
                label: "\(label) · place it with the mouse",
                phase: .sent,
                duration: 3.6
            )
        } else {
            triggerActionDisplay(name: command, label: label, phase: .sent)
        }
        updateLeds()
        updateStatusMessage()
    }

    private func cancelPicker(commit: Bool) {
        if commit, activePickerButton != nil {
            commitPicker()
            return
        }
        activePickerButton = nil
        pickerRingAcc = 0
        pickerCombineAcc = 0
        ToolWheelSession.shared.hide()
    }

    private func pickerAimReset() {
        ToolWheelSession.shared.aimX = 0
        ToolWheelSession.shared.aimY = 0
        ToolWheelSession.shared.aimActive = false
    }

    private func handlePickerAnalog(_ control: String, kind: MotionKind, units: Double, isFine: Bool) {
        GuideController.shared.hardwareEvent(.analogMoved(control))
        let session = ToolWheelSession.shared
        if kind == .ring && control == MaskCombine.ringControl {
            stepPickerCombine(units: units, isFine: isFine)
            return
        }
        if kind == .ring || kind == .knob {
            let threshold = MaskToolPicker.detentUnits * (isFine ? 1.8 : 1.0)
            if (pickerRingAcc > 0) != (units > 0) { pickerRingAcc = 0 }
            pickerRingAcc += units
            let now = Date()
            guard abs(pickerRingAcc) >= threshold, now.timeIntervalSince(pickerLastStep) >= MaskToolPicker.minStepInterval else {
                return
            }
            let clockwise = pickerRingAcc > 0
            pickerRingAcc -= clockwise ? threshold : -threshold
            pickerLastStep = now
            session.selectedIndex = MaskToolPicker.steppedIndex(from: session.selectedIndex, clockwise: clockwise)
            session.tick += 1
            session.aimActive = false
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            return
        }
        if kind == .trackball {
            guard let lastUnderscore = control.lastIndex(of: "_") else { return }
            let axis = String(control[control.index(after: lastUnderscore)...])
            let signed = (axis == "X") ? units : units
            if axis == "X" {
                session.aimX += (profile.balls["TB_GAIN"]?.invert_x == false ? signed : -signed)
            } else {
                session.aimY += (profile.balls["TB_GAIN"]?.invert_y == false ? signed : -signed)
            }
            if let aimed = MaskToolPicker.index(aiming: session.aimX, dy: session.aimY) {
                session.aimActive = true
                if aimed != session.selectedIndex {
                    session.selectedIndex = aimed
                    session.tick += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        }
    }

    private func drivePointerIfNeeded(ballName: String, param: String, axis: String, scaledDelta: Double, binding: BallBinding) -> Bool {
        guard PointerCommands.isMove(param) else { return false }
        if !LightroomAccessibility.isTrusted(prompt: true) {
            notice(ballName, "Allow Accessibility to move the pointer")
            return true
        }
        let dx = axis == "X" ? (binding.invert_x ? -scaledDelta : scaledDelta) : 0
        let dy = axis == "Y" ? (binding.invert_y ? -scaledDelta : scaledDelta) : 0
        PointerDriver.move(dx: dx * 0.42, dy: dy * 0.42)
        lastAdjustmentTimestamp = Date()
        let mode: ActiveDisplayMode = .action(
            name: ballName,
            label: maskPlacing ? "Place" : "Pointer",
            phase: .sent
        )
        currentDisplayMode = mode
        collapseTimer?.invalidate()
        scheduleCollapse(after: 1.6)
        return true
    }

    private func stepPickerCombine(units: Double, isFine: Bool) {
        let session = ToolWheelSession.shared
        let threshold = MaskToolPicker.combineDetentUnits * (isFine ? 1.8 : 1.0)
        if (pickerCombineAcc > 0) != (units > 0) { pickerCombineAcc = 0 }
        pickerCombineAcc += units
        let now = Date()
        guard abs(pickerCombineAcc) >= threshold, now.timeIntervalSince(pickerLastStep) >= MaskToolPicker.minStepInterval else {
            return
        }
        let clockwise = pickerCombineAcc > 0
        pickerCombineAcc -= clockwise ? threshold : -threshold
        pickerLastStep = now
        session.combine = MaskToolPicker.steppedCombine(from: session.combine, clockwise: clockwise)
        lastPickerCombine = session.combine
        session.tick += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        updateStatusMessage()
        updateLeds()
    }

    private func drivePointerResize(control: String, delta: Double) {
        if !LightroomAccessibility.isTrusted(prompt: true) {
            notice(control, "Allow Accessibility to resize the mask")
            return
        }
        GuideController.shared.hardwareEvent(.analogMoved(control))
        PointerDriver.resize(delta: delta * 0.18)
        lastAdjustmentTimestamp = Date()
        currentDisplayMode = .action(name: control, label: "Mask size", phase: .sent)
        collapseTimer?.invalidate()
        scheduleCollapse(after: 1.6)
    }

    // MARK: - Notch HUD Triggers

    public var physicallyHeldControlNames: [String] {
        HardwareMap.shared.buttonBitToControl.compactMap { bit, name in
            pressedButtonBits.contains(bit) ? name : nil
        }
    }

    public var overlayLayerName: String? {
        layerPriority.first
    }

    public func isLayerLatched(_ layer: String) -> Bool {
        toggledLayers.contains(layer) && !engagedHolds.contains { profile.buttons[$0]?.hold_layer == layer }
    }

    private func triggerLayerBanner(layer: String, variant: String? = nil, hint: String? = nil) {
        collapseTimer?.invalidate()
        currentDisplayMode = bannerMode(for: layer, variant: variant, hint: hint)
    }

    private func bannerMode(for layer: String, variant: String? = nil, hint: String? = nil) -> ActiveDisplayMode {
        let v = variant ?? activeVariants[layer]
        let resolvedHint: String
        if layer == "MASK" {
            resolvedHint = hint ?? "Edit selected mask"
        } else {
            resolvedHint = hint ?? layerTitle(layer)
        }
        return .layerBanner(
            layer: layer,
            variant: v,
            hint: resolvedHint,
            chips: connectionChips(forLayer: layer),
            latched: isLayerLatched(layer),
            grid: knobGrid(forLayer: layer, variant: v)
        )
    }

    private func presentHoldHUD() {
        collapseTimer?.invalidate()
        // The grid is only worth reading if the numbers are current.
        LightroomBridge.shared.requestFullRefresh()
        if let mode = holdBannerMode() {
            currentDisplayMode = mode
        }
    }

    /// Lightroom reported new values while a mode is on screen. Redraw the grid so the
    /// numbers under your fingers are the numbers in Lightroom.
    private func refreshHoldBannerIfShowing() {
        guard case .layerBanner = currentDisplayMode else { return }
        if let mode = holdBannerMode() { currentDisplayMode = mode }
    }

    private func holdBannerMode() -> ActiveDisplayMode? {
        // While the trail is being scrubbed, the trail is the readout.
        if RewindEngine.shared.isRewinding {
            return .rewind(RewindEngine.shared.state)
        }
        if let held = heldProgramButton, let program = profile.buttons[held]?.holdProgram {
            return .layerBanner(
                layer: PanelLayout.label(forControl: held),
                variant: nil,
                hint: holdSubtitle(for: program),
                chips: connectionChips(forProgram: program),
                latched: false,
                grid: knobGrid(forProgram: program)
            )
        }
        if let layer = overlayLayerName {
            return bannerMode(for: layer)
        }
        if let latched = latchedProgramButton, let program = profile.buttons[latched]?.tapProgram {
            return .layerBanner(
                layer: PanelLayout.label(forControl: latched),
                variant: nil,
                hint: holdSubtitle(for: program),
                chips: connectionChips(forProgram: program),
                latched: true,
                grid: knobGrid(forProgram: program)
            )
        }
        if let mod = heldModifiers.first {
            return .layerBanner(layer: mod, variant: nil, hint: "Fine adjustments", chips: [String(format: "%.2g×", AppSettings.shared.fineMultiplier)], latched: false, grid: [])
        }
        if let temp = tempFocusParam {
            return .layerBanner(
                layer: "FOCUS",
                variant: nil,
                hint: CommandDatabase.shared.label(for: temp),
                chips: [PanelLayout.label(forControl: AppSettings.shared.focusDialControl)],
                latched: true,
                grid: []
            )
        }
        return nil
    }

    private func holdSubtitle(for program: AnalogProgram) -> String {
        if program.scope == "focus", let param = program.focusParam, !param.isEmpty {
            return CommandDatabase.shared.label(for: param)
        }
        return program.summary
    }

    private func connectionChips(forProgram program: AnalogProgram) -> [String] {
        var chips: [String] = []
        if program.appliesToKnobs { chips.append("Knobs") }
        if program.appliesToWheels { chips.append("Wheels") }
        return chips
    }

    private func connectionChips(forLayer layer: String) -> [String] {
        guard let spec = profile.layers[layer] else { return [] }
        var chips: [String] = []
        if let rings = spec.rings, !rings.isEmpty {
            chips.append(contentsOf: PanelLayout.rings.compactMap { id in
                rings[id].map { "\(PanelLayout.shortLabel(forControl: id)): \(CommandDatabase.shared.shortLabel(for: $0.param))" }
            })
        }
        if let balls = spec.balls, !balls.isEmpty { chips.append("Wheels") }
        if let buttons = spec.buttons, !buttons.isEmpty { chips.append("\(buttons.count) keys") }
        return Array(chips.prefix(4))
    }

    /// Knob map for a mode. Masks default to the same seats as Base.
    public func knobsForLayer(_ layer: String, variant: String? = nil) -> [String: KnobBinding]? {
        if layer == "MASK", AppSettings.shared.mirrorMaskToBase {
            let mirrored = LocalAdjustments.mirroredKnobs(from: profile)
            if !mirrored.isEmpty { return mirrored }
        }
        guard let spec = profile.layers[layer] else { return nil }
        let variantKnobs = variant.flatMap { spec.variants?[$0]?.knobs } ?? [:]
        if variantKnobs.isEmpty { return spec.knobs }
        return (spec.knobs ?? [:]).merging(variantKnobs) { _, v in v }
    }

    /// What a slider reads right now, for the held-mode grid. nil when Lightroom has
    /// not reported it, so the grid shows the name alone rather than inventing a number.
    private func liveValue(for param: String) -> String? {
        guard !PointerCommands.isPointer(param) else { return nil }
        guard RepeatCommands.pair(for: param) == nil else { return nil }
        let bridge = LightroomBridge.shared
        guard bridge.isConnected, bridge.hasValue(param) else { return nil }
        return formatValue(param: param, value: bridge.value(for: param))
    }

    private func knobCell(id: String, overlay: [String: KnobBinding]) -> KnobCell {
        if let b = overlay[id] {
            return KnobCell(label: CommandDatabase.shared.shortLabel(for: b.param),
                            value: liveValue(for: b.param), isOverlay: true)
        }
        guard let base = profile.knobs[id] else {
            return KnobCell(label: "-", isOverlay: false)
        }
        return KnobCell(label: CommandDatabase.shared.shortLabel(for: base.param),
                        value: liveValue(for: base.param), isOverlay: false)
    }

    /// Twelve knob names for the HUD row. Overlay names are bright; pass-through names are dim.
    public func knobGrid(forLayer layer: String, variant: String? = nil) -> [KnobCell] {
        let overlay = knobsForLayer(layer, variant: variant) ?? [:]
        guard !overlay.isEmpty else { return [] }
        return PanelLayout.knobs.map { knobCell(id: $0, overlay: overlay) }
    }

    private func knobGrid(forProgram program: AnalogProgram) -> [KnobCell] {
        guard program.appliesToKnobs else { return [] }
        if program.scope == "focus" { return [] }
        let overlay = program.knobs ?? [:]
        guard !overlay.isEmpty else { return [] }
        return PanelLayout.knobs.map { knobCell(id: $0, overlay: overlay) }
    }

    private func triggerActionDisplay(name: String, label: String, phase: ActionPhase,
                                      duration: TimeInterval = 2.0, hold: Bool = false) {
        currentDisplayMode = .action(name: name, label: label, phase: phase)
        if hold {
            collapseTimer?.invalidate()
        } else {
            scheduleCollapse(after: duration)
        }
    }

    /// Explain why a control did nothing. Rate-limited so a spinning knob does not strobe.
    private func notice(_ control: String, _ message: String) {
        let now = Date()
        guard now.timeIntervalSince(lastNoticeAt) > 1.2 else { return }
        lastNoticeAt = now
        triggerActionDisplay(name: control, label: message, phase: .blocked)
    }

    private func scheduleCollapse(after duration: TimeInterval? = nil) {
        collapseTimer?.invalidate()
        let wait = duration ?? AppSettings.shared.hudDuration
        guard wait < 120 else { return } // 120s represents "Always Visible"

        collapseTimer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseToIdle()
            }
        }
        // .common, not the default mode: a timer in the default mode stops firing
        // while a menu is open or a list is being scrolled.
        if let collapseTimer { RunLoop.main.add(collapseTimer, forMode: .common) }
    }

    private func collapseToIdle() {
        if let mode = holdBannerMode() {
            // Held modes stay while the key is down; toggled modes shrink to a quiet reminder.
            currentDisplayMode = mode
            return
        }
        currentDisplayMode = .idle
        if pressedButtonBits.isEmpty {
            setHighlight(nil)
        }
    }

    public func updateLEDs() {
        updateLeds(immediate: true)
    }

    public func updateLeds(immediate: Bool = false) {
        guard !ledsOwnedByShow, !RewindEngine.shared.isRewinding else { return }
        ledWorkItem?.cancel()
        if immediate {
            pushLeds()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pushLeds()
        }
        ledWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
    }

    public func currentBaseWhiteBits() -> Set<Int> {
        let mode = AppSettings.shared.ledMode
        var bits = Set<Int>()
        let programButton = programLEDButton()

        switch mode {
        case "stealth":
            bits = []
        case "all":
            bits = Set(HardwareMap.shared.buttonBitToControl.keys)
        case "layer":
            if let programButton, let bit = HardwareMap.shared.buttonBit(forControl: programButton) {
                bits = [bit]
            } else {
                bits = layerLEDBits()
            }
        case "pulse":
            bits = pressedButtonBits
            if let sel = selectedHardwareButtonBit {
                bits.insert(sel)
            }
            if let programButton, let bit = HardwareMap.shared.buttonBit(forControl: programButton) {
                bits = [bit]
                bits.formUnion(pressedButtonBits)
            } else {
                bits.formUnion(layerLEDBits(includeModifiers: false))
            }
        default:
            bits = pressedButtonBits
            if let programButton, let bit = HardwareMap.shared.buttonBit(forControl: programButton) {
                bits = [bit]
            }
        }
        return bits.union(pickerLEDBits())
    }

    public func currentSemanticColorBits() -> Set<Int> {
        let mode = AppSettings.shared.ledMode
        guard mode != "stealth" else { return [] }
        var colorBits = Set<Int>()

        // 1. Bypass (Bit 0: Red) - Before view active, or physically pressed down, or held
        if isBeforeViewActive || engagedHolds.contains("BYPASS") || pressedButtonBits.contains(20) {
            colorBits.insert(PanelColorLED.bypassRed.rawValue)
        }

        // 2. Disable (Bit 3: Red) - Physically pressed down, or held
        if engagedHolds.contains("DISABLE") || pressedButtonBits.contains(21) || activeLayers.contains("DISABLE") || toggledLayers.contains("DISABLE") {
            colorBits.insert(PanelColorLED.disableRed.rawValue)
        }

        // 3. Offset (Bit 2: Green) - Pressed, held, or in active OFFSET mode
        if activeLayers.contains("OFFSET") || overlayLayerName == "OFFSET" || toggledLayers.contains("OFFSET") || engagedHolds.contains("OFFSET") || pressedButtonBits.contains(13) {
            colorBits.insert(PanelColorLED.offsetGreen.rawValue)
        }

        // 4. Shift Up (Bit 4: Green) - Pressed, or held
        if heldModifiers.contains("SHIFT") || engagedHolds.contains("SHIFT") || pressedButtonBits.contains(24) || activeLayers.contains("MIXER") || activeLayers.contains("SHIFT") {
            colorBits.insert(PanelColorLED.shiftUpGreen.rawValue)
        }

        // 5. Shift Down (Bit 5: Green) - Pressed, or held
        if heldModifiers.contains("CORNER_LOWER_RIGHT") || engagedHolds.contains("CORNER_LOWER_RIGHT") || pressedButtonBits.contains(25) || activeLayers.contains("MULTISELECT") || activeLayers.contains("CORNER_LOWER_RIGHT") {
            colorBits.insert(PanelColorLED.shiftDownGreen.rawValue)
        }

        // 6. Play Still (Bit 6: Green) - Pressed, held, or in STILL/EFFECTS layer
        if engagedHolds.contains("PLAY_STILL") || pressedButtonBits.contains(26) || activeLayers.contains("STILL") || activeLayers.contains("EFFECTS") || toggledLayers.contains("STILL") || toggledLayers.contains("EFFECTS") {
            colorBits.insert(PanelColorLED.playStillGreen.rawValue)
        }

        // 7. Wipe Still (Bit 7: Green) - Pressed, held, or in WIPE layer
        if engagedHolds.contains("WIPE_STILL") || pressedButtonBits.contains(27) || activeLayers.contains("WIPE") || toggledLayers.contains("WIPE") {
            colorBits.insert(PanelColorLED.wipeStillGreen.rawValue)
        }

        // 8. Highlight Clipping / Warning (Bit 8: Green) - Pressed, held, or in H/LITE/DETAIL mode
        if engagedHolds.contains("H/LITE") || pressedButtonBits.contains(29) || activeLayers.contains("H/LITE") || activeLayers.contains("DETAIL") || toggledLayers.contains("H/LITE") {
            colorBits.insert(PanelColorLED.hliteGreen.rawValue)
        }

        // 9. Viewer Zoom / Loupe (Bit 9: Green) - Pressed, held, or in VIEWER/CROP mode
        if engagedHolds.contains("VIEWER") || pressedButtonBits.contains(30) || activeLayers.contains("VIEWER") || activeLayers.contains("CROP") || toggledLayers.contains("VIEWER") {
            colorBits.insert(PanelColorLED.viewerGreen.rawValue)
        }

        // 10. Cursor / Local Adjustments / Mask mode (Bit 10: Green)
        // Stays illuminated in Green when in CURSOR / Local mode (MASK layer, radial, linear, brush, picker), or pressed, or held
        if activeLayers.contains("MASK") || overlayLayerName == "MASK" || toggledLayers.contains("MASK") || maskPlacing || activePickerButton != nil || engagedHolds.contains("CURSOR") || pressedButtonBits.contains(31) {
            colorBits.insert(PanelColorLED.cursorGreen.rawValue)
        }

        return colorBits
    }

    private func pushLeds() {
        guard !ledsOwnedByShow, !RewindEngine.shared.isRewinding else { return }
        var bits = currentBaseWhiteBits()
        let colorBits = currentSemanticColorBits()

        // For any button currently illuminated in color (Report 0x04),
        // suppress its white LED so the color is 100% vibrant and pure
        let colorKeyBits: [PanelColorLED: Int] = [
            .bypassRed: 20,
            .disableRed: 21,
            .offsetGreen: 13,
            .shiftUpGreen: 24,
            .shiftDownGreen: 25,
            .playStillGreen: 26,
            .wipeStillGreen: 27,
            .hliteGreen: 29,
            .viewerGreen: 30,
            .cursorGreen: 31
        ]
        for (colorLed, whiteBit) in colorKeyBits {
            if colorBits.contains(colorLed.rawValue) {
                bits.remove(whiteBit)
            }
        }

        PanelManager.shared.setDualLEDs(whiteBits: bits, colorBits: colorBits)
    }

    private func pickerLEDBits() -> Set<Int> {
        guard activePickerButton != nil else { return [] }
        var bits = Set<Int>()
        if let owner = activePickerButton, let bit = HardwareMap.shared.buttonBit(forControl: owner) {
            bits.insert(bit)
        }
        let selected = ToolWheelSession.shared.combine
        for (key, mode) in MaskCombine.buttonMap where mode == selected {
            if let bit = HardwareMap.shared.buttonBit(forControl: key) { bits.insert(bit) }
        }
        return bits
    }

    private func layerLEDBits(includeModifiers: Bool = true) -> Set<Int> {
        var bits = Set<Int>()
        for layer in activeLayers {
            if let activator = buttonActivating(layer: layer),
               let b = HardwareMap.shared.buttonBit(forControl: activator) {
                bits.insert(b)
            }
            // Keys that do something in this layer light up, so you can see the layer's map.
            for key in (profile.layers[layer]?.buttons ?? [:]).keys {
                if let b = HardwareMap.shared.buttonBit(forControl: key) { bits.insert(b) }
            }
        }
        if includeModifiers {
            for mod in heldModifiers {
                if let activator = buttonActivating(modifier: mod),
                   let b = HardwareMap.shared.buttonBit(forControl: activator) {
                    bits.insert(b)
                }
            }
        }
        return bits
    }

    private func programLEDButton() -> String? {
        if let held = heldProgramButton,
           profile.buttons[held]?.holdProgram?.lightOnlyThisButton != false {
            return held
        }
        if let latched = latchedProgramButton,
           profile.buttons[latched]?.tapProgram?.lightOnlyThisButton != false {
            return latched
        }
        return nil
    }

    private func buttonActivating(layer: String) -> String? {
        if let held = engagedHolds.first(where: { profile.buttons[$0]?.hold_layer == layer }) {
            return held
        }
        for (name, spec) in profile.buttons.sorted(by: { $0.key < $1.key }) {
            if spec.hold_layer == layer || spec.layer == layer {
                return name
            }
        }
        return nil
    }

    private func buttonActivating(modifier: String) -> String? {
        for (name, spec) in profile.buttons where spec.modifier == modifier {
            return name
        }
        return nil
    }

    private func updateStatusMessage() {
        if outputBlocked {
            statusMessage = "Paused"
        } else if activePickerButton != nil {
            let session = ToolWheelSession.shared
            statusMessage = "Hold \(session.ownerLabel) · \(session.combine.title) \(session.selected.title)"
        } else if maskPlacing, overlayLayerName == "MASK" {
            statusMessage = "Masks · placing"
        } else if let held = heldProgramButton, let program = profile.buttons[held]?.holdProgram {
            statusMessage = "Hold \(PanelLayout.label(forControl: held)) · \(program.summary)"
        } else if let latched = latchedProgramButton, let program = profile.buttons[latched]?.tapProgram {
            statusMessage = "\(PanelLayout.label(forControl: latched)) · \(program.summary)"
        } else if let layer = overlayLayerName {
            let title = layerTitle(layer)
            let state = isLayerLatched(layer) ? "On" : "Held"
            if let v = activeVariants[layer] {
                statusMessage = "\(title) · \(v) · \(state)"
            } else {
                statusMessage = "\(title) · \(state)"
            }
        } else if heldModifiers.contains("FINE") {
            statusMessage = "Fine"
        } else if let temp = tempFocusParam {
            statusMessage = "Focus dial · \(CommandDatabase.shared.label(for: temp))"
        } else {
            statusMessage = "Base"
        }
    }

    public func formatValue(param: String, value: Double) -> String {
        ValueFormatter.format(param: param, value: value, range: LightroomBridge.shared.parameterRange(for: param))
    }

    // MARK: - LightroomBridgeDelegate

    public func lightroomConnectionStateChanged(isConnected: Bool) {
        resetKnobReadout = nil
        // New session, new photo, new values. Re-read before anything sends an absolute value.
        readbackAttempts.removeAll()
        readbackRetried.removeAll()
        readbackGaveUp.removeAll()
        pendingNudges.removeAll()
        if !isConnected {
            // Lightroom forgot any compare view it was showing; don't send a stale restore later.
            for name in engagedHolds where profile.buttons[name]?.hold_action != nil {
                engagedHolds.remove(name)
            }
        }
    }

    /// Lightroom changed a value (Undo, Reset, a preset, a new photo). Move the wheels to match
    /// so the next roll continues from what's on screen, not from where the ball used to be.
    /// A different photo is on screen, so a different trail is being recorded.
    public func lightroomActivePhotoDidChange(id: String?) {
        resetKnobReadout = nil
        isBeforeViewActive = false
        updateLeds()
        RewindEngine.shared.knobParams = currentKnobParams()
        RewindEngine.shared.setActivePhoto(id)
        // Preserve a held request when selection arrives after Undo went down.
        if id != nil, activeLayers.contains("REWIND") { beginRewind() }
    }

    /// The twelve knobs as they are mapped right now, for the rolling readout.
    func currentKnobParams() -> [(control: String, param: String)] {
        PanelLayout.knobs.compactMap { id -> (control: String, param: String)? in
            guard let binding = profile.knobs[id] else { return nil }
            return (control: id, param: binding.param)
        }
    }

    var referenceContext: String {
        var parts = layerPriority.map { layer in
            let bank = activeVariants[layer].map { " · " + $0 } ?? ""
            return layerTitle(layer) + bank + (toggledLayers.contains(layer) ? " (on)" : " (held)")
        }
        if parts.isEmpty { parts = ["Base"] }
        if currentAnalogProgram() != nil { parts.append(currentProgramLabel()) }
        if let param = tempFocusParam { parts.append("Focus: " + CommandDatabase.shared.label(for: param)) }
        if !heldModifiers.isEmpty { parts.append("Fine adjustment") }
        if maskPlacing { parts.append("Placing mask: balls move the pointer") }
        if ToolWheelSession.shared.isPresented { parts.append("Mask wheel active: wheels choose tool / operation") }
        return parts.joined(separator: " · ")
    }

    /// The help overlay follows the same layer priority, custom programs and focus dial
    /// as the live controls. It never loads a factory map over the user's assignments.
    func currentHelpProfile() -> Profile {
        var shown = profile
        if overlayLayerName == "MASK" { shown.knobs = [:]; shown.rings = [:] }
        for layer in layerPriority.reversed() {
            if let knobs = knobsForLayer(layer, variant: activeVariants[layer]) { shown.knobs.merge(knobs) { _, next in next } }
            if let rings = profile.layers[layer]?.rings { shown.rings.merge(rings) { _, next in next } }
            if let balls = profile.layers[layer]?.balls { shown.balls.merge(balls) { _, next in next } }
        }
        let helpButtonIDs = Set(PanelLayout.allButtons + PanelLayout.knobs.map { "PRESS_" + $0 } + Array(profile.buttons.keys) + layerPriority.flatMap { Array(profile.layers[$0]?.buttons?.keys ?? Dictionary<String, ButtonBinding>().keys) })
        for id in helpButtonIDs {
            var binding = resolvedButtonBinding(for: id) ?? ButtonBinding()
            let hold = holdBinding(for: id)
            binding.hold_layer = hold?.hold_layer
            binding.holdProgram = hold?.holdProgram
            binding.hold_picker = hold?.hold_picker
            binding.hold_action = hold?.hold_action
            binding.modifier = hold?.modifier
            binding.release_action = hold?.release_action
            shown.buttons[id] = binding
        }
        if let program = currentAnalogProgram() {
            if program.scope == "focus", let raw = program.focusParam {
                let param = resolveProgramParam(raw)
                if program.appliesToKnobs { for id in PanelLayout.knobs { shown.knobs[id] = KnobBinding(param: param) } }
                if program.appliesToWheels {
                    for id in PanelLayout.rings { shown.rings[id] = RingBinding(param: param) }
                    for id in PanelLayout.balls { shown.balls[id] = .slider(param) }
                }
            } else {
                if program.appliesToKnobs { shown.knobs.merge(program.knobs ?? [:]) { _, next in next } }
                if program.appliesToWheels {
                    shown.rings.merge(program.rings ?? [:]) { _, next in next }
                    shown.balls.merge(program.balls ?? [:]) { _, next in next }
                }
            }
        }
        // Mask balls bypass programs and Base in the actual analog dispatcher.
        if maskPlacing {
            shown.balls = Dictionary(uniqueKeysWithValues: PanelLayout.balls.map { ($0, maskPlaceBinding()) })
            shown.rings.merge(profile.layers["MASK"]?.rings ?? [:]) { _, next in next }
        } else if overlayLayerName == "MASK" {
            shown.balls = profile.layers["MASK"]?.balls ?? [:]
        }
        if let param = tempFocusParam { shown.knobs[AppSettings.shared.focusDialControl] = KnobBinding(param: param) }
        if RewindEngine.shared.isRewinding {
            shown.knobs = shown.knobs.filter { RewindCommands.isRewind($0.value.param) }
            shown.rings = shown.rings.filter { RewindCommands.isRewind($0.value.param) }
            shown.balls = [:]
        }
        if activePickerButton != nil {
            shown.knobs = Dictionary(uniqueKeysWithValues: PanelLayout.knobs.map { ($0, KnobBinding(param: "Choose mask tool")) })
            shown.rings = Dictionary(uniqueKeysWithValues: PanelLayout.rings.map { ($0, RingBinding(param: $0 == MaskCombine.ringControl ? "Choose mask operation" : "Choose mask tool")) })
            shown.balls = Dictionary(uniqueKeysWithValues: PanelLayout.balls.map { ($0, BallBinding.slider("Aim at mask tool")) })
            for (key, operation) in MaskCombine.buttonMap { shown.buttons[key] = ButtonBinding(action: "Mask operation: " + operation.title) }
        }
        return shown
    }

    public func lightroomParameterDidUpdate(name: String, value: Double) {
        let bridge = LightroomBridge.shared
        if resetKnobReadout?.param == name { PanelDiagnostics.record("reset readback \(name)=\(value)") }
        refreshKnobResetReadout(param: name, value: value)
        // A tiny turn while pressing may show "Updating" during Reset's freshness
        // window. Replace that waiting state when Lightroom returns the value.
        if !outputBlocked, let dial = activeDialReadout, dial.param == name {
            let label = CommandDatabase.shared.label(for: name)
            switch currentDisplayMode {
            case .knob(let who, _, _, _, let fine, let angle) where who == dial.name:
                currentDisplayMode = .knob(name: who, param: label, value: value,
                                          displayValue: formatValue(param: name, value: value), isFine: fine, angleDegrees: angle)
            case .ring(let who, _, _, _, let fine, let angle) where who == dial.name:
                currentDisplayMode = .ring(name: who, param: label, value: value,
                                          displayValue: formatValue(param: name, value: value), isFine: fine, angleDegrees: angle)
            default: break
            }
        }
        scheduleHoldBannerRefresh()
        applyPendingNudge(for: name)
        for engine in Array(trackballs.values) + Array(overlayTrackballs.values)
        where (engine.hueParam == name || engine.satParam == name) && engine.isSettled {
            engine.sync(turns: bridge.value(for: engine.hueParam), saturation: bridge.value(for: engine.satParam))
        }
    }

    /// Lightroom finally reported a slider that was turned while it was unknown. Apply
    /// that turn from the real value, so nothing ever jumps to the middle first.
    private func applyPendingNudge(for param: String) {
        guard let pending = pendingNudges.removeValue(forKey: param), pending != 0 else { return }
        guard shouldSendToLightroom, LightroomBridge.shared.isConnected else { return }
        _ = LightroomBridge.shared.nudgeParameter(param, delta: pending)
    }

    /// Reset one color wheel. its ball and its ring. for whatever they're mapped to right now.
    private func resetWheel(_ which: String, key: String) {
        let parts = which.split(separator: ":").map(String.init)
        let wheel = parts.first ?? which
        let component = parts.count > 1 ? parts[1] : "all"
        let ballName = "TB_\(wheel)"
        let ringName = "RING_\(wheel)"
        let shown = currentHelpProfile()
        let ball = component == "ring" ? nil : shown.balls[ballName]
        let ring = component == "ball" ? nil : shown.rings[ringName]
        let commands = WheelReset.commands(ball: ball, ringParam: ring?.param, known: Set(CommandDatabase.shared.commands.keys))
        PanelDiagnostics.record("wheel reset \(which) commands=\(commands.joined(separator: ",")) connected=\(LightroomBridge.shared.isConnected)")
        let title = WheelReset.title(wheel) + (component == "all" ? "" : " · " + component)
        guard !commands.isEmpty else {
            triggerActionDisplay(name: key, label: "\(title): nothing to reset", phase: .blocked)
            return
        }
        guard LightroomBridge.shared.isConnected else {
            triggerActionDisplay(name: key, label: "\(title) · Lightroom isn’t connected", phase: .blocked)
            return
        }
        for tb in trackballs.values { tb.stopInertia() }
        for tb in overlayTrackballs.values { tb.stopInertia() }
        commands.forEach {
            pendingNudges[String($0.dropFirst("Reset".count))] = nil
            LightroomBridge.shared.fireAction($0)
        }
        if component != "ring" {
            trackballs[ballName]?.recenter()
            overlayTrackballs.filter { $0.key.hasSuffix(":\(ballName)") }.values.forEach { $0.recenter() }
        }
        triggerActionDisplay(name: key, label: title, phase: .done)
    }
}

/// Lightroom-style readouts. Never prints "+0" or "-0".
public enum ValueFormatter {
    public static func format(param: String, value: Double, range: ParameterRange? = nil) -> String {
        if let range, !["CropLeft", "CropRight", "CropTop", "CropBottom", "PresetAmount", "local_Amount"].contains(param) { return range.display(value) }
        switch param {
        case "Exposure", "local_Exposure":
            return signed((value - 0.5) * 10.0, decimals: 2, suffix: " EV")
        case "Temperature":
            return String(format: "%.0f K", 2000.0 + value * 48000.0)
        case "Tint":
            return signed((value - 0.5) * 300.0, decimals: 0)
        case "straightenAngle":
            return signed((value - 0.5) * 90.0, decimals: 1, suffix: "°")
        case "CropLeft", "CropRight", "CropTop", "CropBottom", "PresetAmount", "local_Amount":
            return String(format: "%.0f%%", value * 100.0)
        default:
            // A slider whose real range is known prints the number Lightroom shows.
            // Everything else keeps the bipolar reading, which is right for most of them.
            if let range = ParameterRanges.range(for: param) {
                return range.display(value)
            }
            return signed((value - 0.5) * 200.0, decimals: 0)
        }
    }

    public static func signed(_ value: Double, decimals: Int, suffix: String = "") -> String {
        let factor = pow(10.0, Double(max(0, decimals)))
        let rounded = (value * factor).rounded() / factor
        if rounded == 0 {
            return String(format: "%.\(decimals)f", 0.0) + suffix
        }
        return String(format: "%+.\(decimals)f", rounded) + suffix
    }
}
