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

        let branch = trail.fork(at: 10.0, name: "Take 2")
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
        _ = trail.fork(at: 2.0, name: "Take 2")
        trail.record(param: "Exposure", value: 0.4, at: 3.0)
        let second = trail.activeBranchID
        _ = trail.fork(at: 3.5, name: "Take 3")
        trail.record(param: "Exposure", value: 0.6, at: 4.0)

        XCTAssertEqual(trail.branches.count, 3)
        XCTAssertEqual(trail.playback(on: first).value(of: "Exposure", at: 10) ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(trail.playback(on: second).value(of: "Exposure", at: 10) ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(trail.playback().value(of: "Exposure", at: 10) ?? 0, 0.6, accuracy: 0.0001)
        // The line the playhead is on knows where the others left it.
        XCTAssertEqual(trail.forks(of: second).map(\.name), ["Take 3"])
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
        _ = trail.fork(at: 1.2, name: "Take 2")
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
        XCTAssertEqual(engine.state.strength, 1.0, accuracy: 0.0001)
    }

    func testStrengthTakesThePhotoPartOfTheWayBack() {
        start()
        edit("Exposure", 1.0, secondsFromStart: 4.0)
        engine.beginRewind()
        engine.scrub(units: -600, now: Date())
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.5, accuracy: 0.05)

        // Half strength is half way between now and the scrub point.
        engine.adjustStrength(units: -125)
        XCTAssertEqual(engine.state.strength, 0.5, accuracy: 0.02)
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 0.75, accuracy: 0.05)

        engine.adjustStrength(units: -1000)
        XCTAssertEqual(engine.state.strength, 0.0, accuracy: 0.0001, "strength stops at 0")
        XCTAssertEqual(lightroom.values["Exposure"] ?? 0, 1.0, accuracy: 0.0001)
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
        XCTAssertEqual(engine.state.branchName, "Take 2")
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
