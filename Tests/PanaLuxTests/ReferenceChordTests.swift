import XCTest
@testable import PanaLux

final class ReferenceChordTests: XCTestCase {
    func testBothOrdersSuppressTapsAndDismissOnEitherRelease() {
        for pair in [["PREV_STILL", "NEXT_STILL"], ["NEXT_STILL", "PREV_STILL"]] {
            for release in pair {
                var chord = ReferenceChord()
                XCTAssertTrue(chord.receive(pair[0], down: true).isEmpty)
                XCTAssertTrue(chord.receive(pair[1], down: true).isEmpty)
                XCTAssertTrue(chord.visible)
                XCTAssertTrue(chord.receive(release, down: false).isEmpty)
                XCTAssertFalse(chord.visible)
                XCTAssertTrue(chord.receive(pair.first { $0 != release }!, down: false).isEmpty)
                XCTAssertTrue(chord.pressed.isEmpty)
            }
        }
    }

    func testSingleTapAndHoldRetainTheirEvents() {
        var chord = ReferenceChord()
        _ = chord.receive("PREV_STILL", down: true)
        XCTAssertEqual(chord.receive("PREV_STILL", down: false), [.init(name: "PREV_STILL", down: true), .init(name: "PREV_STILL", down: false)])
        _ = chord.receive("NEXT_STILL", down: true)
        XCTAssertEqual(chord.flush(), [.init(name: "NEXT_STILL", down: true)])
        XCTAssertEqual(chord.receive("NEXT_STILL", down: false), [.init(name: "NEXT_STILL", down: false)])
    }

    func testOtherCombinationsKeepEventOrderAndLatePartnerDoesNotPeek() {
        var chord = ReferenceChord()
        _ = chord.receive("PREV_STILL", down: true)
        XCTAssertEqual(chord.receive("PRESS_LUM_MIX", down: true), [.init(name: "PREV_STILL", down: true), .init(name: "PRESS_LUM_MIX", down: true)])
        XCTAssertEqual(chord.receive("NEXT_STILL", down: true), [.init(name: "NEXT_STILL", down: true)])
        XCTAssertFalse(chord.visible)
        chord.reset()
        XCTAssertTrue(chord.pressed.isEmpty)
    }

    func testResetDismissesAndRepeatedDownDoesNotLeak() {
        var chord = ReferenceChord()
        _ = chord.receive("PREV_STILL", down: true)
        _ = chord.receive("NEXT_STILL", down: true)
        XCTAssertTrue(chord.receive("NEXT_STILL", down: true).isEmpty)
        chord.reset()
        XCTAssertFalse(chord.visible)
        XCTAssertNil(chord.pending)
    }

    @MainActor
    func testHardwareReportsShowAndDisconnectDismissesWithoutTap() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        let original = engine.profile
        defer { engine.profile = original; engine.returnToBase(announce: false) }
        engine.returnToBase(announce: false)
        // A leaked tap would toggle a mode, making this test sensitive to actual engine output.
        engine.profile.buttons["PREV_STILL"] = ButtonBinding(layer: "OFFSET")
        engine.profile.buttons["NEXT_STILL"] = ButtonBinding(layer: "MASK")
        let motions = ["PREV_STILL", "NEXT_STILL"].map { PanelMotion(reportId: 2, slot: HardwareMap.shared.buttonBit(forControl: $0)!, kind: .keyDown) }
        engine.panelDidReceiveMotion(motions)
        XCTAssertTrue(engine.referencePeekVisible)
        XCTAssertTrue(engine.activeLayers.isEmpty)
        engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: HardwareMap.shared.buttonBit(forControl: "PREV_STILL")!, kind: .keyUp)])
        XCTAssertFalse(engine.referencePeekVisible)
        XCTAssertTrue(engine.activeLayers.isEmpty)
        engine.panelDidDisconnect()
        XCTAssertFalse(engine.referencePeekVisible)
    }

    @MainActor
    func testReferencesIncludeCustomLayersBanksSliderBallsAndEscapedLabels() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        let original = engine.profile
        defer { engine.profile = original; engine.returnToBase(announce: false) }
        engine.returnToBase(announce: false)
        engine.profile.balls["TB_LIFT"] = .slider("Exposure")
        engine.profile.layers["MIXER"]?.title = "Custom <Mixer>"
        engine.profile.layers["MIXER"]?.buttons?["PRESS_CONTRAST"] = ButtonBinding(action: "Preset_2")
        engine.activeLayers = ["MIXER"]
        let snapshot = PanelReference.current(engine)
        XCTAssertTrue(snapshot.section.contains("Custom &lt;Mixer&gt;"))
        XCTAssertTrue(snapshot.section.contains(CommandDatabase.shared.label(for: "Exposure")))
        XCTAssertEqual(snapshot.profile.buttons["PRESS_CONTRAST"]?.action, "Preset_2")
        let overview = LayerReference.html(for: engine)
        for bank in ["HUE", "SAT", "LUM"] { XCTAssertTrue(overview.contains(bank)) }
        for name in engine.profile.layers.keys { XCTAssertTrue(overview.contains(PanelReference.escape(engine.layerTitle(name)))) }
        XCTAssertFalse(overview.contains("Custom <Mixer>"))
    }
}
