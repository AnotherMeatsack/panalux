import XCTest
@testable import PanaLux

final class FeatureWalkthroughTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults { UserDefaults(suiteName: "PanaLux.FeatureWalkthroughTests." + UUID().uuidString)! }

    func testNewUserAndSameMarketingVersionNewBuildArePending() {
        let defaults = isolatedDefaults()
        let old = FeatureWalkthroughController(defaults: defaults, build: "202609201752")
        old.presentAutomatically()
        XCTAssertEqual(old.index, 0)
        for i in 1..<old.manifest.steps.count { old.move(i) }
        old.done()
        XCTAssertFalse(old.pending)
        let next = FeatureWalkthroughController(defaults: defaults, build: "202609201900")
        XCTAssertTrue(next.pending)
        next.presentAutomatically()
        XCTAssertEqual(next.index, 0)
    }

    func testLaterAndRestartResumeWithoutCompleting() {
        let defaults = isolatedDefaults()
        let first = FeatureWalkthroughController(defaults: defaults, build: "test")
        first.presentAutomatically(); first.move(1); first.move(2); first.later()
        XCTAssertTrue(first.pending)
        XCTAssertFalse(first.progress.completed)
        let restart = FeatureWalkthroughController(defaults: defaults, build: "test")
        restart.presentAutomatically()
        XCTAssertEqual(restart.index, 2)
        restart.done()
        XCTAssertFalse(restart.progress.completed)
        XCTAssertEqual(restart.index, 2)
    }

    func testEachNextThenExplicitDoneRequiredAndCompletionDoesNotNag() {
        let defaults = isolatedDefaults()
        let tour = FeatureWalkthroughController(defaults: defaults, build: "test")
        tour.presentAutomatically()
        tour.move(tour.manifest.steps.count - 1)
        XCTAssertEqual(tour.index, 0, "Cannot silently skip straight to completion")
        for i in 1..<tour.manifest.steps.count { tour.move(i) }
        XCTAssertFalse(tour.progress.completed)
        tour.done()
        XCTAssertNil(tour.index)
        let restart = FeatureWalkthroughController(defaults: defaults, build: "test")
        restart.presentAutomatically()
        XCTAssertNil(restart.index)
        XCTAssertFalse(restart.pending)
    }

    func testReplayAndHandsOnContinuationDoNotEraseCompletedState() {
        let defaults = isolatedDefaults()
        let tour = FeatureWalkthroughController(defaults: defaults, build: "test")
        tour.presentAutomatically()
        for i in 1..<tour.manifest.steps.count { tour.move(i) }
        tour.done()
        var continued = false
        tour.replay { continued = true }
        XCTAssertEqual(tour.index, 0)
        tour.move(1);tour.later()
        XCTAssertFalse(continued)
        XCTAssertTrue(tour.progress.completed)
        tour.replay { continued = true }
        for i in 1..<tour.manifest.steps.count { tour.move(i) }
        tour.done()
        XCTAssertTrue(continued)
    }

    func testManifestCoversRealTargetsAndDiscovery() {
        let m = FeatureWalkthroughManifest.current
        XCTAssertEqual(Set(m.steps.map(\.id)).count, m.steps.count)
        XCTAssertEqual(Set(m.steps.map(\.target)), Set(["launcher","chord","map","gestures","zoom","print","png","replay"]))
        XCTAssertTrue(m.steps.contains { $0.body.contains("Release either key") })
        XCTAssertTrue(m.steps.contains { $0.body.contains("Save as PDF") })
        XCTAssertTrue(m.steps.contains { $0.body.contains("Help →") })
    }
}
