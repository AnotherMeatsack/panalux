import XCTest
@testable import PanaLux

final class ValueFormatterTests: XCTestCase {
    func testZeroNeverSigned() {
        XCTAssertEqual(ValueFormatter.format(param: "Contrast", value: 0.5), "0")
        XCTAssertEqual(ValueFormatter.format(param: "Contrast", value: 0.49999), "0")
        XCTAssertEqual(ValueFormatter.format(param: "Exposure", value: 0.5), "0.00 EV")
        XCTAssertEqual(ValueFormatter.format(param: "Exposure", value: 0.4999999), "0.00 EV")
    }

    func testSignedValues() {
        XCTAssertEqual(ValueFormatter.format(param: "Exposure", value: 0.547), "+0.47 EV")
        XCTAssertEqual(ValueFormatter.format(param: "Exposure", value: 0.453), "-0.47 EV")
        XCTAssertEqual(ValueFormatter.format(param: "Contrast", value: 0.75), "+50")
        XCTAssertEqual(ValueFormatter.format(param: "Temperature", value: 0.0625), "5000 K")
        XCTAssertEqual(ValueFormatter.format(param: "CropLeft", value: 0.1), "10%")
    }
}

final class PanelDecoderTests: XCTestCase {
    /// 0x02 is a valid first bitmap byte. Stripping it would shift every button by 8 bits.
    func testButtonBitmapStartingWith0x02IsNotStripped() {
        let decoder = PanelDecoder()
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 0x02 // bit 1
        let motions = decoder.decode(reportId: 0x02, data: Data(bytes))
        XCTAssertEqual(motions.map(\.slot), [1])
        XCTAssertEqual(motions.first?.kind, .keyDown)
    }

    func testLeadingReportIDIsStrippedByLength() {
        let decoder = PanelDecoder()
        var bytes = [UInt8](repeating: 0, count: 9)
        bytes[0] = 0x02
        bytes[4] = 0x01 // byte 3 → bit 24 (Up Shift)
        let motions = decoder.decode(reportId: 0x02, data: Data(bytes))
        XCTAssertEqual(motions.map(\.slot), [24])
    }

    func testKeyUpFollowsKeyDown() {
        let decoder = PanelDecoder()
        var down = [UInt8](repeating: 0, count: 8)
        down[2] = 0x40 // bit 22 (User)
        _ = decoder.decode(reportId: 0x02, data: Data(down))
        let up = decoder.decode(reportId: 0x02, data: Data(repeating: 0, count: 8))
        XCTAssertEqual(up.map(\.slot), [22])
        XCTAssertEqual(up.first?.kind, .keyUp)
    }
}

final class CommandCatalogTests: XCTestCase {
    private var db: CommandDatabase { CommandDatabase.shared }

    func testCommandsLoad() {
        XCTAssertGreaterThan(db.commands.count, 900)
    }

    /// Every ID the factory map sends must exist in MIDI2LR, or the key silently does nothing.
    func testFactoryMapUsesRealCommands() throws {
        let factory = Profile.loadDefault()
        var ids = Set<String>()
        ids.formUnion(factory.knobs.values.map(\.param))
        ids.formUnion(factory.rings.values.map(\.param))
        ids.formUnion(factory.balls.values.flatMap { [$0.hue, $0.sat] })
        func add(_ b: ButtonBinding) {
            [b.action, b.hold_action, b.release_action, b.tapProgram?.focusParam, b.holdProgram?.focusParam]
                .compactMap { $0 }.forEach { ids.insert($0) }
        }
        factory.buttons.values.forEach(add)
        for layer in factory.layers.values {
            ids.formUnion((layer.knobs ?? [:]).values.map(\.param))
            ids.formUnion((layer.rings ?? [:]).values.map(\.param))
            ids.formUnion((layer.balls ?? [:]).values.flatMap { [$0.hue, $0.sat] })
            (layer.buttons ?? [:]).values.forEach(add)
            for v in (layer.variants ?? [:]).values {
                ids.formUnion((v.knobs ?? [:]).values.map(\.param))
            }
        }
        let missing = ids.filter {
            db.commands[$0] == nil
                && !$0.hasPrefix(WheelReset.prefix)
                && !PointerCommands.isPointer($0)
                && !RewindCommands.isRewind($0)
                && LightroomMenuActions.item($0) == nil
        }.sorted()
        XCTAssertEqual(missing, [], "Factory map uses commands MIDI2LR doesn't have")
        XCTAssertGreaterThan(factory.layers.count, 10)
    }

    /// Rewind is PanaLux's own, so it has to be reachable and remappable like everything else.
    func testFactoryMapWiresRewindToHoldingUndo() {
        let factory = Profile.loadDefault()
        XCTAssertEqual(factory.buttons["UNDO"]?.action, "Undo", "the tap is still Undo")
        XCTAssertEqual(factory.buttons["UNDO"]?.hold_layer, "REWIND")
        let layer = factory.layers["REWIND"]
        XCTAssertNotNil(layer)
        XCTAssertEqual(layer?.rings?["RING_GAMMA"]?.param, RewindCommands.scrub)
        XCTAssertEqual(layer?.rings?["RING_GAIN"]?.param, RewindCommands.strength)
        XCTAssertEqual(layer?.buttons?["NEXT_STILL"]?.action, RewindCommands.tip)
        XCTAssertEqual(layer?.buttons?["ADD_KEYFRM"]?.action, RewindCommands.mark)
        XCTAssertEqual(layer?.buttons?["ADD_NODE"]?.action, RewindCommands.branch)
        XCTAssertEqual(layer?.buttons?["PREV_KEYFRM"]?.action, RewindCommands.previous)
        XCTAssertEqual(layer?.buttons?["NEXT_KEYFRM"]?.action, RewindCommands.next)
        XCTAssertEqual(layer?.buttons?["WIPE_STILL"]?.hold_action, RewindCommands.peek)
        XCTAssertEqual(layer?.buttons?["WIPE_STILL"]?.release_action, RewindCommands.unpeek)
        // Every one of them is a tile the user can drag somewhere else.
        for id in [RewindCommands.scrub, RewindCommands.strength, RewindCommands.tip,
                   RewindCommands.mark, RewindCommands.branch, RewindCommands.previous,
                   RewindCommands.next, RewindCommands.peek] {
            XCTAssertNotNil(CommandCatalog.shared.command(for: id), id)
        }
        XCTAssertTrue(CommandDatabase.shared.catalogCommand(for: RewindCommands.scrub).isParameter,
                      "scrub has to be droppable on a ring")
        XCTAssertFalse(CommandDatabase.shared.catalogCommand(for: RewindCommands.tip).isParameter)
    }

    func testV10GivesUndoARewindHoldWithoutTakingOne() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(9, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        user.buttons["UNDO"] = ButtonBinding(action: "Undo")
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertEqual(migrated.buttons["UNDO"]?.hold_layer, "REWIND")
        XCTAssertEqual(migrated.buttons["UNDO"]?.action, "Undo")

        defaults.set(9, forKey: "profileSchemaVersion")
        var kept = factory
        kept.buttons["UNDO"] = ButtonBinding(action: "Undo", hold_layer: "CULL")
        let skipped = Profile.migrate(kept, factory: factory, defaults: defaults) {}
        XCTAssertEqual(skipped.buttons["UNDO"]?.hold_layer, "CULL", "a hold the user chose is kept")
        defaults.removePersistentDomain(forName: name)
    }

    func testCuratedTilesUseRealCommands() {
        let special: (String) -> Bool = { $0.contains(":") || $0 == "smart_roundtrip" || $0 == "hold_compare" }
        let missing = CommandCatalog.shared.categories
            .flatMap(\.items)
            .map(\.id)
            .filter { !special($0) && db.commands[$0] == nil }
        XCTAssertEqual(missing, [])
    }

    func testRenamedCommandsPointAtRealOnes() {
        for (old, new) in Profile.renamedCommands {
            XCTAssertNil(db.commands[old], "\(old) exists after all")
            XCTAssertNotNil(db.commands[new], "\(new) is not a MIDI2LR command")
        }
    }

    func testRepeatPairsResolve() {
        for id in ["NextPrev", "ZoomInOut", "ChangeBrushSize", "ChangeFeatherSize", "PresetPreviousNext",
                   "IncreaseDecreaseRating", "Key2Key1", "QuickDevExpAdj"] {
            let pair = RepeatCommands.pair(for: id)
            XCTAssertNotNil(pair, id)
            XCTAssertTrue(db.isDialable(id), id)
        }
        XCTAssertNil(RepeatCommands.pair(for: "Exposure"))
    }

    func testFriendlyLabels() {
        XCTAssertEqual(db.label(for: "MaskNewRad"), "New Radial Mask")
        XCTAssertEqual(db.label(for: "MaskSubBrush"), "Subtract Brush")
        XCTAssertEqual(db.label(for: "local_Exposure"), "Mask Exposure")
        XCTAssertEqual(db.label(for: "CropLeft"), "Crop Left")
        XCTAssertEqual(db.shortLabel(for: "SaturationAdjustmentRed"), "Sat Red")
        XCTAssertLessThanOrEqual(db.shortLabel(for: "PostCropVignetteAmount").count, 12)
    }

    func testSlowCommands() {
        XCTAssertTrue(SlowCommands.isSlow("MaskNewSubject"))
        XCTAssertFalse(SlowCommands.isSlow("MaskNewRad"))
    }
}

final class ProfileMigrationTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "panalux-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testV2AddsHoldsWithoutOverwritingUserChoices() {
        let factory = Profile.loadDefault()
        var user = factory
        user.buttons["VIEWER"] = ButtonBinding(action: "NextScreenMode")          // tap only → gets Crop hold
        user.buttons["SELECT"] = ButtonBinding(action: "Pick", modifier: "FINE")   // has a hold → untouched
        user.buttons["WIPE_STILL"] = ButtonBinding(action: "ToggleOverlay")        // bad ID → fixed
        var backedUp = false
        let migrated = Profile.migrate(user, factory: factory, defaults: freshDefaults()) { backedUp = true }
        XCTAssertTrue(backedUp)
        XCTAssertEqual(migrated.buttons["VIEWER"]?.hold_layer, "CROP")
        XCTAssertEqual(migrated.buttons["VIEWER"]?.action, "NextScreenMode")
        XCTAssertEqual(migrated.buttons["SELECT"]?.modifier, "FINE")
        XCTAssertNil(migrated.buttons["SELECT"]?.hold_layer)
        XCTAssertEqual(migrated.buttons["WIPE_STILL"]?.action, "ShoVwdevelop_before_after_horiz")
    }

    func testEveryModeGetsAKeyWithoutOverwriting() {
        let factory = Profile.loadDefault()
        var user = factory
        user.buttons["AUTO_COLOR"] = ButtonBinding(action: "AutoTone")                  // tap only → gets Tone hold
        user.buttons["PLAY"] = ButtonBinding(action: "openExportWithPreviousDialog", modifier: "FINE") // has a hold → kept
        user.buttons["PLAY_REV"] = ButtonBinding(action: "Undo")                          // has a tap → kept
        let migrated = Profile.migrate(user, factory: factory, defaults: freshDefaults()) {}
        XCTAssertEqual(migrated.buttons["AUTO_COLOR"]?.hold_layer, "TONE")
        XCTAssertEqual(migrated.buttons["AUTO_COLOR"]?.action, "AutoTone")
        XCTAssertNil(migrated.buttons["PLAY"]?.hold_layer)
        XCTAssertEqual(migrated.buttons["PLAY_REV"]?.action, "Undo")
        // Every factory mode is reachable from some key.
        let reachable = Set(factory.buttons.values.flatMap { [$0.hold_layer, $0.layer] }.compactMap { $0 })
        XCTAssertEqual(Set(factory.layers.keys).subtracting(reachable), [])
    }

    func testMigrationRunsOnce() {
        let defaults = freshDefaults()
        let factory = Profile.loadDefault()
        _ = Profile.migrate(factory, factory: factory, defaults: defaults) {}
        var user = factory
        user.buttons["VIEWER"] = ButtonBinding(action: "NextScreenMode")
        var backedUp = false
        let again = Profile.migrate(user, factory: factory, defaults: defaults) { backedUp = true }
        XCTAssertFalse(backedUp)
        XCTAssertNil(again.buttons["VIEWER"]?.hold_layer, "second run must not re-add removed holds")
    }

    func testSharedMapRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var profile = Profile.loadDefault()
        profile.knobs["Y_LIFT"] = KnobBinding(param: "Dehaze", scale: 0.0006)
        let url = dir.appendingPathComponent("Test" + ProfileStore.fileSuffix)
        try ProfileStore.export(profile, name: "Test Map", to: url)
        let (name, loaded) = try ProfileStore.load(from: url)
        XCTAssertEqual(name, "Test Map")
        XCTAssertEqual(loaded.knobs["Y_LIFT"], KnobBinding(param: "Dehaze", scale: 0.0006))
        let packet = try ProfileStore.loadPacket(from: url)
        XCTAssertEqual(packet.format, "panalux-map")
        XCTAssertEqual(packet.version, 2)
        XCTAssertNotNil(packet.settings)
        XCTAssertFalse(packet.readme?.isEmpty ?? true)
        XCTAssertTrue(packet.readme?.contains(where: { $0.contains("Dehaze") }) == true)
        XCTAssertNotNil(packet.hardware)
        XCTAssertEqual(packet.settings?.fine, AppSettings.shared.fineMultiplier)
    }

    func testV1SharedMapStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var profile = Profile.loadDefault()
        profile.knobs["Y_LIFT"] = KnobBinding(param: "Dehaze", scale: 0.0006)
        struct V1: Encodable {
            var format = "panalux-map"
            var version = 1
            var name = "Old Share"
            var profile: Profile
        }
        let url = dir.appendingPathComponent("old.panalux.json")
        let encoder = JSONEncoder()
        try encoder.encode(V1(profile: profile)).write(to: url)
        let packet = try ProfileStore.loadPacket(from: url)
        XCTAssertEqual(packet.name, "Old Share")
        XCTAssertEqual(packet.profile.knobs["Y_LIFT"]?.param, "Dehaze")
        XCTAssertNil(packet.settings)
        XCTAssertNil(packet.hardware)
    }

    func testBareProfileImportGetsRepaired() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var old = Profile.loadDefault()
        old.layers = ["MIXER": old.layers["MIXER"]!]
        old.buttons["WIPE_STILL"] = ButtonBinding(action: "ToggleOverlay")
        let url = dir.appendingPathComponent("old.json")
        try Profile.encoded(old).write(to: url)
        let (name, loaded) = try ProfileStore.load(from: url)
        XCTAssertEqual(name, "old")
        XCTAssertNotNil(loaded.layers["CROP"], "factory modes are added to old maps")
        XCTAssertEqual(loaded.buttons["WIPE_STILL"]?.action, "ShoVwdevelop_before_after_horiz")
    }

    func testButtonSlotsClearIndependently() {
        var b = ButtonBinding(action: "Pick", hold_layer: "CULL")
        b.clearTap()
        XCTAssertNil(b.action)
        XCTAssertEqual(b.hold_layer, "CULL")
        b.clearHold()
        XCTAssertFalse(b.hasAnyAssignment)
    }
}

final class HoldEditingTests: XCTestCase {
    func testResetButtonsDontLookLikeSliders() {
        let db = CommandDatabase.shared
        XCTAssertEqual(db.label(for: "Sharpness"), "Sharpness")
        XCTAssertEqual(db.label(for: "ResetSharpness"), "Reset Sharpness")
        XCTAssertFalse(db.catalogCommand(for: "ResetSharpness").isParameter)
        XCTAssertTrue(db.catalogCommand(for: "Sharpness").isParameter)
    }

    func testOldWholeRowFillIsDropped() {
        var knobs: [String: KnobBinding]? = Dictionary(uniqueKeysWithValues: PanelLayout.knobs.map { ($0, KnobBinding(param: "VignetteAmount")) })
        StudioEngine.dropUniformFill(&knobs, count: PanelLayout.knobs.count, keeping: "LUM_MIX")
        XCTAssertEqual(knobs?.keys.sorted(), ["LUM_MIX"])

        var mixed: [String: KnobBinding]? = ["Y_LIFT": KnobBinding(param: "Blacks"), "LUM_MIX": KnobBinding(param: "Sharpness")]
        StudioEngine.dropUniformFill(&mixed, count: PanelLayout.knobs.count, keeping: "LUM_MIX")
        XCTAssertEqual(mixed?.count, 2, "a real per-knob map is left alone")
    }

    func testBallSliderRoundTrips() throws {
        let b = BallBinding.slider("Sharpness")
        let back = try JSONDecoder().decode(BallBinding.self, from: JSONEncoder().encode(b))
        XCTAssertEqual(back.param, "Sharpness")
        let old = try JSONDecoder().decode(BallBinding.self, from: Data(#"{"hue":"A","sat":"B","radius":3000,"invert_x":true,"invert_y":true}"#.utf8))
        XCTAssertNil(old.param)
    }

    func testMenuActionsResolve() {
        XCTAssertEqual(LightroomMenuActions.title("lr_menu:sync"), "Sync Settings")
        XCTAssertNil(LightroomMenuActions.item("Undo"))
    }

    func testSendKeyCodes() {
        XCTAssertEqual(LightroomKeys.keyCodes["c"], 8)
        XCTAssertEqual(LightroomKeys.keyCodes["v"], 9)
        XCTAssertEqual(LightroomKeys.keyCodes["z"], 6)
        XCTAssertEqual(LightroomKeys.keyCodes["["], 33)
        XCTAssertEqual(LightroomKeys.keyCodes["\\"], 42)
    }
}

final class LiveReadingTests: XCTestCase {
    func testSeveralControlsShowTogetherInPanelOrder() {
        var recent = RecentReadings()
        let start = Date()
        let controls = ["RING_GAIN", "TB_LIFT", "Y_GAMMA"]
        var shown: [LiveReading] = []
        for i in 0..<9 {
            let c = controls[i % 3]
            shown = recent.record(LiveReading(control: c, param: c, value: "\(i)"), now: start.addingTimeInterval(Double(i) * 0.02))
        }
        XCTAssertEqual(shown.map(\.control), ["Y_GAMMA", "TB_LIFT", "RING_GAIN"])
    }

    func testSwitchingControlsIsNotSimultaneous() {
        var recent = RecentReadings()
        let start = Date()
        for i in 0..<5 {
            _ = recent.record(LiveReading(control: "CONTRAST", param: "Contrast", value: "\(i)"), now: start.addingTimeInterval(Double(i) * 0.02))
        }
        // Hand moves to Shadows right after Contrast stops.
        let shown = recent.record(LiveReading(control: "SHAD", param: "Shadows", value: "+1"), now: start.addingTimeInterval(0.15))
        XCTAssertEqual(shown.map(\.control), ["SHAD"])
    }

    func testInterleavedTicksAreSimultaneous() {
        var recent = RecentReadings()
        let start = Date()
        var shown: [LiveReading] = []
        for i in 0..<6 {
            let t = start.addingTimeInterval(Double(i) * 0.02)
            let control = i.isMultiple(of: 2) ? "CONTRAST" : "SHAD"
            shown = recent.record(LiveReading(control: control, param: control, value: "\(i)"), now: t)
        }
        XCTAssertEqual(Set(shown.map(\.control)), ["CONTRAST", "SHAD"])
    }

    func testStaleControlsDropOut() {
        var recent = RecentReadings()
        let start = Date()
        _ = recent.record(LiveReading(control: "Y_LIFT", param: "Blacks", value: "-3"), now: start)
        let later = recent.record(LiveReading(control: "CONTRAST", param: "Contrast", value: "+8"), now: start.addingTimeInterval(1))
        XCTAssertEqual(later.map(\.control), ["CONTRAST"])
    }

    func testRepeatedTicksFromOneKnobStayOneReading() {
        var recent = RecentReadings()
        let now = Date()
        _ = recent.record(LiveReading(control: "Y_GAMMA", param: "Exposure", value: "+0.10 EV"), now: now)
        let shown = recent.record(LiveReading(control: "Y_GAMMA", param: "Exposure", value: "+0.11 EV"), now: now)
        XCTAssertEqual(shown, [LiveReading(control: "Y_GAMMA", param: "Exposure", value: "+0.11 EV")])
    }
}

final class UndoResetTests: XCTestCase {
    func testWheelResetTargetsItsOwnBallAndRing() {
        let db = CommandDatabase.shared
        let known = Set(db.commands.keys)
        let factory = Profile.loadDefault()
        let lift = WheelReset.commands(ball: factory.balls["TB_LIFT"], ringParam: factory.rings["RING_LIFT"]?.param, known: known)
        XCTAssertEqual(lift, ["ResetSplitToningShadowHue", "ResetSplitToningShadowSaturation", "ResetColorGradeShadowLum"])
        let gamma = WheelReset.commands(ball: factory.balls["TB_GAMMA"], ringParam: factory.rings["RING_GAMMA"]?.param, known: known)
        XCTAssertEqual(gamma, ["ResetColorGradeMidtoneHue", "ResetColorGradeMidtoneSat", "ResetColorGradeMidtoneLum"])
        XCTAssertEqual(factory.buttons["RESET_GAIN"]?.action, "reset_wheel:GAIN")
    }

    func testV3MovesResetCurrentToExactWheel() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(2, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        user.buttons["RESET_LIFT"] = ButtonBinding(action: "ColorGradeResetCurrent")
        user.buttons["RESET_GAIN"] = ButtonBinding(action: "Undo") // user's own choice stays
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertEqual(migrated.buttons["RESET_LIFT"]?.action, "reset_wheel:LIFT")
        XCTAssertEqual(migrated.buttons["RESET_GAIN"]?.action, "Undo")
        defaults.removePersistentDomain(forName: name)
    }

    func testTrackballSyncMatchesLightroom() {
        let ball = TrackballEngine(name: "TB_GAMMA", hueParam: "h", satParam: "s")
        ball.sync(turns: 0.25, saturation: 0.4)
        let state = ball.currentState
        XCTAssertEqual(state.hueAngle, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.saturation, 0.4, accuracy: 0.0001)
        let (turns, sat) = ball.push(dx: 0, dy: 0)
        XCTAssertEqual(turns, 0.25, accuracy: 0.0001)
        XCTAssertEqual(sat, 0.4, accuracy: 0.0001)
        ball.stopInertia()
    }

    func testResetWheelTilesAreNamed() {
        XCTAssertEqual(CommandDatabase.shared.label(for: "reset_wheel:LIFT"), "Reset Shadows Wheel")
    }
}

final class MaskToolPickerTests: XCTestCase {
    func testFactoryAddNodeOpensTheWheel() {
        let factory = Profile.loadDefault()
        XCTAssertEqual(factory.buttons["ADD_NODE"]?.action, "MaskNewGrad")
        XCTAssertEqual(factory.buttons["ADD_NODE"]?.hold_picker, MaskToolPicker.id)
        XCTAssertEqual(factory.layers["MASK"]?.buttons?["ADD_NODE"]?.hold_picker, MaskToolPicker.id)
        XCTAssertEqual(factory.layers["MASK"]?.balls?["TB_GAIN"]?.hue, "local_ToningHue")
        XCTAssertNil(factory.layers["MASK"]?.balls?["TB_GAIN"]?.param)
        XCTAssertEqual(factory.layers["MASK"]?.balls?["TB_GAMMA"]?.hue, "local_ToningHue")
        XCTAssertEqual(factory.layers["MASK"]?.balls?["TB_LIFT"]?.hue, "local_ToningHue")
        XCTAssertEqual(factory.layers["MASK"]?.rings?["RING_GAIN"]?.param, "local_ToningLuminance")
        XCTAssertNil(factory.layers["MASK"]?.buttons?["LOOP"])
        XCTAssertEqual(LocalAdjustments.localParam(forGlobal: "Exposure"), "local_Exposure")
        XCTAssertEqual(LocalAdjustments.mirroredKnobs(from: factory)["Y_GAMMA"]?.param, "local_Exposure")
        XCTAssertEqual(LocalAdjustments.mirroredKnobs(from: factory)["CONTRAST"]?.param, "local_Contrast")
        XCTAssertEqual(LocalAdjustments.mirroredKnobs(from: factory)["HI_LIGHT"]?.param, "local_Highlights")
    }

    func testEveryWheelCommandExists() {
        let db = CommandDatabase.shared
        for tool in MaskToolPicker.tools {
            XCTAssertNotNil(db.commands[tool.createCommand], tool.createCommand)
        }
        XCTAssertEqual(MaskToolPicker.tools.count, 12)
        let land = MaskToolPicker.tools.first { $0.kind == "Land" }!
        XCTAssertEqual(land.command(combine: .subtract), "MaskNewLand", "MIDI2LR has no MaskSubLand")
        XCTAssertEqual(land.command(combine: .add), "MaskAddLand")
        XCTAssertEqual(MaskToolPicker.tools[1].command(combine: .subtract), "MaskSubRad")
    }

    func testDetentsWrap() {
        XCTAssertEqual(MaskToolPicker.steppedIndex(from: 0, clockwise: false), 11)
        XCTAssertEqual(MaskToolPicker.steppedIndex(from: 11, clockwise: true), 0)
        XCTAssertEqual(MaskToolPicker.tool(at: 0).createCommand, "MaskNewGrad")
        XCTAssertTrue(MaskToolPicker.placesWithPointer(command: "MaskNewBrush"))
        XCTAssertTrue(MaskToolPicker.placesWithPointer(command: "MaskAddRad"))
        XCTAssertFalse(MaskToolPicker.placesWithPointer(command: "MaskNewSubject"))
        XCTAssertFalse(MaskToolPicker.placesWithPointer(command: "MaskHide"))
        XCTAssertEqual(MaskToolPicker.steppedCombine(from: .create, clockwise: true), .add)
        XCTAssertEqual(MaskToolPicker.steppedCombine(from: .create, clockwise: false), .intersect)
    }

    func testAimPicksTopWedge() {
        XCTAssertEqual(MaskToolPicker.centerAngle(index: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(MaskToolPicker.centerAngle(index: 3), .pi / 2, accuracy: 0.001)
        XCTAssertEqual(MaskToolPicker.index(aiming: 0, dy: 800), 0)
        XCTAssertEqual(MaskToolPicker.index(aiming: 800, dy: 0), 3)
        XCTAssertNil(MaskToolPicker.index(aiming: 10, dy: 10))
        let top = MaskToolPicker.polarPoint(angle: 0, radius: 100, center: CGPoint(x: 200, y: 200))
        XCTAssertEqual(top.x, 200, accuracy: 0.01)
        XCTAssertEqual(top.y, 100, accuracy: 0.01)
        let right = MaskToolPicker.polarPoint(angle: .pi / 2, radius: 100, center: CGPoint(x: 200, y: 200))
        XCTAssertEqual(right.x, 300, accuracy: 0.01)
        XCTAssertEqual(right.y, 200, accuracy: 0.01)
    }

    func testV6AddsPickerWithoutOverwritingAHold() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(5, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        user.buttons["ADD_NODE"] = ButtonBinding(action: "MaskNewGrad", enter_layer: "MASK")
        user.buttons["LOOP"] = ButtonBinding(modifier: "FINE")
        var mask = user.layers["MASK"]!
        mask.balls?["TB_LIFT"] = nil
        mask.buttons?["LOOP"] = nil
        user.layers["MASK"] = mask
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertEqual(migrated.buttons["ADD_NODE"]?.hold_picker, "mask_tools")
        XCTAssertEqual(migrated.buttons["ADD_NODE"]?.action, "MaskNewGrad")
        XCTAssertEqual(migrated.layers["MASK"]?.buttons?["ADD_NODE"]?.hold_picker, "mask_tools")
        XCTAssertNil(migrated.layers["MASK"]?.buttons?["LOOP"])
        var kept = factory
        kept.buttons["ADD_NODE"] = ButtonBinding(action: "MaskNewGrad", hold_layer: "CROP")
        defaults.set(5, forKey: "profileSchemaVersion")
        let skipped = Profile.migrate(kept, factory: factory, defaults: defaults) {}
        XCTAssertNil(skipped.buttons["ADD_NODE"]?.hold_picker)
        XCTAssertEqual(skipped.buttons["ADD_NODE"]?.hold_layer, "CROP")
        defaults.removePersistentDomain(forName: name)
    }

    func testV7MovesPointerToRightBall() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(6, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        var mask = user.layers["MASK"]!
        mask.balls?["TB_LIFT"] = BallBinding.slider(PointerCommands.move)
        mask.balls?["TB_GAIN"] = BallBinding(hue: "local_ToningHue", sat: "local_ToningSaturation")
        user.layers["MASK"] = mask
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertEqual(migrated.layers["MASK"]?.balls?["TB_LIFT"]?.hue, "local_ToningHue")
        XCTAssertEqual(migrated.layers["MASK"]?.balls?["TB_GAIN"]?.hue, "local_ToningHue")
        XCTAssertNil(migrated.layers["MASK"]?.balls?["TB_GAIN"]?.param)
        defaults.removePersistentDomain(forName: name)
    }

    func testV8TurnsPointerBallsIntoMaskColor() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(7, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        var mask = user.layers["MASK"]!
        mask.balls?["TB_GAIN"] = BallBinding.slider(PointerCommands.move)
        mask.balls?["TB_GAMMA"] = nil
        user.layers["MASK"] = mask
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertEqual(migrated.layers["MASK"]?.balls?["TB_GAIN"]?.hue, "local_ToningHue")
        XCTAssertNil(migrated.layers["MASK"]?.balls?["TB_GAIN"]?.param)
        XCTAssertEqual(migrated.layers["MASK"]?.balls?["TB_GAMMA"]?.hue, "local_ToningHue")
        XCTAssertEqual(migrated.layers["MASK"]?.balls?["TB_LIFT"]?.hue, "local_ToningHue")
        defaults.removePersistentDomain(forName: name)
    }

    func testV9RemovesMaskPointerOverlays() {
        let name = "panalux-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(8, forKey: "profileSchemaVersion")
        let factory = Profile.loadDefault()
        var user = factory
        var mask = user.layers["MASK"]!
        mask.buttons?["LOOP"] = ButtonBinding(
            action: PointerCommands.click,
            hold_action: PointerCommands.down,
            release_action: PointerCommands.up
        )
        mask.rings?["RING_GAIN"] = RingBinding(param: PointerCommands.size)
        user.layers["MASK"] = mask
        let migrated = Profile.migrate(user, factory: factory, defaults: defaults) {}
        XCTAssertNil(migrated.layers["MASK"]?.buttons?["LOOP"])
        XCTAssertEqual(migrated.layers["MASK"]?.rings?["RING_GAIN"]?.param, "local_ToningLuminance")
        XCTAssertEqual(migrated.layers["MASK"]?.buttons?["ADD_NODE"]?.hold_picker, MaskToolPicker.id)
        defaults.removePersistentDomain(forName: name)
    }
}
