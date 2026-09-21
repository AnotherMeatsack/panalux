import XCTest
@testable import PanaLux

final class FeatureWalkthroughTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "PanaLux.WhatsNewTests." + UUID().uuidString)! }
    private func step(_ id: String, _ since: String) -> FeatureWalkthroughManifest.Step {
        .init(id: id, title: id, body: id, since: since, kind: "new", target: "map", action: nil)
    }
    private func manifest() -> FeatureWalkthroughManifest {
        .init(version: "1.2.7", revision: "t", changelogHeadings: [],
              steps: [step("a", "1.2.4"), step("b", "1.2.5"), step("c", "1.2.6"), step("d", "1.2.7")])
    }
    private func controller(_ d: UserDefaults, current: String = "1.2.7") -> WhatsNewController {
        WhatsNewController(defaults: d, currentVersion: current, manifest: manifest())
    }

    func testVersionOrderingIsNumeric() {
        XCTAssertTrue(AppVersion("1.2.9")! < AppVersion("1.2.10")!)
        XCTAssertTrue(AppVersion("1.9")! < AppVersion("1.10.0")!)
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
    }

    func testOneVersionBehindSeesOnlyTheLatestChanges() {
        let d = defaults()
        d.set("1.2.6", forKey: "whatsNew.lastSeenVersion")
        let c = controller(d)
        c.presentAfterUpdate(onboarded: true)
        XCTAssertEqual(c.items.map(\.id), ["d"])
    }

    func testSomeoneWhoSkippedSeesEverythingTheyMissed() {
        let d = defaults()
        d.set("1.2.4", forKey: "whatsNew.lastSeenVersion")
        let c = controller(d)
        c.presentAfterUpdate(onboarded: true)
        XCTAssertEqual(c.items.map(\.id), ["b", "c", "d"])
        XCTAssertTrue(c.showingChangelog)
    }

    func testShownOnceThenNeverAgainOnSameVersion() {
        let d = defaults()
        d.set("1.2.6", forKey: "whatsNew.lastSeenVersion")
        let first = controller(d)
        first.presentAfterUpdate(onboarded: true)
        XCTAssertTrue(first.showingChangelog)
        let relaunch = controller(d)
        relaunch.presentAfterUpdate(onboarded: true)
        XCTAssertFalse(relaunch.showingChangelog)
    }

    func testNewInstallSeesNothingAndIsMarkedCurrent() {
        let d = defaults()
        let c = controller(d)
        c.presentAfterUpdate(onboarded: false)
        XCTAssertFalse(c.showingChangelog)
        XCTAssertEqual(d.string(forKey: "whatsNew.lastSeenVersion"), "1.2.7")
    }

    func testLegacyCompletedWalkthroughSetsTheBaseline() {
        let d = defaults()
        d.set(true, forKey: "featureWalkthrough.1.2.5:202609200000:rev.completed")
        let c = controller(d)
        c.presentAfterUpdate(onboarded: true)
        XCTAssertEqual(c.items.map(\.id), ["c", "d"])
    }

    func testClosingTheChangelogStartsTheSpotlightAndSkipDoesNot() {
        let d = defaults()
        d.set("1.2.5", forKey: "whatsNew.lastSeenVersion")
        let c = controller(d)
        c.presentAfterUpdate(onboarded: true)
        c.closeChangelog()
        XCTAssertEqual(c.spotlightIndex, 0)
        c.move(1); c.move(1)
        XCTAssertNil(c.spotlightIndex, "Stepping past the last item finishes")
        c.replay()
        c.closeChangelog(showMeWhere: false)
        XCTAssertNil(c.spotlightIndex)
    }

    func testShippedManifestUsesRealTargetsAndVersions() {
        let m = FeatureWalkthroughManifest.current
        XCTAssertEqual(Set(m.steps.map(\.id)).count, m.steps.count)
        XCTAssertTrue(Set(m.steps.map(\.target)).isSubset(of: ["guide", "help", "settings", "map", "inspector"]))
        XCTAssertTrue(m.steps.allSatisfy { AppVersion($0.since) != nil && ["new", "updated"].contains($0.kind) })
        XCTAssertTrue(m.steps.contains { $0.id == "contact" && $0.body.contains("panalux@icloud.com") })
    }
}
