import Foundation
import Combine

/// Everything Rewind needs from Lightroom. A protocol so the recorder can be tested without
/// a catalog, a panel, or a socket.
public protocol RewindOutput: AnyObject {
    /// Every develop value PanaLux currently believes in.
    func rewindKnownValues() -> [String: Double]
    func rewindRange(for param: String) -> ParameterRange?
    func rewindSetParameters(_ values: [String: Double])
    func rewindSetParameter(_ name: String, value: Double)
    /// Ask the plugin for a full `getDevelopSettings()` table; the reply comes back by id.
    func rewindRequestSnapshot(token: String)
    /// Hand a table back to the plugin. This is what restores masks and crop exactly.
    func rewindRestore(blob: String)
}

public extension RewindOutput {
    func rewindSetParameters(_ values: [String: Double]) {
        for (name, value) in values { rewindSetParameter(name, value: value) }
    }
    func rewindRange(for param: String) -> ParameterRange? { nil }
}

/// The recorder and the playhead.
///
/// Two layers, as the trail describes them: keyframes are whole settings tables captured around
/// anything structural, and the value stream is the dense tape between them. Scrubbing
/// interpolates the stream and steps at a keyframe, which is what makes gradual editing feel
/// gradual and discrete edits feel discrete without either being a special case.
///
/// Main thread only, like `StudioEngine`.
public final class RewindEngine: ObservableObject {
    public static let shared = RewindEngine()

    /// Published for the HUD. `StudioEngine` pushes it into the readout.
    @Published public private(set) var state: RewindState = .empty
    @Published public private(set) var isRewinding = false

    /// Fires whenever the readout should be redrawn (scrub, playback, landmark, branch).
    public let changed = PassthroughSubject<RewindState, Never>()

    /// Which tangent is being edited, or nil on the original. The badge beside every readout is
    /// this, so it is never possible to forget you are on a tangent.
    @Published public private(set) var tangentInfo: TangentInfo?

    public enum TangentEvent: Equatable {
        /// A new tangent began. `parent` is the line it left, `at` where on the tape.
        case started(name: String, parent: String, at: TimeInterval)
        case switched(name: String)
    }
    public let tangentEvents = PassthroughSubject<TangentEvent, Never>()

    public weak var output: RewindOutput?
    /// The twelve knobs as they are mapped right now, for the rolling readout.
    public var knobParams: [(control: String, param: String)] = []
    /// Trails are only written for photos Lightroom has actually named.
    public private(set) var photoID: String?
    public private(set) var trail: EditTrail?
    @Published public private(set) var historyUnavailableMessage: String?
    /// Where trails are kept. nil means the usual place beside the map; tests point it elsewhere.
    public var storeDirectory: URL?

    private var playback: TrailPlayback?
    private var playhead: TimeInterval = 0
    /// The playhead is behind the tip, so the next edit starts a branch instead of overwriting.
    private var detached = false
    private var detachedValues: [String: Double]?
    private var peeking = false
    /// The photo as it stood when the hold began. Rolling forward returns to exactly this.
    private var tipValues: [String: Double] = [:]
    private var lastSent: [String: Double] = [:]
    private var appliedKeyframeID: String?
    private var lastScrubAt: Date = .distantPast
    /// How busy each tangent was, by slice of the session. Worked out once per rewind: nothing
    /// is recorded while the hold is on, so it cannot change under the playhead.
    private var laneActivity: [String: [Float]] = [:]
    private var laneSpan: (start: TimeInterval, end: TimeInterval) = (0, 1)
    static let laneBuckets = 120
    private var deletedTangent: (photo: String, branch: TrailBranch, index: Int)?
    @Published public private(set) var canRestoreDeletedTangent = false
    private var pendingSnapshots: [String: String] = [:]   // token → keyframe id
    private var saveWork: DispatchWorkItem?
    /// Reports arriving before this are Lightroom catching up with Rewind, not editing.
    private var ignoreRecordsUntil: Date = .distantPast
    private static let settleAfterRewind: TimeInterval = 1.2
    /// Encoding a long trail is not work for the main thread.
    static let saveQueue = DispatchQueue(label: "com.panalux.trail", qos: .utility)

    // MARK: Feel
    // These are the two numbers that decide how Rewind feels under the hand. They are set from
    // Settings, so they can be tuned without rebuilding.

    /// Ring units for one click. Turned slowly, one click is exactly one thing you did.
    public var clickUnits: Double = 40
    /// 0…1. How fast a hard spin crosses a long session. The slow end never changes: slow is
    /// always one step per click, whatever this says.
    public var acceleration: Double = 0.5

    private var jogRemainder: Double = 0
    /// Clicks per second, smoothed so one quick packet in a slow turn does not throw the playhead.
    private var jogRate: Double = 0
    private var continuousScrub = false
    private var scrubDirection = 0.0

    // MARK: Transport
    public private(set) var isPlaying = false
    public private(set) var playDirection: Double = 1
    /// 1 is the pace the edits were made at. The rings turn this dial; it survives between holds.
    public private(set) var playSpeed: Double = 1
    private var speedLatched = false
    private var speedPull: Double = 0
    private var playTimer: Timer?
    private var lastTick = Date()
    public static let minSpeed = 0.05
    public static let maxSpeed = 32.0
    /// Real editing has long pauses in it. Watching one at its own pace would be watching nothing,
    /// so a stretch of quiet longer than this plays through in `idleGapPlaysIn`.
    static let idleGapAbove: TimeInterval = 1.2
    static let idleGapPlaysIn: TimeInterval = 0.5
    /// 30 a second is smooth to watch and gentle on the socket to Lightroom.
    static let tickInterval: TimeInterval = 1.0 / 30.0

    public init() {}

    deinit { saveWork?.cancel() }

    // MARK: - Photo lifecycle

    /// Lightroom put a different photo on screen. Save what we have and pick up that photo's trail.
    public func setActivePhoto(_ id: String?) {
        guard id != photoID else { return }
        // The trail being left behind has to be on disk before the next one is read.
        flush(synchronously: true)
        endRewind(announce: false)
        detachedValues = nil
        photoID = id
        historyUnavailableMessage = nil
        deletedTangent = nil
        canRestoreDeletedTangent = false
        pendingSnapshots.removeAll()
        guard let id, !id.isEmpty else {
            trail = nil
            playback = nil
            refreshTakeInfo()
            return
        }
        let stored = TrailStore.load(photoID: id, in: storeDirectory)
        // An unreadable or newer-format trail is not a missing trail. Preserve its
        // exact bytes and suspend recording for this photo instead of replacing it.
        if stored == nil, FileManager.default.fileExists(atPath: TrailStore.url(for: id, in: storeDirectory).path) {
            trail = nil
            playback = nil
            historyUnavailableMessage = "This history can’t be opened · saved history is kept"
            refreshTakeInfo()
            return
        }
        var loaded = stored ?? EditTrail(photoID: id)
        loaded.resume()
        trail = loaded
        playback = nil
        detached = false
        refreshTakeInfo()
        // The photo as it arrives is a landmark in its own right: somewhere to get back to.
        captureKeyframe(kind: .open, label: "Opened")
    }

    // MARK: - Recording

    /// Every reported value change, whoever caused it — a knob, a mouse, a preset.
    public func record(param: String, value: Double, at wall: Date = Date(), userInitiated: Bool = false) {
        // While scrubbing, the values coming back are our own playback. Recording them would
        // tape over the recording.
        guard !isRewinding, trail != nil else { return }
        guard !param.isEmpty else { return }
        // Letting go, or putting a settings table back, makes Lightroom resend everything a
        // moment later. None of that is editing, and none of it should start a branch.
        guard userInitiated || wall >= ignoreRecordsUntil else { return }
        // Lightroom confirms what Rewind just wrote. That is the playback coming back, not an
        // edit: recording it would tape over the trail, and worse, would look like a new branch.
        if let sent = lastSent[param], abs(sent - value) < 0.000001 { return }
        lastSent[param] = nil
        if detached {
            startBranch(reason: "Edited from the past", at: wall)
        }
        let t = trail?.time(at: wall) ?? 0
        if trail?.record(param: param, value: value, at: t) == true {
            scheduleSave()
        }
    }

    /// A key that changes the photo in a way the value stream cannot describe: a mask, a crop,
    /// a preset, a paste. The table is captured around it so the point is restorable exactly.
    public func noteStructuralEdit(_ command: String, label: String) {
        guard trail != nil, let kind = RewindEngine.structuralKind(of: command) else { return }
        if detached { startBranch(reason: "Edited from the past") }
        captureKeyframe(kind: kind, label: label)
    }

    static func structuralKind(of command: String) -> TrailKeyframe.Kind? {
        if command.hasPrefix("Mask") { return .mask }
        if command.hasPrefix("Crop") || command == "ResetCrop" || command == "CropOverlay" { return .crop }
        if command.hasPrefix("Preset") || command == "PresetAmount" { return .preset }
        if command == "LRPaste" || command == "PasteSelectedSettings" { return .paste }
        if command == "ResetAll" || command.hasPrefix("Upright") { return .reset }
        if command == "AutoTone" || command == "WhiteBalanceAuto" { return .action }
        return nil
    }

    /// Capture a landmark, and ask Lightroom for the whole table behind it. The table always
    /// describes what is on screen right now, which is why a mark made while rewinding is
    /// captured the same way: the photo already shows the playhead.
    @discardableResult
    private func captureKeyframe(kind: TrailKeyframe.Kind, label: String, at wall: Date = Date(),
                                 time: TimeInterval? = nil, values: [String: Double]? = nil) -> String? {
        guard trail != nil else { return nil }
        let values = values ?? output?.rewindKnownValues() ?? [:]
        let t = time ?? trail?.time(at: wall) ?? 0
        let keyframe = TrailKeyframe(t: t, kind: kind, label: label, values: values)
        _ = trail?.addKeyframe(keyframe)
        playback = nil
        // The settings table arrives later; the keyframe stands on its own until it does.
        let token = TrailStore.fnv1a(keyframe.id)
        // Lightroom may never answer (no photo, wrong module). Don't remember requests forever.
        if pendingSnapshots.count > 64 { pendingSnapshots.removeAll() }
        pendingSnapshots[token] = keyframe.id
        output?.rewindRequestSnapshot(token: token)
        scheduleSave()
        return keyframe.id
    }

    /// The plugin answered a snapshot request.
    public func acceptSnapshot(token: String, blob: String) {
        guard let keyframeID = pendingSnapshots.removeValue(forKey: token) else { return }
        _ = trail?.attachBlob(blob, toKeyframe: keyframeID)
        scheduleSave()
    }

    // MARK: - The hold

    /// UNDO went down and the REWIND layer came on.
    public func beginRewind() {
        guard let trail, !isRewinding else { return }
        isRewinding = true
        peeking = false
        let live = playbackForTrail(trail)
        tipValues = output?.rewindKnownValues() ?? [:]
        lastSent = tipValues
        playhead = live.tip
        // Only count a landmark as already applied if the playhead is standing on it.
        let atTip = live.keyframe(at: live.tip)
        appliedKeyframeID = (atTip.map { abs($0.t - live.tip) < RewindEngine.landmarkWindow } ?? false)
            ? atTip?.id : nil
        jogRemainder = 0
        jogRate = 0
        lastScrubAt = .distantPast
        isPlaying = false
        rebuildLaneActivity()
        publish(caption: "Now")
        RewindLEDAnimator.shared.start()
    }

    /// UNDO came up. The photo stays wherever the playhead is — that is the point.
    public func endRewind(announce: Bool = true) {
        guard isRewinding else { return }
        detachedValues = currentPlayback()?.values(at: playhead, interpolateGaps: continuousScrub)
        finishScrub()
        stopPlaybackTimer()
        isPlaying = false
        isRewinding = false
        peeking = false
        if let playback = currentPlayback() {
            // Settling on a landmark restores its table, so masks and crop come back too.
            applyKeyframeIfNeeded(at: playhead, in: playback)
            detached = playhead < playback.tip - 0.05
        }
        ignoreRecordsUntil = Date().addingTimeInterval(RewindEngine.settleAfterRewind)
        flush()
        if announce { publish(caption: detached ? "Left in the past" : "Now") }
        RewindLEDAnimator.shared.stop()
    }

    // MARK: - Scrubbing

    /// How many steps one click covers. Slow is exactly one, and that never changes; faster
    /// eases up smoothly, with no seam between "careful" and "travelling", to at most a fortieth
    /// of the session per click so a hard spin crosses any length of session in a second or two.
    static func jogMultiplier(rate: Double, stepCount: Int, acceleration: Double) -> Int {
        let careful = 22.0     // clicks a second: a deliberate turn, still one stop a click
        let flat = 120.0       // clicks a second: a hard spin
        let reach = max(1.0, Double(stepCount) / 40.0) * (0.2 + 0.9 * min(1, max(0, acceleration)))
        let s = min(1.0, max(0.0, (rate - careful) / (flat - careful)))
        return max(1, Int((1.0 + (reach - 1.0) * s * s).rounded()))
    }

    /// Centre ring. One click is one thing that changed: every value you had is somewhere the
    /// playhead can stop. Turn faster and it travels; stop turning and it holds exactly there.
    public func scrub(units: Double, now: Date = Date()) {
        guard units.isFinite, units != 0, isRewinding, let playback = currentPlayback() else { return }
        pausePlayback(announce: false)
        let elapsed = now.timeIntervalSince(lastScrubAt)
        let direction = units < 0 ? -1.0 : 1.0
        if elapsed > 0.2 || direction != scrubDirection { jogRate = 0 }
        scrubDirection = direction
        let gap = max(0.001, min(0.5, elapsed))
        lastScrubAt = now
        let instant = abs(units) / gap / max(1, clickUnits)
        jogRate = jogRate * 0.75 + instant * 0.25
        let reach = Double(RewindEngine.jogMultiplier(rate: jogRate, stepCount: playback.stepTimes.count,
                                                      acceleration: acceleration))
        // Fractional stops respond to every packet. A whole slow click still lands exactly on
        // the adjacent edit; reversing never waits for a remainder or a trailing animation.
        let position = playback.fractionalPosition(at: playhead)
        playhead = playback.time(atFractionalPosition: position + units / max(1, clickUnits) * reach)
        continuousScrub = true
        apply(playback)
        publish(caption: stepCaption(for: playhead, in: playback))
    }

    public func seekToFraction(_ fraction: Double) {
        guard fraction.isFinite, !StudioEngine.shared.outputBlocked else { return }
        beginRewind()
        guard isRewinding, let tape = currentPlayback() else { return }
        pausePlayback(announce: false)
        playhead = (tape.stepTimes.first ?? 0) + min(1, max(0, fraction)) * (tape.tip - (tape.stepTimes.first ?? 0))
        continuousScrub = true
        apply(tape)
        publish(caption: stepCaption(for: playhead, in: tape))
    }

    public func canDeleteTangent(_ id: String) -> Bool {
        guard let trail, let branch = trail.branch(id), branch.parent != nil, id != trail.activeBranchID else { return false }
        return !trail.branches.contains { $0.parent == id || $0.mergeSourceID == id }
    }

    @discardableResult
    public func deleteTangent(_ id: String) -> Bool {
        guard !StudioEngine.shared.outputBlocked, canDeleteTangent(id),
              let trail, let index = trail.branches.firstIndex(where: { $0.id == id }) else { return false }
        deletedTangent = (photoID ?? "", trail.branches[index], index)
        canRestoreDeletedTangent = true
        self.trail?.branches.remove(at: index)
        rebuildLaneActivity(); refreshTakeInfo(); scheduleSave()
        publish(caption: "Tangent deleted · Undo Delete is available")
        return true
    }

    public func restoreDeletedTangent() {
        guard let deleted = deletedTangent, deleted.photo == (photoID ?? ""),
              let trail, trail.branch(deleted.branch.id) == nil else { return }
        self.trail?.branches.insert(deleted.branch, at: min(deleted.index, trail.branches.count))
        deletedTangent = nil; canRestoreDeletedTangent = false
        rebuildLaneActivity(); refreshTakeInfo(); scheduleSave()
        publish(caption: "Tangent restored")
    }

    private func finishScrub() { continuousScrub = false }

    /// The rings on either side. Left is the fine dial and right is the coarse one; turning
    /// either clockwise is faster. It is a dial on a log scale, so slow motion has as much room
    /// as fast forward. 1× is where the recording plays as it happened, and it holds there a
    /// moment so it is easy to land on.
    public func adjustSpeed(units: Double, fine: Bool) {
        guard isRewinding else { return }
        var delta = units
        if speedLatched {
            speedPull += units
            guard abs(speedPull) > 40 else { return }
            speedLatched = false
            delta = speedPull
            speedPull = 0
        }
        let before = playSpeed
        let k = fine ? 0.0016 : 0.0045
        playSpeed = min(RewindEngine.maxSpeed, max(RewindEngine.minSpeed, playSpeed * exp(delta * k)))
        if (before - 1) * (playSpeed - 1) < 0 {
            playSpeed = 1
            speedLatched = true
            speedPull = 0
        }
        publish(caption: "Speed \(RewindState.rateText(playSpeed))")
    }

    /// Play forward or backward at the dial's speed. Pressing the direction it is already going
    /// pauses, so one key does both jobs.
    public func play(forward: Bool) {
        finishScrub()
        guard isRewinding, let playback = currentPlayback() else { return }
        if isPlaying && (playDirection > 0) == forward {
            pausePlayback()
            return
        }
        if forward && playback.tip - playhead < 1e-6 {
            publish(caption: "Already at now")
            return
        }
        if !forward && playhead - playback.start < 1e-6 {
            publish(caption: "That is the start")
            return
        }
        peeking = false
        playDirection = forward ? 1 : -1
        isPlaying = true
        lastTick = Date()
        startPlaybackTimer()
        publish(caption: forward ? "Playing" : "Playing backward")
    }

    /// Stop where it is. The photo stays exactly there.
    public func pausePlayback(announce: Bool = true) {
        guard isPlaying else { return }
        stopPlaybackTimer()
        isPlaying = false
        if let playback = currentPlayback() {
            // Settling on a landmark puts its whole table back, masks and crop included.
            applyKeyframeIfNeeded(at: playhead, in: playback)
            if announce { publish(caption: "Paused · " + stepCaption(for: playhead, in: playback)) }
        }
    }

    /// One frame of playback. Public so it can be driven by hand in a test.
    func advancePlayback(by dt: TimeInterval) {
        guard isPlaying, isRewinding, let playback = currentPlayback() else { return }
        var factor = 1.0
        if let gap = playback.surroundingGap(at: playhead), gap > RewindEngine.idleGapAbove {
            factor = gap / RewindEngine.idleGapPlaysIn
        }
        playhead += playDirection * dt * playSpeed * factor
        var finished = false
        if playhead >= playback.tip { playhead = playback.tip; finished = playDirection > 0 }
        if playhead <= playback.start { playhead = playback.start; finished = finished || playDirection < 0 }
        apply(playback)
        if finished {
            let forward = playDirection > 0
            pausePlayback(announce: false)
            publish(caption: forward ? "Now" : "The start")
            return
        }
        publish(caption: RewindEngine.ago(playback.tip - playhead))
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(timeInterval: RewindEngine.tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let dt = min(0.25, now.timeIntervalSince(self.lastTick))
            self.lastTick = now
            self.advancePlayback(by: dt)
        }
        // Common modes, so it keeps playing while a menu or a drag has the run loop.
        RunLoop.main.add(timer, forMode: .common)
        playTimer = timer
    }

    private func stopPlaybackTimer() {
        playTimer?.invalidate()
        playTimer = nil
    }

    /// One key back to now.
    public func jumpToTip() {
        finishScrub()
        guard isRewinding, let playback = currentPlayback() else { return }
        stopPlaybackTimer()
        isPlaying = false
        playhead = playback.tip
        apply(playback)
        applyKeyframeIfNeeded(at: playhead, in: playback)
        detached = false
        publish(caption: "Now")
    }

    public func step(forward: Bool) {
        finishScrub()
        guard isRewinding, let playback = currentPlayback() else { return }
        pausePlayback(announce: false)
        let target = forward ? playback.nextLandmark(after: playhead)?.t
                             : playback.previousLandmark(before: playhead)?.t
        playhead = min(playback.tip, max(playback.start, target ?? (forward ? playback.tip : playback.start)))
        apply(playback)
        applyKeyframeIfNeeded(at: playhead, in: playback)
        publish(caption: caption(for: playhead, in: playback))
    }

    /// Hold to see the tip without moving the playhead. A/B without leaving the past.
    public func setPeeking(_ on: Bool) {
        finishScrub()
        guard isRewinding, let playback = currentPlayback(), peeking != on else { return }
        peeking = on
        apply(playback)
        publish(caption: on ? "Now (peek)" : caption(for: playhead, in: playback))
    }

    /// "I liked it." A mark is a landmark the playhead snaps to.
    public func mark() {
        guard trail != nil else { return }
        // While rewinding, the mark belongs where the playhead is, not where the clock is.
        if isRewinding, let playback = currentPlayback() {
            _ = captureKeyframe(kind: .mark, label: "Mark", time: playhead,
                                values: playback.values(at: playhead, interpolateGaps: continuousScrub))
            publish(caption: "Marked")
        } else {
            _ = captureKeyframe(kind: .mark, label: "Mark")
        }
    }

    /// One press, new tangent. The abandoned line is kept, whole.
    public func startBranch(reason: String = "Branch", at wall: Date = Date(), baseline: [String: Double]? = nil) {
        guard let existing = trail else { return }
        let at = isRewinding || detached ? playhead : existing.tipTime
        let values = baseline ?? (detached ? detachedValues : nil) ?? currentPlayback()?.values(at: at, interpolateGaps: continuousScrub) ?? existing.playback().values(at: at)
        let branch = trail?.fork(at: at, wall: wall)
        detached = false
        playback = nil
        appliedKeyframeID = nil
        if let branch {
            _ = captureKeyframe(kind: .branch, label: branch.name, at: wall, time: at, values: values)
            let parent = branch.parent.flatMap { trail?.branch($0)?.name } ?? "Original"
            tangentEvents.send(.started(name: branch.name, parent: parent, at: at))
        }
        refreshTakeInfo()
        rebuildLaneActivity()
        scheduleSave()
        publish(caption: reason)
    }

    // MARK: - Tangents

    /// Move to the next or previous tangent, keeping your place in time. Standing at the end of a
    /// tangent lands you at the end of the next, so hopping compares where each one finished.
    /// The photo follows at once, so it is an A/B you can flip as fast as you can press.
    public func hopTangent(forward: Bool) {
        finishScrub()
        guard isRewinding, let current = trail, let before = currentPlayback() else { return }
        guard current.branches.count > 1 else {
            publish(caption: "No other tangents yet")
            return
        }
        pausePlayback(announce: false)
        let ids = current.branches.map(\.id)
        let index = ids.firstIndex(of: current.activeBranchID) ?? 0
        let next = ids[(index + (forward ? 1 : ids.count - 1)) % ids.count]
        let wasAtTip = before.tip - playhead < 1e-6
        trail?.activate(next)
        playback = nil
        guard let trail, let after = Optional(playbackForTrail(trail)) else { return }
        playhead = wasAtTip ? after.tip : min(after.tip, max(after.start, playhead))
        appliedKeyframeID = nil
        peeking = false
        apply(after)
        applyKeyframeIfNeeded(at: playhead, in: after)
        refreshTakeInfo()
        scheduleSave()
        let name = trail.activeBranch.name
        tangentEvents.send(.switched(name: name))
        publish(caption: "\(name) · " + stepCaption(for: playhead, in: after))
    }

    /// Open a saved tangent at its latest recorded state. This is an explicit user action.
    public func selectTangent(_ id: String) {
        guard let existing = trail, existing.branch(id) != nil, existing.activeBranchID != id else { return }
        finishScrub()
        let wasRewinding = isRewinding
        if !wasRewinding { beginRewind() }
        pausePlayback(announce: false)
        trail?.activate(id)
        playback = nil
        guard let tape = currentPlayback() else { return }
        playhead = tape.tip
        peeking = false
        appliedKeyframeID = nil
        apply(tape)
        applyKeyframeIfNeeded(at: playhead, in: tape)
        refreshTakeInfo()
        rebuildLaneActivity()
        scheduleSave()
        publish(caption: trail?.activeBranch.name ?? "Tangent")
        if !wasRewinding { endRewind(announce: false) }
    }

    public func renameTangent(_ id: String, to name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !clean.isEmpty, let index = trail?.branches.firstIndex(where: { $0.id == id }) else { return }
        trail?.branches[index].name = clean
        refreshTakeInfo()
        scheduleSave()
        publish(caption: "Named “\(clean)”")
    }

    /// Only normalized slider values are eligible. Opaque mask/settings tables are never mixed.
    public func mergeCandidates(from id: String) -> [String: Double] {
        guard let trail, trail.branch(id) != nil, id != trail.activeBranchID else { return [:] }
        let source = trail.playback(on: id)
        let current = output?.rewindKnownValues() ?? trail.playback().values(at: trail.tipTime)
        return source.values(at: source.tip).filter { name, value in
            value.isFinite && current[name] != nil && abs((current[name] ?? value) - value) > 0.000001
                && !name.hasPrefix("local_") && !name.hasPrefix("Crop")
        }
    }

    /// Fork the destination before applying selected sliders. Both complete source lines survive.
    @discardableResult
    public func mergeParameters(from id: String, names: Set<String>) -> Bool {
        finishScrub()
        guard let existing = trail, id != existing.activeBranchID, let source = existing.branch(id) else { return false }
        let candidates = mergeCandidates(from: id).filter { names.contains($0.key) }
        guard !candidates.isEmpty else { return false }
        let wasRewinding = isRewinding
        if !wasRewinding { beginRewind() }
        pausePlayback(announce: false)
        let destinationName = existing.activeBranch.name
        startBranch(reason: "Merge from \(source.name)", baseline: output?.rewindKnownValues())
        guard let mergedID = trail?.activeBranchID else { return false }
        if let index = trail?.branches.firstIndex(where: { $0.id == mergedID }) {
            trail?.branches[index].mergeSourceID = id
        }
        renameTangent(mergedID, to: "\(destinationName) + \(source.name)")
        let moment = playhead + 0.001
        for (name, value) in candidates { _ = trail?.record(param: name, value: value, at: moment) }
        playback = nil
        playhead = moment
        peeking = false
        if let tape = currentPlayback() { apply(tape) }
        // The branch snapshot describes the state before the merge; never restore it over these sliders.
        detached = false
        rebuildLaneActivity()
        scheduleSave()
        publish(caption: "Merged \(candidates.count) settings · originals kept")
        if !wasRewinding { endRewind(announce: false) }
        return true
    }

    /// The badge's contents: nil on the original, so it only ever appears on a tangent.
    private func refreshTakeInfo() {
        guard let trail, trail.activeBranch.parent != nil else {
            if tangentInfo != nil { tangentInfo = nil }
            return
        }
        let index = trail.branches.firstIndex { $0.id == trail.activeBranchID } ?? 0
        let next = TangentInfo(name: trail.activeBranch.name, colorIndex: index,
                            number: index + 1, total: trail.branches.count)
        if tangentInfo != next { tangentInfo = next }
    }

    private func rebuildLaneActivity() {
        laneActivity = [:]
        guard let trail else { return }
        let start = trail.branches.map(\.forkTime).min() ?? 0
        let end = max(start + 1, trail.branches.map(\.localTip).max() ?? 1)
        laneSpan = (start, end)
        let n = RewindEngine.laneBuckets
        for branch in trail.branches {
            var counts = [Float](repeating: 0, count: n)
            func bucket(_ t: TimeInterval) -> Int {
                min(n - 1, max(0, Int((t - start) / (end - start) * Double(n))))
            }
            for e in branch.events { counts[bucket(e.t)] += 1 }
            for k in branch.keyframes { counts[bucket(k.t)] += 1 }
            // Square root, so a burst does not flatten everything else into the floor.
            let peak = counts.max() ?? 0
            laneActivity[branch.id] = peak > 0 ? counts.map { ($0 / peak).squareRoot() } : counts
        }
    }

    private func makeLanes() -> [TangentLane] {
        guard let trail else { return [] }
        let path = Set(trail.lineage().map(\.id))
        return trail.branches.enumerated().map { index, b in
            TangentLane(id: b.id, name: b.name, colorIndex: index, start: b.forkTime, tip: b.localTip,
                     parentID: b.parent, isActive: b.id == trail.activeBranchID,
                     isOnPath: path.contains(b.id),
                     activity: laneActivity[b.id] ?? [Float](repeating: 0, count: RewindEngine.laneBuckets))
        }
    }

    /// The tape zooms so a screenful is about thirty steps, whether the editing was slow or
    /// frantic. Zoomed out, a dense burst is a solid smear; zoomed in, a slow session is a few
    /// ticks in a void.
    static func tapeWindow(for playback: TrailPlayback, at t: TimeInterval) -> TimeInterval {
        min(900, max(3, playback.typicalGap(around: t) * 30))
    }

    // MARK: - Applying

    private func apply(_ playback: TrailPlayback) {
        guard let output else { return }
        let past = playback.values(at: playhead, interpolateGaps: continuousScrub)
        var changed: [String: Double] = [:]
        for (param, pastValue) in past {
            // Peeking shows now without moving the playhead; otherwise the photo is the past.
            let shown = peeking ? (tipValues[param] ?? pastValue) : pastValue
            if let sent = lastSent[param], abs(sent - shown) < 0.000001 { continue }
            lastSent[param] = shown
            changed[param] = shown
        }
        if !changed.isEmpty { output.rewindSetParameters(changed) }
    }

    /// Restoring a whole table is a catalog write, so it only happens where the playhead
    /// settles: a landmark, a jump, or letting go.
    ///
    /// And only when the playhead is *on* the landmark. A table is the truth at its own moment,
    /// not for everything after it — restoring the morning's table because it happens to be the
    /// nearest landmark would throw away the afternoon.
    private func applyKeyframeIfNeeded(at t: TimeInterval, in playback: TrailPlayback) {
        guard let keyframe = playback.keyframe(at: t),
              abs(keyframe.t - t) < RewindEngine.landmarkWindow,
              keyframe.id != appliedKeyframeID else { return }
        guard let blob = keyframe.blob, !peeking else { return }
        appliedKeyframeID = keyframe.id
        output?.rewindRestore(blob: blob)
        // The table has just moved every slider; what we thought Lightroom held is stale, and
        // the values it reports back over the next moment are the restore, not an edit.
        lastSent.removeAll()
        ignoreRecordsUntil = Date().addingTimeInterval(RewindEngine.settleAfterRewind)
    }

    /// How close the playhead has to be to count as standing on a landmark.
    static let landmarkWindow: TimeInterval = 0.000001

    // MARK: - Readout

    private func currentPlayback() -> TrailPlayback? {
        guard let trail else { return nil }
        if let playback { return playback }
        return playbackForTrail(trail)
    }

    @discardableResult
    private func playbackForTrail(_ trail: EditTrail) -> TrailPlayback {
        let built = trail.playback()
        playback = built
        return built
    }

    private func caption(for t: TimeInterval, in playback: TrailPlayback) -> String {
        if peeking { return "Now (peek)" }
        let behind = playback.tip - t
        if behind < 0.4 { return "Now" }
        if let keyframe = playback.keyframe(at: t), abs(keyframe.t - t) < 0.2 {
            return keyframe.label
        }
        return RewindEngine.ago(behind)
    }

    /// What is under the playhead, in words: the landmark if it is on one, otherwise the thing
    /// that changed at this step ("Exposure +0.35 EV"), otherwise how long ago it was.
    private func stepCaption(for t: TimeInterval, in playback: TrailPlayback) -> String {
        if peeking { return "Now (peek)" }
        if playback.tip - t < 0.001 { return "Now" }
        if let keyframe = playback.keyframe(at: t), abs(keyframe.t - t) < TrailPlayback.stepMerge {
            return keyframe.label
        }
        if let change = describeChange(at: t, in: playback) { return change }
        return RewindEngine.ago(playback.tip - t)
    }

    /// The parameter or parameters that moved at exactly this step, with the value they landed on.
    private func describeChange(at t: TimeInterval, in playback: TrailPlayback) -> String? {
        // A fractional playhead almost never equals an event timestamp. Describe the
        // surrounding edit using the exact values sent to the live preview.
        let values = playback.values(at: t, interpolateGaps: continuousScrub)
        var nearest: (time: TimeInterval, params: [String])?
        for param in playback.parameters.sorted() {
            guard let events = playback.series[param] else { continue }
            let event = events.first { $0.t >= t - 1e-9 } ?? events.last
            guard let event else { continue }
            let distance = abs(event.t - t)
            if nearest == nil || distance < nearest!.time - 1e-9 { nearest = (distance, [param]) }
            else if abs(distance - nearest!.time) < 1e-9 { nearest!.params.append(param) }
        }
        guard let param = nearest?.params.first, let value = values[param] else { return nil }
        let name = CommandDatabase.shared.shortLabel(for: param)
        let display = ValueFormatter.format(param: param, value: value, range: output?.rewindRange(for: param))
        let extra = (nearest?.params.count ?? 0) > 1 ? " +\((nearest?.params.count ?? 1) - 1) more" : ""
        return "\(name) \(display)\(extra) · \(RewindEngine.ago(playback.tip - t))"
    }

    /// "1:32" for a point on the tape.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func ago(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.0f seconds back", seconds.rounded()) }
        if seconds < 3600 {
            let minutes = Int((seconds / 60).rounded())
            return minutes == 1 ? "a minute back" : "\(minutes) minutes back"
        }
        let hours = seconds / 3600
        return hours < 1.6 ? "an hour back" : String(format: "%.0f hours back", hours.rounded())
    }

    private func publish(caption: String) {
        let next = buildState(caption: caption)
        state = next
        changed.send(next)
    }

    func buildState(caption: String) -> RewindState {
        guard let playback = currentPlayback() else { return .empty }
        let values = peeking ? tipValues : playback.values(at: playhead, interpolateGaps: continuousScrub)
        var knobs: [RewindKnobValue] = []
        for entry in knobParams {
            let value = values[entry.param] ?? LightroomBridge.neutralValue(for: entry.param)
            let tip = tipValues[entry.param] ?? value
            knobs.append(RewindKnobValue(
                control: entry.control,
                label: CommandDatabase.shared.shortLabel(for: entry.param),
                value: value,
                display: ValueFormatter.format(param: entry.param, value: value, range: output?.rewindRange(for: entry.param)),
                isChanged: abs(tip - value) > 0.002
            ))
        }

        var marks = playback.keyframes.map { keyframe in
            TrailMark(
                id: keyframe.id,
                time: keyframe.t,
                label: keyframe.label,
                kind: TrailMark.Kind(keyframe.kind),
                branchName: nil
            )
        }
        marks += playback.forks.map { fork in
            TrailMark(id: "fork-\(fork.id)", time: fork.time, label: fork.name,
                      kind: .branch, branchName: fork.name)
        }
        marks.sort { $0.time < $1.time }

        let branchName = trail.map { $0.activeBranch }.flatMap { $0.parent == nil ? nil : $0.name }
        let tapeWindow = RewindEngine.tapeWindow(for: playback, at: playhead)
        return RewindState(
            origin: playback.start,
            tip: playback.tip,
            playhead: peeking ? playback.tip : playhead,
            window: tapeWindow,
            marks: marks,
            knobs: knobs,
            branchName: branchName,
            isPeeking: peeking,
            isAtTip: playback.tip - playhead < 0.4,
            caption: caption,
            speed: isPlaying ? min(1.0, playSpeed / 8.0) : min(1.0, jogRate / 120.0),
            rate: playSpeed,
            isPlaying: isPlaying,
            isReverse: isPlaying && playDirection < 0,
            stepNumber: max(0, playback.stepIndex(atOrBefore: playhead) + 1),
            stepCount: playback.stepTimes.count,
            tangents: makeLanes(),
            tangentNumber: (trail?.branches.firstIndex { $0.id == trail?.activeBranchID } ?? 0) + 1,
            tangentCount: trail?.branches.count ?? 1,
            tangentColorIndex: trail?.branches.firstIndex { $0.id == trail?.activeBranchID } ?? 0,
            steps: playback.steps(around: playhead, half: tapeWindow * 1.4, cap: 500),
            spanStart: laneSpan.start,
            spanEnd: laneSpan.end
        )
    }

    /// How much tape is on screen. Long sessions zoom out, short ones stay readable.
    static func window(for playback: TrailPlayback) -> TimeInterval {
        let span = max(4.0, playback.tip - playback.start)
        return min(max(20.0, span * 0.6), 900.0)
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Write the trail out. Synchronously when what happens next depends on it — swapping
    /// photos, quitting — and off the main thread otherwise, since a long session is a lot of
    /// JSON and the panel is still being turned.
    public func flush(synchronously: Bool = false) {
        saveWork?.cancel()
        saveWork = nil
        guard let trail else { return }
        let dir = storeDirectory
        let write = {
            do {
                try TrailStore.save(trail, in: dir)
            } catch {
                print("[Rewind] Could not save the trail: \(error)")
            }
        }
        if synchronously {
            // Drain older snapshots before the latest write, including photo switches.
            RewindEngine.saveQueue.sync(execute: write)
        } else {
            RewindEngine.saveQueue.async(execute: write)
        }
    }
}

extension TrailMark.Kind {
    init(_ kind: TrailKeyframe.Kind) {
        switch kind {
        case .open: self = .open
        case .mark: self = .mark
        case .branch: self = .branch
        case .mask: self = .mask
        case .crop: self = .crop
        case .preset: self = .preset
        case .paste: self = .paste
        case .reset: self = .reset
        case .action: self = .action
        }
    }
}

