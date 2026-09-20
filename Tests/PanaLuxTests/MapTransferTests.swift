import XCTest
import SwiftUI
@testable import PanaLux

final class MapTransferTests: XCTestCase {
    func testHoldTransferKeepsTapAndClonesConflictingLayer() {
        var mine = Profile.loadDefault(), theirs = Profile.loadDefault()
        mine.buttons["USER"] = ButtonBinding(action: "Undo", hold_layer: "TRANSFORM")
        theirs.buttons["USER"] = ButtonBinding(action: "Redo", hold_layer: "TRANSFORM")
        theirs.layers["TRANSFORM"]?.knobs = ["Y_LIFT": KnobBinding(param: "Exposure")]
        let oldLayer = mine.layers["TRANSFORM"]
        let r = MapTransfer.merge(source: theirs, into: mine, selection: .init(controls: ["USER"], slice: .hold))
        XCTAssertEqual(r.profile.buttons["USER"]?.action, "Undo")
        XCTAssertEqual(r.profile.layers["TRANSFORM"], oldLayer)
        let name = r.profile.buttons["USER"]!.hold_layer!
        XCTAssertNotEqual(name, "TRANSFORM")
        XCTAssertEqual(r.profile.layers[name]?.knobs?["Y_LIFT"]?.param, "Exposure")
        XCTAssertEqual(r.profile.knobs, mine.knobs)
        XCTAssertEqual(r.profile.buttons["VIEWER"], mine.buttons["VIEWER"])
    }
    func testTapTransferKeepsHoldAndCanClearTap() {
        var mine = Profile.loadDefault(), theirs = Profile.loadDefault()
        mine.buttons["USER"] = ButtonBinding(action: "Undo", hold_action: "Redo", release_action: "Before")
        theirs.buttons["USER"] = ButtonBinding()
        let r = MapTransfer.merge(source: theirs, into: mine, selection: .init(controls: ["USER"], slice: .tap))
        XCTAssertNil(r.profile.buttons["USER"]?.action)
        XCTAssertEqual(r.profile.buttons["USER"]?.hold_action, "Redo")
        XCTAssertEqual(r.profile.buttons["USER"]?.release_action, "Before")
    }
    func testPartialKnobsAndCombinationsPreserveEverythingElse() {
        let mine = Profile.loadDefault()
        var theirs = mine; theirs.knobs["SAT"] = KnobBinding(param: "Tint")
        let combo = ButtonCombination(held: ["USER"], trigger: "PRESS_SAT", binding: ButtonBinding(action: "Undo"))
        theirs.combinations = [combo]
        let r = MapTransfer.merge(source: theirs, into: mine, selection: .init(controls: ["SAT"], combinations: [combo.id]))
        XCTAssertEqual(r.profile.knobs["SAT"]?.param, "Tint")
        XCTAssertEqual(r.profile.knobs["Y_LIFT"], mine.knobs["Y_LIFT"])
        XCTAssertEqual(r.profile.combinations?.count, ButtonCombination.defaults.count + 1)
        XCTAssertEqual(r.profile.buttons, mine.buttons)
        XCTAssertEqual(MapTransfer.merge(source: theirs, into: mine, selection: .init()).profile, mine)
    }
    func testPressHoldRetainsImplicitResetAndCyclesTerminate() {
        var source = Profile.loadDefault()
        source.buttons["PRESS_SAT"] = ButtonBinding(hold_layer: "CYCLE")
        source.layers["CYCLE"] = LayerSpec(buttons: ["USER": ButtonBinding(layer: "CYCLE")])
        let r = MapTransfer.merge(source: source, into: Profile.loadDefault(), selection: .init(controls: ["PRESS_SAT"], slice: .hold))
        XCTAssertEqual(r.profile.buttons["PRESS_SAT"]?.action, "reset_knob:SAT")
        let id = r.profile.buttons["PRESS_SAT"]!.hold_layer!
        XCTAssertEqual(r.profile.layers[id]?.buttons?["USER"]?.layer, id)
    }
    func testRewindMigrationChangesOnlyCompleteFactoryRingLayout() {
        let suite = "PanaLux-rewind-layout-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = Profile.loadDefault()
        old.layers["REWIND"]?.rings = ["RING_LIFT": RingBinding(param: RewindCommands.speedFine), "RING_GAMMA": RingBinding(param: RewindCommands.scrub), "RING_GAIN": RingBinding(param: RewindCommands.speed)]
        defaults.set(13, forKey: "profileSchemaVersion")
        var backedUp = false
        let migrated = Profile.migrate(old, factory: Profile.loadDefault(), defaults: defaults) { backedUp = true }
        XCTAssertTrue(backedUp)
        XCTAssertEqual(migrated.layers["REWIND"]?.rings?["RING_GAIN"]?.param, RewindCommands.scrub)
        XCTAssertEqual(migrated.layers["REWIND"]?.rings?["RING_GAMMA"]?.param, RewindCommands.tangents)
        XCTAssertEqual(migrated.layers["REWIND"]?.rings?["RING_LIFT"]?.param, RewindCommands.landmarks)
        old.layers["REWIND"]?.rings?["RING_LIFT"] = RingBinding(param: "Exposure")
        defaults.set(13, forKey: "profileSchemaVersion")
        XCTAssertEqual(Profile.migrate(old, factory: Profile.loadDefault(), defaults: defaults, backup: {}).layers["REWIND"]?.rings, old.layers["REWIND"]?.rings)
    }
    func testTutorialShowsEveryRingAndKeepsOriginals() {
        XCTAssertEqual(IntroRewindDemo.frame(at: 3).rings, [2])
        XCTAssertEqual(IntroRewindDemo.frame(at: 19.5).rings, [1])
        XCTAssertEqual(IntroRewindDemo.frame(at: 25).rings, [0])
        XCTAssertEqual(IntroRewindDemo.frame(at: 28).state.tangentCount, 2)
        XCTAssertGreaterThanOrEqual(IntroRewindDemo.length, 45)
    }
    @MainActor func testLibraryNativeRender() throws {
        guard let folder = ProcessInfo.processInfo.environment["PANALUX_RENDER_DIR"] else { throw XCTSkip("Safe render directory required") }
        var profile = Profile.loadDefault(); profile.buttons["USER"] = ButtonBinding(holdProgram: .focused("Exposure"))
        let view = MapLibraryView(initialSource: SharedMap(name: "Portrait · Soft Light", notes: "Example for visual testing", profile: profile), initialSelection: .init(controls: ["USER", "Y_GAMMA", "CONTRAST"]))
        let host = NSHostingView(rootView: view.frame(width: 1260, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.orderFront(nil); defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2)); host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("map-library.png"))
    }
}
