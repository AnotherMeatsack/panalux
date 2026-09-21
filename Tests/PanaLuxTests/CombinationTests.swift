import XCTest
import SwiftUI
@testable import PanaLux

final class CombinationTests: XCTestCase {
    private let preset = ButtonCombination(held: ["PREV_STILL"], trigger: "PRESS_LUM_MIX", binding: ButtonBinding(action: "Preset_1"))

    func testModifierTapIsDeferredThenSuppressedAfterPreset() {
        var input = CombinationInput()
        guard case .deferTap = input.receive("PREV_STILL", down: true, combinations: [preset]) else { return XCTFail() }
        guard case .fire(let fired) = input.receive("PRESS_LUM_MIX", down: true, combinations: [preset]) else { return XCTFail() }
        XCTAssertEqual(fired.binding.action, "Preset_1")
        guard case .suppress = input.receive("PREV_STILL", down: false, combinations: [preset]) else { return XCTFail("No bracket mark on release") }
        guard case .suppress = input.receive("PRESS_LUM_MIX", down: false, combinations: [preset]) else { return XCTFail("No reset on release") }
    }

    func testRapidPressAndReleaseSurviveLEDWindow() {
        let decoder = PanelDecoder()
        let start = Date()
        var until = start.addingTimeInterval(0.08)
        let empty = Data(repeating: 0, count: 8)
        XCTAssertFalse(PanelManager.shouldSuppressButtonReport(empty, until: &until, now: start))
        for _ in 0..<3 {
            var down = Data(repeating: 0, count: 8)
            down[1] = 2 // Saturation push, bit 9
            XCTAssertFalse(PanelManager.shouldSuppressButtonReport(down, until: &until, now: start))
            XCTAssertEqual(decoder.decode(reportId: 2, data: down).map(\.kind), [.keyDown])
            XCTAssertTrue(decoder.hasHeldButtons)
            XCTAssertFalse(PanelManager.shouldSuppressButtonReport(empty, until: &until, now: start.addingTimeInterval(0.01)))
            XCTAssertEqual(decoder.decode(reportId: 2, data: empty).map(\.kind), [.keyUp])
            XCTAssertFalse(decoder.hasHeldButtons)
            until = start.addingTimeInterval(0.08)
        }
    }

    func testUnusedModifierKeepsTap() {
        var input = CombinationInput()
        _ = input.receive("PREV_STILL", down: true, combinations: [preset])
        guard case .tap = input.receive("PREV_STILL", down: false, combinations: [preset]) else { return XCTFail() }
    }

    func testSpecificChordWinsAndCanRepeatWithoutReleasingModifier() {
        var input = CombinationInput()
        let specific = ButtonCombination(held: ["PREV_STILL", "USER"], trigger: preset.trigger, binding: ButtonBinding(action: "Preset_2"))
        let entries = [preset, specific]
        _ = input.receive("USER", down: true, combinations: entries)
        _ = input.receive("PREV_STILL", down: true, combinations: entries)
        for _ in 0..<2 {
            guard case .fire(let result) = input.receive(preset.trigger, down: true, combinations: entries) else { return XCTFail() }
            XCTAssertEqual(result.binding.action, "Preset_2")
            _ = input.receive(preset.trigger, down: false, combinations: entries)
        }
    }

    func testRepeatDownDoesNotRefireAndDisconnectClearsState() {
        var input = CombinationInput()
        _ = input.receive("PREV_STILL", down: true, combinations: [preset])
        _ = input.receive(preset.trigger, down: true, combinations: [preset])
        guard case .suppress = input.receive(preset.trigger, down: true, combinations: [preset]) else { return XCTFail() }
        input.reset()
        guard case .normal = input.receive(preset.trigger, down: true, combinations: [preset]) else { return XCTFail() }
    }

    func testOlderMapsAndExplicitEmptyCombinationsRoundtrip() throws {
        var profile = Profile.loadDefault()
        XCTAssertNil(profile.combinations)
        profile.combinations = []
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)).combinations, [])
        profile.combinations = [preset]
        profile.buttons["PRESS_CONTRAST"] = ButtonBinding(action: "Preset_2")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)), profile)
        XCTAssertTrue(MapReadme.lines(for: profile).contains { $0.contains(preset.title) })
    }

    func testAllKnobDefaultsHaveRealResetsAndHardwarePresses() {
        let profile = Profile.loadDefault()
        for (bit, knob) in PanelLayout.knobs.enumerated() {
            XCTAssertEqual(HardwareMap.shared.controlName(forButtonBit: bit), "PRESS_" + knob)
            XCTAssertNotNil(CommandDatabase.shared.commands["Reset" + profile.knobs[knob]!.param])
            XCTAssertEqual(PanelControlMapping.toSvgId("PRESS_" + knob), PanelControlMapping.toSvgId(knob))
        }
    }

    func testWheelPartsNeverResetOtherComponentAndSliderBallsResetOnce() {
        let ball = BallBinding(hue: "Hue", sat: "Sat")
        let known: Set<String> = ["ResetHue", "ResetSat", "ResetLum"]
        XCTAssertEqual(WheelReset.commands(ball: ball, ringParam: nil, known: known), ["ResetHue", "ResetSat"])
        XCTAssertEqual(WheelReset.commands(ball: nil, ringParam: "Lum", known: known), ["ResetLum"])
        XCTAssertEqual(WheelReset.commands(ball: .slider("Lum"), ringParam: nil, known: known), ["ResetLum"])
        XCTAssertEqual(ButtonCombination.defaults.count, 6)
    }

    func testTypedShortcutsAreActionsAndWheelComponentsAreDiscoverable() {
        XCTAssertFalse(CommandDatabase.shared.catalogCommand(for: "key:cmd+shift+e").isParameter)
        XCTAssertNotNil(CommandDatabase.shared.commands["Preset_1"])
        XCTAssertFalse(CommandDatabase.shared.catalogCommand(for: "Preset_1").isParameter)
        for entry in ButtonCombination.defaults {
            XCTAssertFalse(CommandDatabase.shared.catalogCommand(for: entry.binding.action!).isParameter)
        }
    }
}

@MainActor
final class CombinationRenderingTests: XCTestCase {
    func testKnobResetRefreshesGraphicFromActualReadback() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        defer { engine.returnToBase(announce: false) }
        engine.beginKnobResetReadout(control: "CONTRAST", param: "Contrast")
        engine.lightroomParameterDidUpdate(name: "Contrast", value: 0.5)
        guard case .knob(_, _, let value, let text, _, let angle) = engine.currentDisplayMode else { return XCTFail() }
        XCTAssertEqual(value, 0.5)
        XCTAssertEqual(text, "0")
        XCTAssertEqual(angle, 0)
        engine.currentDisplayMode = .knob(name: PanelLayout.label(forControl: "CONTRAST"), param: "Contrast (Updating)", value: 0.8, displayValue: "…", isFine: false, angleDegrees: 0)
        engine.lightroomParameterDidUpdate(name: "Contrast", value: 0.5)
        guard case .knob(_, let refreshedLabel, let refreshedValue, let refreshedText, _, _) = engine.currentDisplayMode else { return XCTFail() }
        XCTAssertEqual(refreshedLabel, "Contrast")
        XCTAssertEqual(refreshedValue, 0.5)
        XCTAssertEqual(refreshedText, "0")
        engine.beginKnobResetReadout(control: "HUE", param: "Temperature")
        engine.lightroomParameterDidUpdate(name: "Temperature", value: 0.0625)
        guard case .knob(_, _, let temperature, let display, _, _) = engine.currentDisplayMode else { return XCTFail() }
        XCTAssertEqual(temperature, 0.0625)
        XCTAssertEqual(display, engine.formatValue(param: "Temperature", value: 0.0625))
        engine.currentDisplayMode = .action(name: "OTHER", label: "Another action", phase: .sent)
        engine.lightroomParameterDidUpdate(name: "Temperature", value: 0.2)
        XCTAssertEqual(engine.currentDisplayMode, .action(name: "OTHER", label: "Another action", phase: .sent))
    }

    func testCapturedGesturePersistsAndSinglePressKeepsHold() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        let before = engine.profile
        defer { engine.profile = before; engine.setProgrammingButtons(false); engine.returnToBase(announce: false) }
        engine.setProgrammingButtons(true)
        engine.combinationEditorActive = true
        func send(_ bit: Int, _ kind: MotionKind) {
            engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: bit, kind: kind)])
        }
        send(39, .keyDown)
        send(11, .keyDown)
        send(11, .keyUp)
        send(39, .keyUp)
        XCTAssertEqual(engine.combinationHeld, ["PREV_STILL"])
        XCTAssertEqual(engine.combinationTrigger, "PRESS_LUM_MIX")
        engine.saveCombination(command: "Preset_1")
        XCTAssertEqual(engine.effectiveCombinations.last?.binding.action, "Preset_1")
        XCTAssertTrue(engine.outputBlocked)
        engine.combinationHeld = []
        engine.combinationTrigger = "UNDO"
        let hold = engine.profile.buttons["UNDO"]?.hold_layer
        engine.saveCombination(command: "key:cmd+shift+e")
        XCTAssertEqual(engine.profile.buttons["UNDO"]?.hold_layer, hold)
        XCTAssertEqual(engine.profile.buttons["UNDO"]?.action, "key:cmd+shift+e")
    }

    func testShiftWheelResetsTakePriorityOverMixerBanks() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        let before = engine.profile
        defer { engine.profile = before; engine.isOutputPaused = false; engine.returnToBase(announce: false) }
        engine.setProgrammingButtons(false)
        engine.profile = Profile.loadDefault()
        engine.isOutputPaused = true
        for modifierBit in [24, 25] {
            for wheelBit in [33, 34, 35] {
                engine.returnToBase(announce: false)
                engine.activeLayers = modifierBit == 24 ? ["MIXER"] : ["MULTISELECT"]
                engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: modifierBit, kind: .keyDown)])
                engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: wheelBit, kind: .keyDown)])
                guard case .action(_, let label, _) = engine.currentDisplayMode else { return XCTFail("Combination must supersede bank selection") }
                XCTAssertTrue(label.contains(modifierBit == 24 ? "ball" : "ring"), label)
                engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: modifierBit, kind: .keyUp), PanelMotion(reportId: 2, slot: wheelBit, kind: .keyUp)])
            }
        }
    }

    func testUnorderedBitmapRunsCombinationBeforeNormalKnobReset() throws {
        guard AppRuntime.isRenderingStills else { throw XCTSkip("Safe render mode required") }
        let engine = StudioEngine.shared
        let before = engine.profile
        defer { engine.profile = before; engine.isOutputPaused = false; engine.returnToBase(announce: false) }
        engine.setProgrammingButtons(false)
        engine.returnToBase(announce: false)
        engine.isOutputPaused = true
        engine.profile.combinations = [ButtonCombination(held: ["PREV_STILL"], trigger: "PRESS_LUM_MIX", binding: ButtonBinding(action: "Preset_1"))]
        engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: 11, kind: .keyDown), PanelMotion(reportId: 2, slot: 39, kind: .keyDown)])
        guard case .action(_, let label, _) = engine.currentDisplayMode else { return XCTFail("Expected a blocked preset preview") }
        XCTAssertTrue(label.contains("Preset 1"), label)
        engine.panelDidReceiveMotion([PanelMotion(reportId: 2, slot: 39, kind: .keyUp), PanelMotion(reportId: 2, slot: 11, kind: .keyUp)])
        guard case .action(_, let after, _) = engine.currentDisplayMode else { return XCTFail() }
        XCTAssertEqual(after, label, "Neither the modifier tap nor knob reset should fire on release")
    }

    func testEditorAndReleaseNotesRender() throws {
        guard let folder = ProcessInfo.processInfo.environment["PANALUX_RENDER_DIR"] else { throw XCTSkip("Safe render directory required") }
        let engine = StudioEngine.shared
        engine.setProgrammingButtons(true)
        engine.combinationEditorActive = true
        engine.combinationHeld = ["PREV_STILL"]
        engine.combinationTrigger = "PRESS_LUM_MIX"
        defer { engine.setProgrammingButtons(false) }
        func save<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat) throws {
            let host = NSHostingView(rootView: view.frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        try save(CombinationEditorView().padding(18), name: "combination-editor", width: 380, height: 610)
        try save(MapInspectorView(selectedControl: .constant("LUM_MIX")), name: "full-inspector", width: 370, height: 750)
        engine.setProgrammingButtons(false)
        let sample = RewindEngine()
        let sampleDir = URL(fileURLWithPath: folder).appendingPathComponent("sample-trails")
        sample.storeDirectory = sampleDir
        sample.setActivePhoto("workspace-render-only")
        sample.record(param: "Exposure", value: 0.5)
        sample.record(param: "Contrast", value: 0.5)
        let original = sample.trail!.activeBranchID
        sample.startBranch(reason: "Warm highlights")
        let alternate = sample.trail!.activeBranchID
        sample.renameTangent(alternate, to: "Warm highlights")
        sample.record(param: "Exposure", value: 0.7, at: Date().addingTimeInterval(1))
        sample.record(param: "Contrast", value: 0.6, at: Date().addingTimeInterval(2))
        sample.selectTangent(original)
        sample.startBranch(reason: "Soft contrast")
        sample.renameTangent(sample.trail!.activeBranchID, to: "Soft contrast")
        sample.record(param: "Contrast", value: 0.4, at: Date().addingTimeInterval(3))
        try save(ExpandedRewindView(rewind: sample), name: "expanded-rewind", width: 930, height: 740)
        try save(ExpandedRewindView(rewind: sample, initialSourceID: alternate), name: "rewind-merge-inspector", width: 930, height: 740)
        sample.setActivePhoto(nil)
        try save(IntroShowView.still(scene: 7, at: 42), name: "rewind-tutorial-merge", width: 1160, height: 780)
        try save(ReleaseNotesView(), name: "release-notes", width: 680, height: 640)
    }
}
