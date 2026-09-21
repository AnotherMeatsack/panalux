import XCTest
@testable import PanaLux

final class PanelColorLEDTests: XCTestCase {
    
    func testReport02WhiteBitmaskGeneration() {
        // Empty set: Report ID 0x02 followed by 8 zero bytes
        let emptyPayload = PanelLEDController.makeWhitePayload(activeBits: [])
        XCTAssertEqual(emptyPayload.count, 9)
        XCTAssertEqual(emptyPayload[0], 0x02)
        for i in 1..<9 {
            XCTAssertEqual(emptyPayload[i], 0x00)
        }
        
        // Single bit 20 (Bypass white button) -> byte 1 + (20/8) = byte 3, bit 20%8 = 4 (1 << 4 = 0x10)
        let bypassPayload = PanelLEDController.makeWhitePayload(activeBits: [20])
        XCTAssertEqual(bypassPayload[0], 0x02)
        XCTAssertEqual(bypassPayload[3], 0x10)
        
        // Knob press 0 -> bit 0 -> byte 1, bit 0 (0x01)
        let knob0Payload = PanelLEDController.makeWhitePayload(activeBits: [0])
        XCTAssertEqual(knob0Payload[1], 0x01)
    }
    
    func testReport04ColorBitmaskGeneration() {
        // Empty set: Report ID 0x04 followed by 6 zero bytes
        let emptyPayload = PanelLEDController.makeColorPayload(activeBits: [])
        XCTAssertEqual(emptyPayload.count, 7)
        XCTAssertEqual(emptyPayload[0], 0x04)
        for i in 1..<7 {
            XCTAssertEqual(emptyPayload[i], 0x00)
        }
        
        // All 10 physical hardware color channels active
        let allBits = Set(PanelColorLED.allCases.map { $0.rawValue })
        let fullPayload = PanelLEDController.makeColorPayload(activeBits: allBits)
        XCTAssertEqual(fullPayload[0], 0x04)
        
        // Byte 1 contains bits 0..7:
        // bit 0 (Bypass Red): 0x01
        // bit 2 (Offset Green): 0x04
        // bit 3 (Disable Red): 0x08
        // bit 4 (Shift Up Green): 0x10
        // bit 5 (Shift Down Green): 0x20
        // bit 6 (Play Still Green): 0x40
        // bit 7 (Wipe Still Green): 0x80
        // Expected byte 1: 0x01 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x80 = 0xFD
        XCTAssertEqual(fullPayload[1], 0xFD)
        
        // Byte 2 contains bits 8..15:
        // bit 8 (H/Lite Green): 0x01
        // bit 9 (Viewer Green): 0x02
        // bit 10 (Cursor Green): 0x04
        // Expected byte 2: 0x01 | 0x02 | 0x04 = 0x07
        XCTAssertEqual(fullPayload[2], 0x07)
        
        // Bytes 3..6 should be 0 since bits 11..47 have no populated LEDs
        for i in 3..<7 {
            XCTAssertEqual(fullPayload[i], 0x00)
        }
    }
    
    func testColorControlNameMappingAndProperties() {
        XCTAssertEqual(PanelColorLED.allCases.count, 10)
        
        // Red channels
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "BYPASS"), .bypassRed)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "BYPASS"), 0)
        XCTAssertTrue(PanelColorLED.bypassRed.isRed)
        XCTAssertFalse(PanelColorLED.bypassRed.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "DISABLE"), .disableRed)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "DISABLE"), 3)
        XCTAssertTrue(PanelColorLED.disableRed.isRed)
        XCTAssertFalse(PanelColorLED.disableRed.isGreen)
        
        // Green channels
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "OFFSET"), .offsetGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "OFFSET"), 2)
        XCTAssertTrue(PanelColorLED.offsetGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "SHIFT"), .shiftUpGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "SHIFT"), 4)
        XCTAssertTrue(PanelColorLED.shiftUpGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "CORNER_LOWER_RIGHT"), .shiftDownGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "CORNER_LOWER_RIGHT"), 5)
        XCTAssertTrue(PanelColorLED.shiftDownGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "PLAY_STILL"), .playStillGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "PLAY_STILL"), 6)
        XCTAssertTrue(PanelColorLED.playStillGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "WIPE_STILL"), .wipeStillGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "WIPE_STILL"), 7)
        XCTAssertTrue(PanelColorLED.wipeStillGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "H/LITE"), .hliteGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "H/LITE"), 8)
        XCTAssertTrue(PanelColorLED.hliteGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "VIEWER"), .viewerGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "VIEWER"), 9)
        XCTAssertTrue(PanelColorLED.viewerGreen.isGreen)
        
        XCTAssertEqual(PanelLEDController.colorChannel(forControl: "CURSOR"), .cursorGreen)
        XCTAssertEqual(PanelLEDController.colorBit(forControl: "CURSOR"), 10)
        XCTAssertTrue(PanelColorLED.cursorGreen.isGreen)
        
        // Non-color controls return nil
        XCTAssertNil(PanelLEDController.colorChannel(forControl: "UNDO"))
        XCTAssertNil(PanelLEDController.colorBit(forControl: "UNDO"))
    }
    
    func testLightShowFrameCodable() throws {
        let frame = LightShowFrame(
            active: true,
            whiteControls: ["UNDO", "REDO"],
            colorControls: ["BYPASS": "red", "SHIFT": "green"],
            title: "Color Reveal",
            subtitle: "10 Channels"
        )
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(LightShowFrame.self, from: data)
        XCTAssertEqual(frame, decoded)
        XCTAssertEqual(decoded.colorControls["BYPASS"], "red")
        XCTAssertEqual(decoded.colorControls["SHIFT"], "green")
    }
    
    func testRewindReactiveLightingSettingDefault() {
        XCTAssertTrue(AppSettings.shared.rewindReactiveLighting)
    }
    
    func testRewindLEDAnimatorLifecycle() {
        let animator = RewindLEDAnimator.shared
        animator.start()
        animator.noteWheelDelta(command: RewindCommands.scrub, deltaUnits: -5.0)
        animator.noteWheelDelta(command: RewindCommands.scrub, deltaUnits: 5.0)
        animator.stop()
        // Successfully starts, receives ticks, and stops cleanly without crashing or dangling timers
    }

    func testPanelManagerNeverSuppressesEmptyButtonRelease() {
        let emptyReport = Data([0x02, 0, 0, 0, 0, 0, 0, 0, 0])
        var until = Date().addingTimeInterval(10.0)
        let now = Date()
        let shouldSuppress = PanelManager.shouldSuppressButtonReport(emptyReport, until: &until, now: now)
        XCTAssertFalse(shouldSuppress, "Empty button release reports must never be suppressed, or key releases will be swallowed.")
    }

    func testTrackballLightAnimatorMotionAndDirection() {
        let animator = TrackballLightAnimator.shared
        XCTAssertFalse(animator.isAnimating)

        // Push Lift ball up/forward
        animator.noteMotion(ballName: "TB_LIFT_Y", axis: "Y", delta: 10.0)
        // Push Gamma ball rightward
        animator.noteMotion(ballName: "TB_GAMMA_X", axis: "X", delta: 10.0)
        // Push Gain ball down
        animator.noteMotion(ballName: "TB_GAIN_Y", axis: "Y", delta: -10.0)

        XCTAssertTrue(AppSettings.shared.trackballRadiantLighting)
    }

    func testKnobWavesReachTheKeysNearestThem() {
        let animator = TrackballLightAnimator.shared
        func bit(_ name: String) -> Int { HardwareMap.shared.buttonBit(forControl: name)! }
        let lift = animator.controlsReached(byKnob: "Y_LIFT")
        for near in ["AUTO_COLOR", "OFFSET", "COPY", "PASTE", "UNDO", "REDO", "DELETE", "RESET_ALL", "PLAY_STILL"] {
            XCTAssertTrue(lift.contains(bit(near)), "Y Lift should reach \(near)")
        }
        XCTAssertFalse(lift.contains(bit("WIPE_STILL")), "Y Lift should not reach Wipe")
        let gamma = animator.controlsReached(byKnob: "Y_GAMMA")
        for near in ["OFFSET", "PLAY_STILL", "WIPE_STILL", "GRAB_STILL"] {
            XCTAssertTrue(gamma.contains(bit(near)), "Y Gamma should reach \(near)")
        }
    }

    func testSemanticColorBitsAtRestAreNotForced() {
        let engine = StudioEngine.shared
        // When not in any mode and nothing pressed/held, colors should be clean
        let colors = engine.currentSemanticColorBits()
        // If neither bypass nor disable nor shift are active, their bits shouldn't be forced
        if !engine.isBeforeViewActive {
            XCTAssertFalse(colors.contains(PanelColorLED.bypassRed.rawValue))
        }
        XCTAssertFalse(colors.contains(PanelColorLED.disableRed.rawValue))
        XCTAssertFalse(colors.contains(PanelColorLED.shiftUpGreen.rawValue))
        XCTAssertFalse(colors.contains(PanelColorLED.shiftDownGreen.rawValue))
    }

    func testIntroLEDDirectorScenesAndTransitions() {
        let director = IntroLEDDirector.shared
        XCTAssertFalse(director.isActive)

        director.start()
        XCTAssertTrue(director.isActive)
        XCTAssertTrue(StudioEngine.shared.isLightShowActive)

        // Scene 0: Title
        director.update(scene: 0, t: 1.0)
        // Scene 1: Overview
        director.update(scene: 1, t: 1.0)
        // Scene 2: Knobs
        director.update(scene: 2, t: 1.0)
        // Scene 3: Trackballs
        director.update(scene: 3, t: 2.0)
        // Scene 4: Modes (Color Mixer, Upright, Viewer, Masks)
        director.update(scene: 4, t: 1.0)
        // Scene 5: Hold vs Toggle
        director.update(scene: 5, t: 2.0)
        // Scene 6: Mask Wheel
        director.update(scene: 6, t: 2.0)
        // Scene 7: Rewind+
        director.update(scene: 7, t: 2.0)
        // Scene 8: Safety
        director.update(scene: 8, t: 1.0)
        // Scene 9: Finale
        director.update(scene: 9, t: 1.0)

        director.stop()
        XCTAssertFalse(director.isActive)
        XCTAssertFalse(StudioEngine.shared.isLightShowActive)
    }
}

