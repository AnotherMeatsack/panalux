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

    /// Fires whenever the readout should be redrawn (scrub, strength, landmark, branch).
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
    private var strength: Double = 1.0
    /// The playhead is behind the tip, so the next edit starts a branch instead of overwriting.
    private var detached = false
    private var peeking = false
    /// The photo as it stood when the hold began. Rolling forward returns to exactly this.
    private var tipValues: [String: Double] = [:]
    private var lastSent: [String: Double] = [:]
    private var appliedKeyframeID: String?
    private var scrubVelocity: Double = 0
    private var lastScrubAt: Date = .distantPast
    private var pendingSnapshots: [String: String] = [:]   // token → keyframe id
    private var saveWork: DispatchWorkItem?
    /// Reports arriving before this are Lightroom catching up with Rewind, not editing.
    private var ignoreRecordsUntil: Date = .distantPast
    private static let settleAfterRewind: TimeInterval = 1.2
    /// Encoding a long trail is not work for the main thread.
    private static let saveQueue = DispatchQueue(label: "com.panalux.trail", qos: .utility)

    /// Below this many encoder units a second, one detent is one edit; above it, time flows.
    private let slowScrub: Double = 26.0
    /// Seconds of trail per encoder unit at a crawl and at a sprint.
    private let secondsPerUnitSlow: Double = 0.06
    private let secondsPerUnitFast: Double = 2.4
    private let snapWindow: TimeInterval = 0.9

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
        strength = 1.0
        // Only count a landmark as already applied if the playhead is standing on it.
        let atTip = live.keyframe(at: live.tip)
        appliedKeyframeID = (atTip.map { abs($0.t - live.tip) < RewindEngine.landmarkWindow } ?? false)
            ? atTip?.id : nil
        scrubVelocity = 0
        lastScrubAt = .distantPast
        publish(caption: "Now")
    }

    /// UNDO came up. The photo stays wherever the playhead is — that is the point.
    public func endRewind(announce: Bool = true) {
        guard isRewinding else { return }
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

    /// Centre ring. Slow is one edit at a time; fast is minutes at a time.
    public func scrub(units: Double, now: Date = Date()) {
        guard isRewinding, let playback = currentPlayback() else { return }
        let gap = max(0.001, min(0.5, now.timeIntervalSince(lastScrubAt)))
        lastScrubAt = now
        let instant = abs(units) / gap
        // Smoothed so one fast packet in a slow turn does not throw the playhead across the tape.
        scrubVelocity = scrubVelocity * 0.7 + instant * 0.3

        if scrubVelocity < slowScrub {
            playhead = playback.stepToEdit(from: playhead, forward: units > 0)
        } else {
            let normalized = min(1.0, (scrubVelocity - slowScrub) / (slowScrub * 8))
            let perUnit = secondsPerUnitSlow + (secondsPerUnitFast - secondsPerUnitSlow) * normalized * normalized
            playhead += units * perUnit
        }
        playhead = min(playback.tip, max(playback.start, playhead))
        if scrubVelocity < slowScrub * 2, let snap = playback.snapTarget(near: playhead, within: snapWindow) {
            playhead = snap
        }
        apply(playback)
        publish(caption: caption(for: playhead, in: playback))
    }

    /// Right ring. How far toward the scrub point, 0–100%.
    public func adjustStrength(units: Double) {
        guard isRewinding, let playback = currentPlayback() else { return }
        strength = min(1.0, max(0.0, strength + units * 0.004))
        apply(playback)
        publish(caption: strength >= 0.999 ? caption(for: playhead, in: playback)
                                           : "\(Int((strength * 100).rounded()))% of the way back")
    }

    /// One key back to now.
    public func jumpToTip() {
        guard isRewinding, let playback = currentPlayback() else { return }
        playhead = playback.tip
        strength = 1.0
        apply(playback)
        applyKeyframeIfNeeded(at: playhead, in: playback)
        detached = false
        publish(caption: "Now")
    }

    public func step(forward: Bool) {
        guard isRewinding, let playback = currentPlayback() else { return }
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
        let mix = peeking ? 0.0 : strength
        for (param, pastValue) in past {
            let live = tipValues[param] ?? pastValue
            let blended = live + (pastValue - live) * mix
            if let sent = lastSent[param], abs(sent - blended) < 0.0008 { continue }
            lastSent[param] = blended
            output.rewindSetParameter(param, value: blended)
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
        guard let blob = keyframe.blob, !peeking, strength > 0.999 else { return }
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
            strength: peeking ? 0 : strength,
            marks: marks,
            knobs: knobs,
            branchName: branchName,
            isPeeking: peeking,
            isAtTip: playback.tip - playhead < 0.4,
            caption: caption,
            speed: min(1.0, scrubVelocity / (slowScrub * 8))
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

