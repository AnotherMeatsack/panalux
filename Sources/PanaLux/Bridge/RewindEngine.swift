import Foundation
import Combine

/// Everything Rewind needs from Lightroom. A protocol so the recorder can be tested without
/// a catalog, a panel, or a socket.
public protocol RewindOutput: AnyObject {
    /// Every develop value PanaLux currently believes in.
    func rewindKnownValues() -> [String: Double]
    func rewindSetParameter(_ name: String, value: Double)
    /// Ask the plugin for a full `getDevelopSettings()` table; the reply comes back by id.
    func rewindRequestSnapshot(token: String)
    /// Hand a table back to the plugin. This is what restores masks and crop exactly.
    func rewindRestore(blob: String)
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

    public weak var output: RewindOutput?
    /// The twelve knobs as they are mapped right now, for the rolling readout.
    public var knobParams: [(control: String, param: String)] = []
    /// Trails are only written for photos Lightroom has actually named.
    public private(set) var photoID: String?
    public private(set) var trail: EditTrail?
    /// Where trails are kept. nil means the usual place beside the map; tests point it elsewhere.
    public var storeDirectory: URL?

    private var playback: TrailPlayback?
    private var playhead: TimeInterval = 0
    /// The playhead is behind the tip, so the next edit starts a branch instead of overwriting.
    private var detached = false
    private var peeking = false
    /// The photo as it stood when the hold began. Rolling forward returns to exactly this.
    private var tipValues: [String: Double] = [:]
    private var lastSent: [String: Double] = [:]
    private var appliedKeyframeID: String?
    private var lastScrubAt: Date = .distantPast
    private var pendingSnapshots: [String: String] = [:]   // token → keyframe id
    private var saveWork: DispatchWorkItem?
    /// Reports arriving before this are Lightroom catching up with Rewind, not editing.
    private var ignoreRecordsUntil: Date = .distantPast
    private static let settleAfterRewind: TimeInterval = 1.2
    /// Encoding a long trail is not work for the main thread.
    private static let saveQueue = DispatchQueue(label: "com.panalux.trail", qos: .utility)

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

    // MARK: Transport
    public private(set) var isPlaying = false
    private var playDirection: Double = 1
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

    // MARK: - Photo lifecycle

    /// Lightroom put a different photo on screen. Save what we have and pick up that photo's trail.
    public func setActivePhoto(_ id: String?) {
        guard id != photoID else { return }
        // The trail being left behind has to be on disk before the next one is read.
        flush(synchronously: true)
        endRewind(announce: false)
        photoID = id
        guard let id, !id.isEmpty else {
            trail = nil
            playback = nil
            return
        }
        var loaded = TrailStore.load(photoID: id, in: storeDirectory) ?? EditTrail(photoID: id)
        loaded.resume()
        trail = loaded
        playback = nil
        detached = false
        // The photo as it arrives is a landmark in its own right: somewhere to get back to.
        captureKeyframe(kind: .open, label: "Opened")
    }

    // MARK: - Recording

    /// Every reported value change, whoever caused it — a knob, a mouse, a preset.
    public func record(param: String, value: Double, at wall: Date = Date()) {
        // While scrubbing, the values coming back are our own playback. Recording them would
        // tape over the recording.
        guard !isRewinding, trail != nil else { return }
        guard !param.isEmpty else { return }
        // Letting go, or putting a settings table back, makes Lightroom resend everything a
        // moment later. None of that is editing, and none of it should start a branch.
        guard wall >= ignoreRecordsUntil else { return }
        // Lightroom confirms what Rewind just wrote. That is the playback coming back, not an
        // edit: recording it would tape over the trail, and worse, would look like a new branch.
        if let sent = lastSent[param], abs(sent - value) < 0.003 { return }
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
        publish(caption: "Now")
    }

    /// UNDO came up. The photo stays wherever the playhead is — that is the point.
    public func endRewind(announce: Bool = true) {
        guard isRewinding else { return }
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
    }

    // MARK: - Scrubbing

    /// How many steps one click covers. Slow is exactly one, and that never changes; faster
    /// eases up smoothly, with no seam between "careful" and "travelling", to at most a fortieth
    /// of the session per click so a hard spin crosses any length of session in a second or two.
    static func jogMultiplier(rate: Double, stepCount: Int, acceleration: Double) -> Int {
        let careful = 10.0     // clicks a second: a deliberate turn
        let flat = 70.0        // clicks a second: a hard spin
        let reach = max(1.0, Double(stepCount) / 40.0) * (0.25 + 1.5 * min(1, max(0, acceleration)))
        let s = min(1.0, max(0.0, (rate - careful) / (flat - careful)))
        return max(1, Int((1.0 + (reach - 1.0) * s * s).rounded()))
    }

    /// Centre ring. One click is one thing that changed: every value you had is somewhere the
    /// playhead can stop. Turn faster and it travels; stop turning and it holds exactly there.
    public func scrub(units: Double, now: Date = Date()) {
        guard isRewinding, let playback = currentPlayback() else { return }
        // Taking hold of the ring takes over from playback.
        pausePlayback(announce: false)
        let gap = max(0.001, min(0.5, now.timeIntervalSince(lastScrubAt)))
        lastScrubAt = now
        // Turning back the other way starts a fresh click rather than paying off the old one.
        if units * jogRemainder < 0 { jogRemainder = 0 }
        jogRemainder += units
        let clicks = Int((jogRemainder / max(1, clickUnits)).rounded(.towardZero))
        guard clicks != 0 else { return }
        jogRemainder -= Double(clicks) * clickUnits

        let instant = abs(units) / gap / max(1, clickUnits)
        jogRate = jogRate * 0.6 + instant * 0.4
        let reach = RewindEngine.jogMultiplier(rate: jogRate, stepCount: playback.stepTimes.count,
                                               acceleration: acceleration)
        playhead = playback.step(from: playhead, by: clicks * reach)
        apply(playback)
        publish(caption: stepCaption(for: playhead, in: playback))
    }

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
                                values: playback.values(at: playhead))
            publish(caption: "Marked")
        } else {
            _ = captureKeyframe(kind: .mark, label: "Mark")
        }
    }

    /// One press, new tangent. The abandoned line is kept, whole.
    public func startBranch(reason: String = "Branch", at wall: Date = Date()) {
        guard let existing = trail else { return }
        let at = isRewinding || detached ? playhead : existing.tipTime
        let values = currentPlayback()?.values(at: at) ?? existing.playback().values(at: at)
        let branch = trail?.fork(at: at, wall: wall)
        detached = false
        playback = nil
        appliedKeyframeID = nil
        if let branch {
            _ = captureKeyframe(kind: .branch, label: branch.name, at: wall, time: at, values: values)
        }
        scheduleSave()
        publish(caption: reason)
    }

    // MARK: - Applying

    private func apply(_ playback: TrailPlayback) {
        guard let output else { return }
        let past = playback.values(at: playhead)
        for (param, pastValue) in past {
            // Peeking shows now without moving the playhead; otherwise the photo is the past.
            let shown = peeking ? (tipValues[param] ?? pastValue) : pastValue
            if let sent = lastSent[param], abs(sent - shown) < 0.0008 { continue }
            lastSent[param] = shown
            output.rewindSetParameter(param, value: shown)
        }
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
    static let landmarkWindow: TimeInterval = 0.25

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
        var moved: [(name: String, text: String)] = []
        for param in playback.parameters.sorted() {
            guard let events = playback.series[param],
                  let e = events.first(where: { abs($0.t - t) < TrailPlayback.stepMerge }) else { continue }
            moved.append((CommandDatabase.shared.shortLabel(for: param),
                          ValueFormatter.format(param: param, value: e.value)))
        }
        guard let first = moved.first else { return nil }
        var text = "\(first.name) \(first.text)"
        if moved.count > 1 { text += " +\(moved.count - 1) more" }
        return text
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
        let values = peeking ? tipValues : playback.values(at: playhead)
        var knobs: [RewindKnobValue] = []
        for entry in knobParams {
            let value = values[entry.param] ?? LightroomBridge.neutralValue(for: entry.param)
            let tip = tipValues[entry.param] ?? value
            knobs.append(RewindKnobValue(
                control: entry.control,
                label: CommandDatabase.shared.shortLabel(for: entry.param),
                value: value,
                display: ValueFormatter.format(param: entry.param, value: value),
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
        return RewindState(
            origin: playback.start,
            tip: playback.tip,
            playhead: peeking ? playback.tip : playhead,
            window: RewindEngine.window(for: playback),
            marks: marks,
            knobs: knobs,
            branchName: branchName,
            isPeeking: peeking,
            isAtTip: playback.tip - playhead < 0.4,
            caption: caption,
            speed: isPlaying ? min(1.0, playSpeed / 8.0) : min(1.0, jogRate / 70.0),
            rate: playSpeed,
            isPlaying: isPlaying,
            isReverse: isPlaying && playDirection < 0,
            stepNumber: max(0, playback.stepIndex(atOrBefore: playhead) + 1),
            stepCount: playback.stepTimes.count
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
            write()
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

