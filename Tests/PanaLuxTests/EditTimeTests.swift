import XCTest
@testable import PanaLux

final class EditTimeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testWallClockFollowsTrailTimeWithinASession() {
        var trail = EditTrail(photoID: "p", now: start)
        _ = trail.record(param: "Exposure", value: 0.6, at: 42)
        XCTAssertEqual(trail.wallClock(at: 42), start.addingTimeInterval(42))
    }

    func testResumedSessionKeepsEachEditsOwnRealTime() {
        var trail = EditTrail(photoID: "p", now: start)
        _ = trail.record(param: "Exposure", value: 0.6, at: 10)
        // PanaLux was closed for three hours, then the photo came back.
        let later = start.addingTimeInterval(3 * 3600)
        trail.resume(at: later)
        let resumedT = trail.time(at: later.addingTimeInterval(5))
        XCTAssertEqual(trail.wallClock(at: 10), start.addingTimeInterval(10), "The first session's edit is still at its real time")
        XCTAssertEqual(trail.wallClock(at: resumedT)!.timeIntervalSince1970, later.addingTimeInterval(5).timeIntervalSince1970, accuracy: 0.001)
    }

    func testTrailWithoutAClockAdmitsItDoesNotKnow() {
        var trail = EditTrail(photoID: "p", now: start)
        trail.branches[0].sessions = nil
        XCTAssertNil(trail.wallClock(at: 5))
    }

    func testEditTimeReadsAsTodayYesterdayOrDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))!
        let today = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 9, minute: 5, second: 7))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 5, second: 7))!
        let older = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9, minute: 5, second: 7))!
        XCTAssertFalse(RewindEngine.editTime(today, now: now, calendar: cal).contains("Yesterday"))
        XCTAssertTrue(RewindEngine.editTime(yesterday, now: now, calendar: cal).hasPrefix("Yesterday "))
        XCTAssertTrue(RewindEngine.editTime(older, now: now, calendar: cal).contains("Sep"))
    }
}
