import XCTest
@testable import PanaLux

/// The trail is the whole promise: it records everything, it can rebuild any moment, and it
/// never destroys a future to make room for a new one.
final class EditTrailTests: XCTestCase {

    /// A gesture: many samples close together. An edit: one value, then a long pause.
    private func gesture(_ trail: inout EditTrail, param: String, from: Double, to: Double,
                         start: TimeInterval, steps: Int = 10, spacing: TimeInterval = 0.05) {
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            trail.record(param: param, value: from + (to - from) * f, at: start + Double(i) * spacing)
        }
    }

    func testRecordsEveryMoveAndDropsRepeats() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.5, at: 1.0)
        trail.record(param: "Exposure", value: 0.6, at: 1.1)
        trail.record(param: "Exposure", value: 0.6, at: 1.2)   // the knob reported, nothing moved
        trail.record(param: "Exposure", value: 0.6, at: 40.0)  // a full refresh, much later
        trail.record(param: "Contrast", value: 0.7, at: 1.3)
        XCTAssertEqual(trail.activeBranch.events.count, 3)
        XCTAssertEqual(trail.activeBranch.events.map(\.param), ["Exposure", "Exposure", "Contrast"])
    }

    func testRebuildsAMomentInTime() {
        var trail = EditTrail(photoID: "cat:1")
        gesture(&trail, param: "Exposure", from: 0.5, to: 0.8, start: 1.0)   // 1.0 … 1.5
        trail.record(param: "Contrast", value: 0.75, at: 9.0)
        let playback = trail.playback()

        // Inside the gesture the value is interpolated: scrubbing is continuous.
        XCTAssertEqual(playback.value(of: "Exposure", at: 1.25) ?? 0, 0.65, accuracy: 0.01)
        // After it, the value simply held. The playhead steps instead of drifting.
        XCTAssertEqual(playback.value(of: "Exposure", at: 5.0) ?? 0, 0.8, accuracy: 0.0001)
        // Before a parameter was ever touched it has no value to restore.
        XCTAssertNil(playback.value(of: "Contrast", at: 5.0))
        XCTAssertEqual(playback.values(at: 9.0)["Contrast"] ?? 0, 0.75, accuracy: 0.0001)
    }

    func testValuesBetweenGesturesDoNotDriftTowardTheNextEdit() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.2, at: 1.0)
        trail.record(param: "Exposure", value: 0.9, at: 61.0)  // a minute later, a fresh move
        let playback = trail.playback()
        // Halfway between them the photo was still at 0.2, not at 0.55.
        XCTAssertEqual(playback.value(of: "Exposure", at: 31.0) ?? 0, 0.2, accuracy: 0.0001)
    }

    func testEveryChangeIsAStepAndTheEndsAreAlwaysPlacesToStand() {
        var trail = EditTrail(photoID: "cat:1")
        // A trackball's hue and saturation land a few milliseconds apart: one move, one step.
        trail.record(param: "GradeHue", value: 0.30, at: 2.000)
        trail.record(param: "GradeSat", value: 0.40, at: 2.010)
        trail.record(param: "Exposure", value: 0.60, at: 5.0)
        trail.record(param: "Exposure", value: 0.70, at: 9.0)
        let steps = trail.playback().stepTimes
        XCTAssertEqual(steps.count, 4, "start, the trackball move, two exposure changes")
        XCTAssertEqual(steps.first ?? -1, trail.playback().start, accuracy: 0.0001)
        XCTAssertEqual(steps.last ?? -1, 9.0, accuracy: 0.0001, "the last step is where it ends up")
    }

    func testOneClickIsOneStepAndBackAgainLandsOnTheSameSpot() {
        var trail = EditTrail(photoID: "cat:1")
        for (i, v) in [0.51, 0.52, 0.53, 0.54, 0.55].enumerated() {
            trail.record(param: "Exposure", value: v, at: 10.0 + Double(i) * 2.0)   // 10, 12, 14, 16, 18
        }
        let playback = trail.playback()
        let steps = playback.stepTimes
        let last = steps.count - 1
        XCTAssertEqual(playback.step(from: steps[last], by: -1), steps[last - 1], accuracy: 0.0001)
        XCTAssertEqual(playback.step(from: steps[last], by: -3), steps[last - 3], accuracy: 0.0001)
        XCTAssertEqual(playback.step(from: steps[last - 3], by: 3), steps[last], accuracy: 0.0001)
        // From between two steps, forward lands ahead and back lands behind: neither skips one.
        let between = (steps[2] + steps[3]) / 2
        XCTAssertEqual(playback.step(from: between, by: 1), steps[3], accuracy: 0.0001)
        XCTAssertEqual(playback.step(from: between, by: -1), steps[2], accuracy: 0.0001)
        // The ends park; they do not wrap.
        XCTAssertEqual(playback.step(from: steps[0], by: -5), steps[0], accuracy: 0.0001)
        XCTAssertEqual(playback.step(from: steps[last], by: 99), steps[last], accuracy: 0.0001)
    }

    func testATakeLeavesTheLineThatOwnsThatMoment() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.6, at: 10.0)
        trail.record(param: "Exposure", value: 0.7, at: 30.0)
        let original = trail.activeBranchID
        let second = trail.fork(at: 20.0, wall: Date())                  // Tangent 2 leaves the original at 20 s
        trail.record(param: "Contrast", value: 0.8, at: 25.0)

        // Rewinding to 5 s and editing while Tangent 2 is active: 5 s belongs to the original, not to
        // Tangent 2 (which only begins at 20 s), so that is where the new tangent must hang.
        let third = trail.fork(at: 5.0, wall: Date())
        XCTAssertEqual(third.parent, original, "a tangent cannot start before its parent does")
        XCTAssertEqual(trail.lineage().map(\.id), [original, third.id])

        // And one from later than Tangent 2's start does hang off Tangent 2.
        trail.activate(second.id)
        let fourth = trail.fork(at: 22.0, wall: Date())
        XCTAssertEqual(fourth.parent, second.id)
        // Every tangent can still be played back from the start, in order.
        for id in [original, second.id, third.id, fourth.id] {
            let playback = trail.playback(on: id)
            XCTAssertEqual(playback.stepTimes, playback.stepTimes.sorted(), id)
            XCTAssertLessThanOrEqual(playback.start, playback.tip)
        }
    }

    func testTangentsMadeWhenTheyWereCalledTakesAreRenamedOnLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var trail = EditTrail(photoID: "cat:9")
        trail.record(param: "Exposure", value: 0.6, at: 10)
        let old = trail.fork(at: 5, name: "Take 2")
        _ = trail.addKeyframe(TrailKeyframe(t: 5, kind: .branch, label: "Take 2"))
        _ = trail.fork(at: 6, name: "Tangent 3")                          // already new: left alone
        _ = trail.fork(at: 7, name: "Take here")                          // a name of someone's own: left alone
        try TrailStore.save(trail, in: dir)

        let loaded = try XCTUnwrap(TrailStore.load(photoID: "cat:9", in: dir))
        XCTAssertEqual(loaded.branches.map(\.name), ["Original", "Tangent 2", "Tangent 3", "Take here"])
        let fork = loaded.branches.first { $0.id == old.id }
        XCTAssertEqual(fork?.keyframes.first { $0.kind == .branch }?.label, "Tangent 2",
                       "the landmark and the tangent still share a name, so the tape can colour it")
    }

    func testActivatingATakeContinuesItsClockAfterItsOwnTip() {
        var trail = EditTrail(photoID: "cat:1")
        let root = trail.activeBranchID
        trail.record(param: "Exposure", value: 0.6, at: 40.0)
        _ = trail.fork(at: 10.0, wall: Date())
        let later = Date().addingTimeInterval(500)
        trail.activate(root, at: later)
        // Now, on the original, is just after where the original ended, not 500 s later.
        XCTAssertEqual(trail.time(at: later), 40.0 + EditTrail.resumeGap, accuracy: 0.01)
    }

    func testKeyframeSeedsParametersTheStreamNeverSaw() {
        var trail = EditTrail(photoID: "cat:1")
        _ = trail.addKeyframe(TrailKeyframe(t: 0, kind: .open, label: "Opened",
                                            values: ["Contrast": 0.5, "Texture": 0.4]))
        trail.record(param: "Exposure", value: 0.7, at: 2.0)
        let values = trail.playback().values(at: 3.0)
        XCTAssertEqual(values["Texture"] ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(values["Exposure"] ?? 0, 0.7, accuracy: 0.0001)
    }

    func testBranchingKeepsTheParentWhole() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.3, at: 1.0)
        trail.record(param: "Exposure", value: 0.9, at: 20.0)   // the future that gets rolled past
        let parentID = trail.activeBranchID
        let parentEvents = trail.activeBranch.events

        let branch = trail.fork(at: 10.0, name: "Tangent 2")
        trail.record(param: "Exposure", value: 0.1, at: 11.0)

        // The parent is untouched: its whole future is still there.
        XCTAssertEqual(trail.branch(parentID)?.events, parentEvents)
        XCTAssertEqual(trail.branch(parentID)?.events.count, 2)

        // The branch sees the parent up to the fork, and its own work after it.
        let onBranch = trail.playback()
        XCTAssertEqual(onBranch.value(of: "Exposure", at: 5.0) ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(onBranch.value(of: "Exposure", at: 12.0) ?? 0, 0.1, accuracy: 0.0001)

        // …and never the parent's abandoned future.
        XCTAssertEqual(onBranch.value(of: "Exposure", at: 30.0) ?? 0, 0.1, accuracy: 0.0001)

        // The parent, played on its own, still ends where it did.
        let onParent = trail.playback(on: parentID)
        XCTAssertEqual(onParent.value(of: "Exposure", at: 30.0) ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertEqual(branch.parent, parentID)
    }

    func testBranchOfABranchKeepsEveryLine() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.2, at: 1.0)
        let first = trail.activeBranchID
        _ = trail.fork(at: 2.0, name: "Tangent 2")
        trail.record(param: "Exposure", value: 0.4, at: 3.0)
        let second = trail.activeBranchID
        _ = trail.fork(at: 3.5, name: "Tangent 3")
        trail.record(param: "Exposure", value: 0.6, at: 4.0)

        XCTAssertEqual(trail.branches.count, 3)
        XCTAssertEqual(trail.playback(on: first).value(of: "Exposure", at: 10) ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(trail.playback(on: second).value(of: "Exposure", at: 10) ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(trail.playback().value(of: "Exposure", at: 10) ?? 0, 0.6, accuracy: 0.0001)
        // The line the playhead is on knows where the others left it.
        XCTAssertEqual(trail.forks(of: second).map(\.name), ["Tangent 3"])
    }

    func testLandmarksAndSnapping() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.3, at: 1.0)
        _ = trail.addKeyframe(TrailKeyframe(t: 5.0, kind: .mask, label: "New Radial Mask"))
        _ = trail.addKeyframe(TrailKeyframe(t: 12.0, kind: .mark, label: "Mark"))
        let playback = trail.playback()

        XCTAssertEqual(playback.keyframe(at: 6.0)?.label, "New Radial Mask")
        XCTAssertEqual(playback.previousLandmark(before: 12.0)?.label, "New Radial Mask")
        XCTAssertEqual(playback.nextLandmark(after: 6.0)?.label, "Mark")
        // A mask is a landmark but not a snap; a mark pulls the playhead in.
        XCTAssertEqual(playback.snapTarget(near: 12.4, within: 0.9) ?? 0, 12.0, accuracy: 0.0001)
        XCTAssertNil(playback.snapTarget(near: 5.2, within: 0.9))
    }

    func testSlowScrubWalksOneEditAtATime() {
        var trail = EditTrail(photoID: "cat:1")
        gesture(&trail, param: "Exposure", from: 0.5, to: 0.8, start: 1.0)   // one edit
        gesture(&trail, param: "Contrast", from: 0.5, to: 0.2, start: 20.0)  // another
        let playback = trail.playback()
        XCTAssertEqual(playback.editTimes.count, 2)
        XCTAssertEqual(playback.stepToEdit(from: 25.0, forward: false), 20.0, accuracy: 0.0001)
        XCTAssertEqual(playback.stepToEdit(from: 5.0, forward: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(playback.stepToEdit(from: 5.0, forward: true), 20.0, accuracy: 0.0001)
        // Walking off either end parks on the end, it does not wrap.
        XCTAssertEqual(playback.stepToEdit(from: 0.0, forward: false), playback.start, accuracy: 0.0001)
        XCTAssertEqual(playback.stepToEdit(from: 99.0, forward: true), playback.tip, accuracy: 0.0001)
    }

    func testTipIsNeverMovedByRollingBack() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.3, at: 1.0)
        trail.record(param: "Exposure", value: 0.9, at: 30.0)
        let tip = trail.tipTime
        XCTAssertEqual(tip, 30.0, accuracy: 0.0001)
        // Reading the past cannot change the recording.
        _ = trail.playback().values(at: 2.0)
        XCTAssertEqual(trail.tipTime, tip, accuracy: 0.0001)
    }

    func testPersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        var trail = EditTrail(photoID: "My Catalog:1234")
        _ = trail.addKeyframe(TrailKeyframe(id: "k1", t: 0, kind: .open, label: "Opened",
                                            values: ["Exposure": 0.5], blob: "BASE64=="))
        gesture(&trail, param: "Exposure", from: 0.5, to: 0.8, start: 1.0)
        _ = trail.fork(at: 1.2, name: "Tangent 2")
        trail.record(param: "Contrast", value: 0.25, at: 2.0)
        XCTAssertTrue(trail.attachBlob("MASKS==", toKeyframe: "k1"))

        try TrailStore.save(trail, in: dir)
        let loaded = try XCTUnwrap(TrailStore.load(photoID: "My Catalog:1234", in: dir))

        XCTAssertEqual(loaded.branches.count, 2)
        XCTAssertEqual(loaded.activeBranchID, trail.activeBranchID)
        XCTAssertEqual(loaded.photoID, "My Catalog:1234")
        XCTAssertEqual(loaded.playback().keyframes.first?.blob, "MASKS==")
        XCTAssertEqual(loaded.playback().value(of: "Contrast", at: 3.0) ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(loaded.playback().value(of: "Exposure", at: 1.1) ?? 0,
                       trail.playback().value(of: "Exposure", at: 1.1) ?? -1, accuracy: 0.0001)
        // A photo id is a catalog string, not a filename.
        XCTAssertFalse(TrailStore.fileName(for: "a/b c:1").contains("/"))
        XCTAssertEqual(TrailStore.fileName(for: "cat:1"), TrailStore.fileName(for: "cat:1"))
        XCTAssertNotEqual(TrailStore.fileName(for: "cat:1"), TrailStore.fileName(for: "cat:2"))
    }

    func testMissingOrForeignFilesAreIgnoredRatherThanCrashing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(TrailStore.load(photoID: "nothing here", in: dir))
        try Data("not json".utf8).write(to: TrailStore.url(for: "cat:9", in: dir))
        XCTAssertNil(TrailStore.load(photoID: "cat:9", in: dir))
    }

    func testResumingASessionKeepsTheTapeDense() {
        var trail = EditTrail(photoID: "cat:1")
        trail.record(param: "Exposure", value: 0.3, at: 4.0)
        // The app was quit for an hour. The trail should continue, not carry the hour.
        let later = Date().addingTimeInterval(3600)
        trail.resume(at: later)
        XCTAssertEqual(trail.time(at: later), 4.0 + EditTrail.resumeGap, accuracy: 0.01)
        XCTAssertEqual(trail.tipTime, 4.0, accuracy: 0.0001)
    }

    func testLongRecordingsAreThinnedFromTheOldestEndOnly() {
        var events: [TrailEvent] = []
        for i in 0..<1000 {
            events.append(TrailEvent(t: Double(i) * 0.05, param: "Exposure", value: Double(i) / 1000))
        }
        let recent = Array(events.suffix(500))
        EditTrail.thin(&events)
        XCTAssertLessThan(events.count, 1000)
        XCTAssertEqual(Array(events.suffix(500)), recent, "the recent past is never thinned")
    }
}

/// Stands in for Lightroom: remembers what Rewind wrote and what it asked for.
final class FakeLightroom: RewindOutput {
    var values: [String: Double] = [:]
    var sent: [(param: String, value: Double)] = []
    var snapshotTokens: [String] = []
    var restored: [String] = []

    func rewindKnownValues() -> [String: Double] { values }
    func rewindSetParameter(_ name: String, value: Double) {
        values[name] = value
        sent.append((param: name, value: value))
    }
    func rewindRequestSnapshot(token: String) { snapshotTokens.append(token) }
    func rewindRestore(blob: String) { restored.append(blob) }
}

final class RewindEngineTests: XCTestCase {
    private var dir: URL!
    private var lightroom: FakeLightroom!
    private var engine: RewindEngine!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        lightroom = FakeLightroom()
        engine = RewindEngine()
        engine.storeDirectory = dir
        engine.output = lightroom
        engine.knobParams = [(control: "Y_GAMMA", param: "Exposure"), (control: "CONTRAST", param: "Contrast")]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// Records a move as though Lightroom reported it, at a chosen moment on the trail.
    private func edit(_ param: String, _ value: Double, secondsFromStart: TimeInterval) {
        // A real move lands in Lightroom first; the plugin then reports it.
        lightroom.values[param] = value
        let branch = engine.trail!.activeBranch
        engine.record(param: param, value: value,
                      at: branch.clockOrigin.addingTimeInterval(secondsFromStart - branch.forkTime))
    }

    private func start(photo: String = "cat:1") {
        lightroom.values = ["Exposure": 0.5, "Contrast": 0.5]
        engine.setActivePhoto(photo)
    }

    func testOpeningAPhotoStartsATrailAndAsksForTheTable() {
        start()
        XCTAssertEqual(engine.photoID, "cat:1")
        XCTAssertEqual(engine.trail?.playback().keyframes.first?.kind, .open)
        XCTAssertEqual(lightroom.snapshotTokens.count, 1, "the photo as it arrived is worth a table")
    }

    func testTheSnapshotComesBackAndAttachesToItsKeyframe() {
        start()
        let token = try! XCTUnwrap(lightroom.snapshotTokens.first)
        engine.acceptSnapshot(token: token, blob: "TABLE==")
        XCTAssertEqual(engine.trail?.playback().keyframes.first?.blob, "TABLE==")
        // A reply nobody asked for is ignored rather than attached to the wrong moment.
        engine.acceptSnapshot(token: "not-a-token", blob: "JUNK")
        XCTAssertEqual(engine.trail?.playback().keyframes.first?.blob, "TABLE==")
    }

    func testEveryReportedMoveIsRecorded() {
        start()
        edit("Exposure", 0.6, secondsFromStart: 1.0)
        edit("Exposure", 0.7, secondsFromStart: 1.1)
        edit("Contrast", 0.8, secondsFromStart: 2.0)
        XCTAssertEqual(engine.trail?.activeBranch.events.count, 3)
    }

    func testPlaybackComingBackFromLightroomIsNotRecordedAsAnEdit() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 1.0)
        engine.beginRewind()
        engine.scrub(units: 400, now: Date())          // roll back
        let written = lightroom.values["Exposure"] ?? 0
        engine.endRewind()
        let before = engine.trail?.activeBranch.events.count ?? 0

        // Lightroom confirms what Rewind just wrote. That is not an edit, and must not branch,
        // however long it takes to come back.
        engine.record(param: "Exposure", value: written, at: Date().addingTimeInterval(5))
        XCTAssertEqual(engine.trail?.activeBranch.events.count, before)
        XCTAssertEqual(engine.trail?.branches.count, 1, "an echo is not a new line of editing")
    }

    func testScrubbingMovesThePhotoAndLettingGoLeavesItThere() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 4.0)
        engine.beginRewind()
        XCTAssertEqual(engine.state.isAtTip, true)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.9, accuracy: 0.0001)

        engine.scrub(units: -600, now: Date())
        XCTAssertLessThan(engine.state.playhead, engine.state.tip)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.5, accuracy: 0.05,
                       "rolled back before the move, the photo is where it started")

        engine.endRewind()
        XCTAssertFalse(engine.isRewinding)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.5, accuracy: 0.05,
                       "letting go leaves the photo wherever the playhead is")
    }

    func testBackToNowReturnsToTheTip() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 4.0)
        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        engine.jumpToTip()
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertTrue(engine.state.isAtTip)
    }

    func testPeekShowsNowWithoutLeavingThePast() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 4.0)
        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        let parked = engine.state.playhead

        engine.setPeeking(true)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.9, accuracy: 0.0001)
        engine.setPeeking(false)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.5, accuracy: 0.05)
        XCTAssertEqual(engine.state.playhead, parked, accuracy: 0.0001)
    }

    func testEditingFromTheRolledBackPointBranchesAndKeepsTheFuture() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 10.0)
        let originalID = engine.trail!.activeBranchID
        let originalEvents = engine.trail!.activeBranch.events

        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        engine.endRewind()

        // The next real move — once Lightroom has finished catching up — starts a new line
        // rather than overwriting the old one.
        engine.record(param: "Contrast", value: 0.2, at: Date().addingTimeInterval(3))
        XCTAssertEqual(engine.trail?.branches.count, 2)
        XCTAssertNotEqual(engine.trail?.activeBranchID, originalID)
        XCTAssertEqual(engine.trail?.branch(originalID)?.events, originalEvents,
                       "the abandoned line is kept, whole")
        XCTAssertEqual(engine.trail?.playback(on: originalID).value(of: "Exposure", at: 20) ?? 0,
                       0.9, accuracy: 0.0001)
    }

    func testBranchKeyStartsALineWithoutLosingAnything() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 10.0)
        let originalID = engine.trail!.activeBranchID
        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        engine.startBranch()
        XCTAssertEqual(engine.trail?.branches.count, 2)
        XCTAssertEqual(engine.state.branchName, "Tangent 2")
        XCTAssertEqual(engine.trail?.playback(on: originalID).value(of: "Exposure", at: 20) ?? 0,
                       0.9, accuracy: 0.0001)
        // Branching again forks the branch, and still keeps both parents.
        engine.startBranch()
        XCTAssertEqual(engine.trail?.branches.count, 3)
    }

    func testMarksAreLandmarksTheReadoutShows() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 4.0)
        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        engine.mark()
        let marks = engine.state.marks.filter { $0.kind == .mark }
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks.first?.time ?? -1, engine.state.playhead, accuracy: 0.0001)
    }

    func testSteppingLandmarksRestoresTheirWholeTable() {
        start()
        let token = try! XCTUnwrap(lightroom.snapshotTokens.first)
        engine.acceptSnapshot(token: token, blob: "OPENED==")
        edit("Exposure", 0.9, secondsFromStart: 10.0)
        engine.beginRewind()

        engine.step(forward: false)
        XCTAssertEqual(lightroom.restored, ["OPENED=="],
                       "landing on a landmark puts its masks and crop back too")
        // Landing on the same landmark twice does not write the catalog twice.
        engine.step(forward: false)
        XCTAssertEqual(lightroom.restored.count, 1)
    }

    func testStructuralEditsBecomeLandmarks() {
        start()
        engine.noteStructuralEdit("MaskNewRad", label: "New Radial Mask")
        engine.noteStructuralEdit("Exposure", label: "Exposure")   // a slider is not structural
        let kinds = engine.trail?.playback().keyframes.map(\.kind) ?? []
        XCTAssertEqual(kinds, [.open, .mask])
        XCTAssertEqual(RewindEngine.structuralKind(of: "LRPaste"), .paste)
        XCTAssertEqual(RewindEngine.structuralKind(of: "CropLeft"), .crop)
        XCTAssertNil(RewindEngine.structuralKind(of: "Contrast"))
    }

    func testTheTrailSurvivesQuitting() {
        start()
        edit("Exposure", 0.85, secondsFromStart: 3.0)
        engine.setActivePhoto("cat:2")          // saves the first photo's trail on the way out

        let reopened = RewindEngine()
        reopened.storeDirectory = dir
        reopened.output = lightroom
        reopened.setActivePhoto("cat:1")
        XCTAssertEqual(reopened.trail?.playback().value(of: "Exposure", at: 3.0) ?? 0,
                       0.85, accuracy: 0.0001)
        // …and continues where it left off rather than carrying the gap.
        XCTAssertGreaterThan(reopened.trail?.tipTime ?? 0, 3.0)
    }

    func testTheReadoutDescribesWhereThePlayheadIs() {
        start()
        edit("Exposure", 0.9, secondsFromStart: 4.0)
        engine.beginRewind()
        XCTAssertEqual(engine.state.caption, "Now")
        XCTAssertEqual(engine.state.knobs.map(\.control), ["Y_GAMMA", "CONTRAST"])
        XCTAssertFalse(engine.state.knobs[0].isChanged)

        engine.scrub(units: -600, now: Date())
        XCTAssertTrue(engine.state.knobs[0].isChanged, "the rolled-back knob reads differently")
        XCTAssertFalse(engine.state.isAtTip)
        XCTAssertEqual(RewindEngine.ago(90), "2 minutes back")
        XCTAssertEqual(RewindEngine.ago(20), "20 seconds back")
    }
}

final class TrailTrackTests: XCTestCase {
    private let headX: CGFloat = 400 * 0.62
    private let scale: CGFloat = 376 / 200          // 376pt of track, 200 seconds across it

    private func place(_ marks: [TrailMark], playhead: TimeInterval) -> [TrailTrack.PlacedMark] {
        TrailTrack.layout(marks: marks, playhead: playhead, headX: headX, scale: scale, width: 376)
    }

    func testGlyphsThatLandOnTopOfEachOtherAreNudgedApart() {
        let pileUp = (0..<4).map { i in
            TrailMark(id: "\(i)", time: 60 + Double(i), label: "Edit \(i)", kind: .mask)
        }
        let placed = place(pileUp, playhead: 62)
        XCTAssertEqual(placed.count, 4)
        let raw = scale * 1.0   // one second apart
        XCTAssertGreaterThanOrEqual(placed[1].x - placed[0].x, TrailTrack.glyphSpacing - 0.001,
                                    "two landmarks on top of each other pull apart")
        for (a, b) in zip(placed, placed.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.x - a.x, raw - 0.001,
                                        "spreading a cluster never makes it tighter, or reorders it")
        }
        // …but never moved so far that the tape lies about when something happened.
        for item in placed {
            let honest = headX + CGFloat(item.mark.time - 62) * scale
            XCTAssertLessThanOrEqual(abs(item.x - honest), TrailTrack.maxGlyphNudge + 0.001)
        }
    }

    func testTheTapeMovesUnderAStillPlayhead() {
        let mark = TrailMark(id: "a", time: 100, label: "Mark", kind: .mark)
        let atTip = place([mark], playhead: 100).first
        let rolledBack = place([mark], playhead: 60).first
        XCTAssertEqual(atTip?.x ?? 0, headX, accuracy: 0.001, "a landmark under the playhead sits on it")
        // Roll back 40 seconds and the same landmark has moved 40 seconds to the right.
        XCTAssertEqual((rolledBack?.x ?? 0) - headX, 40 * scale, accuracy: 0.001)
    }

    func testLabelsThatLandTogetherGoOnDifferentRows() {
        let crowded = [
            TrailMark(id: "a", time: 60, label: "New Radial Mask", kind: .mask),
            TrailMark(id: "b", time: 63, label: "Paste Settings", kind: .paste),
            TrailMark(id: "c", time: 66, label: "Mark", kind: .mark),
            TrailMark(id: "d", time: 70, label: "Crop", kind: .crop)
        ]
        let placed = place(crowded, playhead: 66)
        XCTAssertEqual(placed.count, 4, "every landmark keeps its glyph")
        let labelled = placed.filter(\.showsLabel)
        XCTAssertGreaterThanOrEqual(labelled.count, 2)
        XCTAssertTrue(labelled.contains { $0.mark.kind == .mark }, "the user's own mark keeps its name")
        for a in labelled {
            for b in labelled where b.mark.id != a.mark.id && b.row == a.row {
                let gap = abs(a.x - b.x)
                let needed = (TrailTrack.labelWidth(a.mark.label) + TrailTrack.labelWidth(b.mark.label)) / 2
                XCTAssertGreaterThanOrEqual(gap, needed, "\(a.mark.label) collides with \(b.mark.label)")
            }
        }
    }

    func testFarApartLabelsStayOnTheFirstRow() {
        let spread = [
            TrailMark(id: "a", time: 0, label: "Opened", kind: .open),
            TrailMark(id: "b", time: 90, label: "Mark", kind: .mark)
        ]
        XCTAssertEqual(place(spread, playhead: 90).map(\.row), [0, 0])
    }

    func testOffscreenLandmarksAreNotDrawn() {
        let far = [TrailMark(id: "a", time: -9000, label: "Ancient", kind: .open),
                   TrailMark(id: "b", time: 9000, label: "Distant", kind: .mark)]
        XCTAssertTrue(place(far, playhead: 0).isEmpty)
    }

    func testLabelsFadeInAsTheyApproachAndOutAsTheyPass() {
        let atHead = TrailTrack.nearness(of: headX, to: headX)
        let nearby = TrailTrack.nearness(of: headX + 60, to: headX)
        let faraway = TrailTrack.nearness(of: headX + 200, to: headX)
        XCTAssertEqual(atHead, 1.0, accuracy: 0.001)
        XCTAssertLessThan(nearby, atHead)
        XCTAssertLessThan(faraway, nearby)
        XCTAssertEqual(faraway, 0.0, accuracy: 0.0001, "a landmark far from the playhead has no label at all")
        // Symmetric: coming and going look the same.
        XCTAssertEqual(TrailTrack.nearness(of: headX - 60, to: headX), nearby, accuracy: 0.0001)
    }
}


/// The feel of Rewind: exact steps at a crawl, smooth travel at speed, and a transport that
/// replays a session at a pace you set. None of these need a panel or a socket.
final class RewindTransportTests: XCTestCase {
    private var dir: URL!
    private var lightroom: FakeLightroom!
    private var engine: RewindEngine!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lightroom = FakeLightroom()
        engine = RewindEngine()
        engine.storeDirectory = dir
        engine.output = lightroom
        engine.knobParams = [(control: "Y_GAMMA", param: "Exposure")]
        engine.clickUnits = 40
        engine.acceleration = 0.5
        lightroom.values = ["Exposure": 0.5]
        engine.setActivePhoto("cat:1")
    }

    override func tearDown() {
        engine.endRewind(announce: false)
        engine.setActivePhoto(nil)          // writes what is pending, so nothing lands on a deleted folder
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func edit(_ value: Double, at seconds: TimeInterval, param: String = "Exposure") {
        lightroom.values[param] = value
        let branch = engine.trail!.activeBranch
        engine.record(param: param, value: value,
                      at: branch.clockOrigin.addingTimeInterval(seconds - branch.forkTime))
    }

    /// Ten separate edits, ten seconds apart.
    private func tenEdits() {
        for i in 1...10 { edit(0.5 + Double(i) * 0.03, at: Double(i) * 10.0) }
    }

    func testOneClickOfTheRingIsExactlyOneStep() {
        tenEdits()
        engine.beginRewind()
        let steps = engine.trail!.playback().stepTimes
        XCTAssertEqual(engine.state.playhead, steps.last ?? -1, accuracy: 0.0001)

        engine.scrub(units: -40, now: Date())
        XCTAssertEqual(engine.state.playhead, steps[steps.count - 2], accuracy: 0.0001)
        engine.scrub(units: -40, now: Date().addingTimeInterval(0.6))
        XCTAssertEqual(engine.state.playhead, steps[steps.count - 3], accuracy: 0.0001)
        // Forward again lands where it was: the same numbers, not something close to them.
        engine.scrub(units: 40, now: Date().addingTimeInterval(1.2))
        XCTAssertEqual(engine.state.playhead, steps[steps.count - 2], accuracy: 0.0001)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.5 + 9 * 0.03, accuracy: 0.0001,
                       "the photo is exactly the edit you stopped on")
    }

    func testASlowTurnNeverSkipsAStep() {
        tenEdits()
        engine.beginRewind()
        let steps = engine.trail!.playback().stepTimes
        // Ten small packets, a quarter second apart: a careful hand. 10 × 12 units = 3 clicks.
        var now = Date()
        for _ in 0..<10 {
            now = now.addingTimeInterval(0.25)
            engine.scrub(units: -12, now: now)
        }
        XCTAssertEqual(engine.state.playhead, steps[steps.count - 1 - 3], accuracy: 0.0001)
    }

    func testTurningBackTheOtherWayStartsAFreshClick() {
        tenEdits()
        engine.beginRewind()
        let steps = engine.trail!.playback().stepTimes
        var now = Date()
        now = now.addingTimeInterval(0.3); engine.scrub(units: -30, now: now)   // nearly a click back
        now = now.addingTimeInterval(0.3); engine.scrub(units: 30, now: now)    // and reverse
        XCTAssertEqual(engine.state.playhead, steps.last ?? -1, accuracy: 0.0001,
                       "wobbling the ring at a click's edge does not move the playhead")
    }

    func testTheRingStepsToWhatChangedAndSaysSo() {
        tenEdits()
        engine.beginRewind()
        engine.scrub(units: -40, now: Date())
        XCTAssertTrue(engine.state.caption.contains("Exposure"), engine.state.caption)
        XCTAssertEqual(engine.state.stepCount, engine.trail!.playback().stepTimes.count)
        XCTAssertEqual(engine.state.stepNumber, engine.state.stepCount - 1)
    }

    func testSlowIsAlwaysOneStepAndTravelGrowsSmoothlyWithSpeed() {
        for steps in [40, 640, 5_000, 40_000] {
            XCTAssertEqual(RewindEngine.jogMultiplier(rate: 0, stepCount: steps, acceleration: 0.5), 1)
            XCTAssertEqual(RewindEngine.jogMultiplier(rate: 10, stepCount: steps, acceleration: 1), 1,
                           "a deliberate turn is one step per click at any length")
            var previous = 1
            for rate in stride(from: 0.0, through: 120.0, by: 5.0) {
                let m = RewindEngine.jogMultiplier(rate: rate, stepCount: steps, acceleration: 0.5)
                XCTAssertGreaterThanOrEqual(m, previous, "faster never means slower")
                previous = m
            }
        }
        // A hard spin covers a long session in a couple of dozen clicks; a short one stays fine.
        let long = RewindEngine.jogMultiplier(rate: 90, stepCount: 40_000, acceleration: 0.5)
        XCTAssertGreaterThan(long, 400)
        XCTAssertLessThanOrEqual(long, 40_000 / 40 * 2)
        let short = RewindEngine.jogMultiplier(rate: 90, stepCount: 40, acceleration: 0.5)
        XCTAssertLessThanOrEqual(short, 2, "thirty seconds of editing does not need to be crossed at speed")
        // The dial changes the top, never the bottom.
        XCTAssertLessThan(RewindEngine.jogMultiplier(rate: 90, stepCount: 5_000, acceleration: 0),
                          RewindEngine.jogMultiplier(rate: 90, stepCount: 5_000, acceleration: 1))
    }

    func testPlayReplaysAtTheDialsSpeedAndPauseHoldsThePhoto() {
        // A burst of editing, then a real pause, then another burst.
        for i in 0...20 { edit(0.5 + Double(i) * 0.01, at: 2.0 + Double(i) * 0.05) }
        engine.beginRewind()
        engine.scrub(units: -40_000, now: Date())                       // all the way to the start
        XCTAssertEqual(engine.state.playhead, engine.trail!.playback().start, accuracy: 0.0001)

        engine.play(forward: true)
        XCTAssertTrue(engine.isPlaying)
        engine.advancePlayback(by: 1.0)                                 // 1× : a second passes
        XCTAssertEqual(engine.state.playhead, 1.0, accuracy: 0.001)

        // Halve it: half the time passes in the same second.
        engine.adjustSpeed(units: -154, fine: false)                    // exp(-154 × 0.0045) ≈ 0.5
        XCTAssertEqual(engine.state.rate, 0.5, accuracy: 0.02)
        let before = engine.state.playhead
        engine.advancePlayback(by: 1.0)
        XCTAssertEqual(engine.state.playhead - before, engine.state.rate, accuracy: 0.05)

        engine.pausePlayback()
        XCTAssertFalse(engine.isPlaying)
        let held = engine.state.playhead
        let photo = lightroom.values["Exposure"]
        engine.advancePlayback(by: 5.0)
        XCTAssertEqual(engine.state.playhead, held, accuracy: 0.0001, "paused means paused")
        XCTAssertEqual(lightroom.values["Exposure"], photo)
    }

    func testAQuietStretchPlaysThroughInAFractionOfItsLength() {
        edit(0.6, at: 1.0)
        edit(0.9, at: 601.0)                                            // ten minutes later
        engine.beginRewind()
        engine.scrub(units: -40_000, now: Date())
        // Stand just after the first edit and play: the ten minutes must not take ten minutes.
        engine.scrub(units: 40, now: Date().addingTimeInterval(1))      // one click: onto the first edit
        let start = engine.state.playhead
        XCTAssertEqual(start, 1.0, accuracy: 0.0001)
        engine.play(forward: true)
        engine.advancePlayback(by: 0.6)
        XCTAssertGreaterThan(engine.state.playhead - start, 300, "the quiet is compressed")
        XCTAssertLessThanOrEqual(engine.state.playhead, 601.0 + 0.0001)
    }

    func testPlayStopsAtNowAndPressingTheSameDirectionPauses() {
        edit(0.6, at: 1.0)
        edit(0.7, at: 2.0)
        engine.beginRewind()
        engine.scrub(units: -40_000, now: Date())
        engine.play(forward: true)
        engine.play(forward: true)                                      // same key again
        XCTAssertFalse(engine.isPlaying, "one key starts it and stops it")

        engine.play(forward: true)
        engine.advancePlayback(by: 30)                                  // far more than there is
        XCTAssertFalse(engine.isPlaying, "it stops on its own at now")
        XCTAssertTrue(engine.state.isAtTip)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.7, accuracy: 0.0001)

        // At now there is nowhere further forward to play.
        engine.play(forward: true)
        XCTAssertFalse(engine.isPlaying)
    }

    func testPlayBackwardWalksTheEditsBackOut() {
        for i in 1...5 { edit(0.5 + Double(i) * 0.05, at: Double(i)) }
        engine.beginRewind()
        engine.play(forward: false)
        XCTAssertTrue(engine.state.isReverse)
        engine.advancePlayback(by: 2.0)
        XCTAssertLessThan(engine.state.playhead, engine.state.tip)
        XCTAssertLessThan(lightroom.values["Exposure"] ?? 1, 0.5 + 5 * 0.05)
    }

    func testTakingHoldOfTheRingStopsPlayback() {
        tenEdits()
        engine.beginRewind()
        engine.scrub(units: -40_000, now: Date())
        engine.play(forward: true)
        XCTAssertTrue(engine.isPlaying)
        engine.scrub(units: 40, now: Date().addingTimeInterval(1))
        XCTAssertFalse(engine.isPlaying, "your hand on the ring wins over the replay")
    }

    func testLettingGoOfUndoStopsPlayback() {
        tenEdits()
        engine.beginRewind()
        engine.scrub(units: -40_000, now: Date())
        engine.play(forward: true)
        engine.endRewind()
        XCTAssertFalse(engine.isPlaying)
        let held = engine.state.playhead
        engine.advancePlayback(by: 5)
        XCTAssertEqual(engine.state.playhead, held, accuracy: 0.0001)
    }

    func testTheSpeedDialCatchesAtNormalSpeedAndLeavesWithAFirmerTurn() {
        tenEdits()
        engine.beginRewind()
        engine.adjustSpeed(units: -300, fine: false)
        XCTAssertLessThan(engine.state.rate, 1)
        engine.adjustSpeed(units: 600, fine: false)                     // sweeps straight through 1×
        XCTAssertEqual(engine.state.rate, 1.0, accuracy: 0.0001, "it lands on 1× instead of overshooting")
        engine.adjustSpeed(units: 10, fine: false)                      // a nudge is not enough to leave
        XCTAssertEqual(engine.state.rate, 1.0, accuracy: 0.0001)
        engine.adjustSpeed(units: 100, fine: false)
        XCTAssertGreaterThan(engine.state.rate, 1.2)
    }

    func testTheDialSpansSlowMotionToFastForwardAndStopsAtTheEnds() {
        tenEdits()
        engine.beginRewind()
        engine.adjustSpeed(units: -100_000, fine: false)
        XCTAssertEqual(engine.state.rate, RewindEngine.minSpeed, accuracy: 0.0001)
        engine.adjustSpeed(units: 100_000, fine: false)
        engine.adjustSpeed(units: 100_000, fine: false)
        XCTAssertEqual(engine.state.rate, RewindEngine.maxSpeed, accuracy: 0.0001)
        XCTAssertEqual(RewindState.rateText(1), "1×")
        XCTAssertEqual(RewindState.rateText(0.25), "0.25×")
        XCTAssertEqual(RewindState.rateText(12.4), "12×")
    }

    func testTheFineDialMovesSlowerThanTheCoarseOne() {
        tenEdits()
        engine.beginRewind()
        engine.adjustSpeed(units: -150, fine: true)
        let fine = engine.state.rate
        engine.adjustSpeed(units: 150, fine: true)                      // back to 1×
        engine.adjustSpeed(units: -150, fine: false)
        let coarse = engine.state.rate
        XCTAssertGreaterThan(fine, coarse, "the same turn moves the fine dial less")
    }
}


/// Tangents: how you get onto one, how you tell, and how you move between them.
final class RewindTangentsTests: XCTestCase {
    private var dir: URL!
    private var lightroom: FakeLightroom!
    private var engine: RewindEngine!
    private var events: [RewindEngine.TangentEvent] = []
    private var subscription: Any?

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        lightroom = FakeLightroom()
        engine = RewindEngine()
        engine.storeDirectory = dir
        engine.output = lightroom
        engine.knobParams = [(control: "Y_GAMMA", param: "Exposure")]
        lightroom.values = ["Exposure": 0.5]
        engine.setActivePhoto("cat:1")
        events = []
        subscription = engine.tangentEvents.sink { [unowned self] in self.events.append($0) }
    }

    override func tearDown() {
        engine.endRewind(announce: false)
        engine.setActivePhoto(nil)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func edit(_ value: Double, at seconds: TimeInterval) {
        lightroom.values["Exposure"] = value
        let branch = engine.trail!.activeBranch
        engine.record(param: "Exposure", value: value,
                      at: branch.clockOrigin.addingTimeInterval(seconds - branch.forkTime))
    }

    /// Original: 0.6 at 10 s, 0.9 at 30 s. Then rewind to 15 s and edit: Tangent 2 starts there.
    private func makeSecondTangent() {
        edit(0.6, at: 10)
        edit(0.9, at: 30)
        engine.beginRewind()
        engine.scrub(units: -40, now: Date())                            // one step back: onto 10 s
        engine.endRewind()
        edit(0.2, at: 12)                                                // an edit from the past
    }

    func testThereIsNoBadgeOnTheOriginal() {
        edit(0.6, at: 10)
        XCTAssertNil(engine.tangentInfo)
    }

    func testEditingFromThePastStartsATakeSaysSoAndKeepsTheOtherLine() {
        makeSecondTangent()
        XCTAssertEqual(engine.trail?.branches.count, 2)
        XCTAssertEqual(engine.tangentInfo, TangentInfo(name: "Tangent 2", colorIndex: 1, number: 2, total: 2))
        XCTAssertEqual(events.count, 1)
        if case .started(let name, let parent, let at)? = events.first {
            XCTAssertEqual(name, "Tangent 2")
            XCTAssertEqual(parent, "Original")
            XCTAssertEqual(at, 10, accuracy: 0.05)
        } else {
            XCTFail("expected a started event, got \(events)")
        }
        // The original still has all of it.
        let original = engine.trail!.branches[0].id
        XCTAssertEqual(engine.trail!.playback(on: original).value(of: "Exposure", at: 31) ?? 0, 0.9, accuracy: 0.0001)
    }

    func testHoppingKeepsYourPlaceAndTheAB() {
        makeSecondTangent()
        engine.beginRewind()
        XCTAssertEqual(engine.state.tangentNumber, 2)
        XCTAssertEqual(engine.state.tangents.map(\.name), ["Original", "Tangent 2"])
        XCTAssertEqual(engine.state.tangents.filter(\.isActive).map(\.name), ["Tangent 2"])
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.2, accuracy: 0.0001, "Tangent 2 finished at 0.2")

        // At the end of Tangent 2, hopping lands at the end of the original: compare the results.
        engine.hopTangent(forward: true)
        XCTAssertEqual(engine.state.tangentNumber, 1)
        XCTAssertEqual(engine.tangentInfo, nil)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.9, accuracy: 0.0001, "the original finished at 0.9")
        XCTAssertTrue(engine.state.isAtTip)

        // And back. It wraps.
        engine.hopTangent(forward: true)
        XCTAssertEqual(engine.state.tangentNumber, 2)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.2, accuracy: 0.0001)
    }

    func testHoppingFromTheMiddleStaysAtTheSameMoment() {
        makeSecondTangent()
        engine.beginRewind()
        engine.scrub(units: -40, now: Date())                            // off the tip, into Tangent 2's line
        let here = engine.state.playhead
        XCTAssertFalse(engine.state.isAtTip)
        engine.hopTangent(forward: false)
        XCTAssertEqual(engine.state.playhead, min(here, engine.state.tip), accuracy: 0.0001)
        XCTAssertFalse(engine.state.isAtTip)
    }

    func testHoppingThenEditingContinuesThatTake() {
        makeSecondTangent()
        engine.beginRewind()
        engine.hopTangent(forward: true)                                    // onto the original, at its tip
        engine.endRewind()
        // The original is the tangent being edited again, so this lands on it, not on Tangent 2.
        XCTAssertEqual(engine.trail?.activeBranch.name, "Original")
        let before = engine.trail!.activeBranch.events.count
        edit(0.95, at: 36)                                               // well after Lightroom has settled
        XCTAssertEqual(engine.trail?.branches.count, 2, "still no new tangent: we were at its tip")
        XCTAssertEqual(engine.trail!.activeBranch.events.count, before + 1)
    }

    func testOneTakeHasNothingToHopTo() {
        edit(0.6, at: 10)
        engine.beginRewind()
        engine.hopTangent(forward: true)
        XCTAssertEqual(engine.state.tangentCount, 1)
        XCTAssertTrue(engine.state.caption.contains("No other tangents"), engine.state.caption)
    }

    func testEveryTakeGetsALaneWithItsOwnActivity() {
        makeSecondTangent()
        engine.beginRewind()
        let lanes = engine.state.tangents
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(lanes[1].parentID, lanes[0].id)
        XCTAssertGreaterThan(lanes[0].activity.max() ?? 0, 0)
        XCTAssertEqual(lanes[0].activity.count, RewindEngine.laneBuckets)
        XCTAssertEqual(lanes.map(\.colorIndex), [0, 1])
        XCTAssertGreaterThanOrEqual(engine.state.spanEnd, lanes.map(\.tip).max() ?? 0)
        XCTAssertFalse(engine.state.steps.isEmpty, "the tape has ticks to draw")
    }

    func testTheTapeZoomsToHowDenselyYouWereEditing() {
        // Frantic: a step every tenth of a second. Slow: one every five seconds.
        var frantic = EditTrail(photoID: "a")
        for i in 0..<200 { frantic.record(param: "Exposure", value: 0.3 + Double(i) * 0.001, at: Double(i) * 0.1) }
        var slow = EditTrail(photoID: "b")
        for i in 0..<200 { slow.record(param: "Exposure", value: 0.3 + Double(i) * 0.001, at: Double(i) * 5.0) }
        let fast = RewindEngine.tapeWindow(for: frantic.playback(), at: 10)
        let calm = RewindEngine.tapeWindow(for: slow.playback(), at: 500)
        XCTAssertLessThan(fast, calm)
        XCTAssertGreaterThanOrEqual(fast, 3)
        XCTAssertLessThanOrEqual(calm, 900)
    }
}


/// The springs behind the readout. They have to arrive quickly and never overshoot: that is what
/// makes the tape feel like it has weight instead of wobbling.
final class RewindMotionTests: XCTestCase {
    private func state(playhead: Double, step: Int, window: Double = 30) -> RewindState {
        RewindState(origin: 0, tip: 200, playhead: playhead, window: window, stepNumber: step, stepCount: 100)
    }

    /// Runs the springs at a display rate for a while.
    private func run(_ motion: RewindMotion, _ state: RewindState, seconds: Double, hz: Double = 120,
                     from start: Double = 1000) -> [Double] {
        var positions: [Double] = []
        var t = start
        for _ in 0..<Int(seconds * hz) {
            motion.advance(state, now: t)
            positions.append(motion.position)
            t += 1 / hz
        }
        return positions
    }

    func testThePlayheadArrivesQuicklyAndNeverOvershoots() {
        let motion = RewindMotion()
        motion.advance(state(playhead: 100, step: 10), now: 1000)         // starts settled at 100
        let path = run(motion, state(playhead: 108, step: 11), seconds: 0.6, from: 1000.01)
        XCTAssertLessThanOrEqual(path.max() ?? 0, 108.0001, "critically damped: it never goes past")
        XCTAssertGreaterThan(path[Int(0.25 * 120)], 108 - 8 * 0.02, "within about a quarter of a second it is nearly there")
        XCTAssertEqual(path.last ?? 0, 108, accuracy: 0.001)
        // Monotonic: no wobble on the way.
        for pair in zip(path, path.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1, pair.0 - 1e-9) }
    }

    func testTheSameSpringWorksAtAnyFrameRate() {
        func settle(hz: Double) -> Double {
            let motion = RewindMotion()
            motion.advance(state(playhead: 50, step: 1), now: 1000)
            return run(motion, state(playhead: 56, step: 2), seconds: 0.2, hz: hz, from: 1000.01).last ?? 0
        }
        // 60, 120 and 240 Hz displays all agree, so a ProMotion screen is smoother, not different.
        XCTAssertEqual(settle(hz: 60), settle(hz: 120), accuracy: 0.08)
        XCTAssertEqual(settle(hz: 120), settle(hz: 240), accuracy: 0.08)
    }

    func testAJumpAcrossTheWholeSessionGlidesInFromTheEdgeOfTheTape() {
        let motion = RewindMotion()
        motion.advance(state(playhead: 5, step: 1, window: 30), now: 1000)
        motion.advance(state(playhead: 5_000, step: 2, window: 30), now: 1000.01)
        XCTAssertGreaterThan(motion.position, 5_000 - 30, "it never crosses empty tape: the last stretch is on screen")
    }

    func testEachNewStepBlipsAndItDecays() {
        let motion = RewindMotion()
        motion.advance(state(playhead: 10, step: 4), now: 1000)
        XCTAssertEqual(motion.pulse, 0, accuracy: 0.0001, "nothing to blip about on the first frame")
        motion.advance(state(playhead: 10.5, step: 5), now: 1000.01)
        XCTAssertGreaterThan(motion.pulse, 0.5)
        _ = run(motion, state(playhead: 10.5, step: 5), seconds: 1.0, from: 1000.02)
        XCTAssertLessThan(motion.pulse, 0.01, "and it settles, so a held playhead is still")
    }

    func testTheTapeReZoomsSmoothly() {
        let motion = RewindMotion()
        motion.advance(state(playhead: 10, step: 1, window: 10), now: 1000)
        let w = (0..<60).map { i -> Double in
            motion.advance(state(playhead: 10, step: 1, window: 40), now: 1000.01 + Double(i) / 120)
            return motion.window
        }
        XCTAssertGreaterThanOrEqual(w.first ?? 0, 10)
        XCTAssertLessThanOrEqual(w.max() ?? 0, 40.0001, "no overshoot when it zooms out")
        for pair in zip(w, w.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1, pair.0 - 1e-9) }
    }

    func testTheActiveLaneEasesOnRatherThanSnapping() {
        let motion = RewindMotion()
        let a = TangentLane(id: "a", name: "Original", colorIndex: 0, start: 0, tip: 10, parentID: nil,
                         isActive: true, isOnPath: true, activity: [])
        let b = TangentLane(id: "b", name: "Tangent 2", colorIndex: 1, start: 4, tip: 10, parentID: "a",
                         isActive: false, isOnPath: false, activity: [])
        var s = state(playhead: 5, step: 1)
        s.tangents = [a, b]
        motion.advance(s, now: 1000)
        XCTAssertEqual(motion.glow["a"] ?? 0, 1, accuracy: 0.001)
        // Hop: b becomes active.
        s.tangents = [TangentLane(id: "a", name: "Original", colorIndex: 0, start: 0, tip: 10, parentID: nil, isActive: false, isOnPath: false, activity: []),
                   TangentLane(id: "b", name: "Tangent 2", colorIndex: 1, start: 4, tip: 10, parentID: "a", isActive: true, isOnPath: true, activity: [])]
        motion.advance(s, now: 1000.008)
        let early = motion.glow["b"] ?? 0
        XCTAssertGreaterThan(early, 0)
        XCTAssertLessThan(early, 0.5, "the lit lane fades over rather than jumping")
        _ = run(motion, s, seconds: 0.6, from: 1000.02)
        XCTAssertGreaterThan(motion.glow["b"] ?? 0, 0.97)
        XCTAssertLessThan(motion.glow["a"] ?? 1, 0.03)
    }
}


/// The intro's Rewind+ slide plays the real readout from a scripted session. It has to make sense
/// at every moment, or the slide shows something the feature never does.
final class IntroRewindDemoTests: XCTestCase {
    private let times = stride(from: 0.0, through: IntroRewindDemo.length, by: 0.05).map { $0 }

    func testNothingShowsUntilUndoIsHeld() {
        let before = IntroRewindDemo.frame(at: 0.6)
        XCTAssertEqual(before.readoutOpacity, 0)
        XCTAssertTrue(before.keys.isEmpty)
        let held = IntroRewindDemo.frame(at: 2.0)
        XCTAssertEqual(held.readoutOpacity, 1)
        XCTAssertTrue(held.keys.contains("button_undo"), "the key you hold is lit")
    }

    func testEveryMomentIsCoherent() {
        for t in times {
            let f = IntroRewindDemo.frame(at: t)
            let s = f.state
            XCTAssertGreaterThanOrEqual(s.playhead, 0, "t=\(t)")
            XCTAssertLessThanOrEqual(s.playhead, s.tip + 0.0001, "the playhead is never past the end of its line (t=\(t))")
            XCTAssertLessThanOrEqual(s.tip, IntroRewindDemo.spanEnd, "t=\(t)")
            XCTAssertLessThanOrEqual(s.stepNumber, s.stepCount, "t=\(t)")
            XCTAssertGreaterThanOrEqual(s.stepNumber, 1, "t=\(t)")
            XCTAssertEqual(s.tangents.count, s.tangentCount, "t=\(t)")
            XCTAssertEqual(s.tangents.filter(\.isActive).count, 1, "exactly one lane is lit (t=\(t))")
            XCTAssertEqual(s.tangents.first { $0.isActive }?.colorIndex, s.tangentColorIndex, "t=\(t)")
            XCTAssertEqual(s.knobs.count, 12, "t=\(t)")
            XCTAssertFalse(f.step.isEmpty)
            for lane in s.tangents { XCTAssertEqual(lane.activity.count, RewindEngine.laneBuckets) }
        }
    }

    func testTheSlideTellsTheStoryInOrder() {
        // One click of the ring is one step; then travelling; then play; a tangent; then hops.
        XCTAssertTrue(IntroRewindDemo.frame(at: 3.0).step.hasPrefix("1"))
        XCTAssertTrue(IntroRewindDemo.frame(at: 3.0).rings.contains(1), "the centre ring glows while it is turned")
        XCTAssertTrue(IntroRewindDemo.frame(at: 9.0).step.hasPrefix("2"))
        XCTAssertTrue(IntroRewindDemo.frame(at: 9.0).state.isPlaying)
        XCTAssertFalse(IntroRewindDemo.frame(at: 13.0).state.isPlaying, "Stop pauses it")
        XCTAssertTrue(IntroRewindDemo.frame(at: 15.0).step.hasPrefix("3"))
        XCTAssertTrue(IntroRewindDemo.frame(at: 20.5).step.hasPrefix("4"))
        XCTAssertEqual(IntroRewindDemo.frame(at: 5.0).state.tangentCount, 1)
        XCTAssertEqual(IntroRewindDemo.frame(at: 15.0).state.tangentCount, 2)
    }

    func testPlaybackSlowsDownWhenTheDialIsTurned() {
        let early = IntroRewindDemo.frame(at: 8.5).state.rate
        let late = IntroRewindDemo.frame(at: 11.5).state.rate
        XCTAssertEqual(early, 1, accuracy: 0.0001, "starts at normal speed")
        XCTAssertEqual(late, 0.25, accuracy: 0.0001, "and ends in slow motion")
        // Playback only moves forward, and never past where it was stopped.
        var previous = IntroRewindDemo.frame(at: 7.6).state.playhead
        for t in stride(from: 7.7, through: 12.5, by: 0.1) {
            let now = IntroRewindDemo.frame(at: t).state.playhead
            XCTAssertGreaterThanOrEqual(now, previous - 1e-9, "t=\(t)")
            previous = now
        }
    }

    func testTheTangentLeavesTheOriginalWhereItWasStopped() {
        let stopped = IntroRewindDemo.frame(at: 13.0).state.playhead
        let fork = IntroRewindDemo.frame(at: 16.0).state.tangents[1].start
        XCTAssertEqual(fork, stopped, accuracy: 0.0001, "a tangent starts at the moment you stopped on")
        XCTAssertLessThan(fork, IntroRewindDemo.tip, "so the original keeps a future the tangent does not have")
    }

    func testHoppingAlternatesBetweenTheTwoLines() {
        var active: [String] = []
        for t in stride(from: 19.0, through: 25.0, by: 0.1) {
            let name = IntroRewindDemo.frame(at: t).state.tangents.first { $0.isActive }?.name ?? "?"
            if active.last != name { active.append(name) }
        }
        XCTAssertEqual(active, ["Tangent 2", "Original", "Tangent 2", "Original"])
    }

    func testTheSlideFitsTheShow() {
        // The show is a fixed list of scenes; the new one must not push the finale off the end.
        XCTAssertEqual(IntroRewindDemo.length, 26)
        XCTAssertGreaterThan(IntroRewindDemo.frame(at: IntroRewindDemo.length).state.stepCount, 100)
    }
}
