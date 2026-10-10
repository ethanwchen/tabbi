import XCTest
import TabbiKitCore

final class MeetingNudgeTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ id: String, startsIn minutes: Double, allDay: Bool = false) -> UpcomingEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return UpcomingEvent(id: id, title: id, start: start, end: start.addingTimeInterval(30 * 60), isAllDay: allDay)
    }

    func testAMeetingNudgesOnceWhenItComesWithinFiveMinutes() {
        var watch = MeetingNudgeWatch()
        let sources = TickerSources(events: [event("standup", startsIn: 10)])
        XCTAssertNil(watch.nudge(for: sources, at: now), "ten minutes out is too early")
        let fiveBefore = now.addingTimeInterval(5 * 60)
        let nudge = watch.nudge(for: sources, at: fiveBefore)
        XCTAssertEqual(nudge?.startedAt, fiveBefore)
        XCTAssertNil(watch.nudge(for: sources, at: fiveBefore.addingTimeInterval(30)), "at most once per meeting")
        XCTAssertNil(watch.nudge(for: sources, at: fiveBefore.addingTimeInterval(4 * 60)))
    }

    func testTheNudgeIsBriefAndEndsOnItsOwn() {
        let nudge = MeetingNudge(key: "standup", startedAt: now)
        XCTAssertTrue(nudge.isShowing(at: now))
        XCTAssertTrue(nudge.isShowing(at: now.addingTimeInterval(MeetingNudge.duration - 0.1)))
        XCTAssertFalse(nudge.isShowing(at: nudge.endsAt))
        XCTAssertFalse(nudge.isShowing(at: now.addingTimeInterval(-1)), "a clock set back shows nothing")
    }

    func testMeetingsUnderWayOrAllDayNeverNudge() {
        var watch = MeetingNudgeWatch()
        let sources = TickerSources(events: [event("review", startsIn: -5), event("holiday", startsIn: 3, allDay: true)])
        XCTAssertNil(watch.nudge(for: sources, at: now))
    }

    func testBackToBackMeetingsEachGetTheirOwnNudge() {
        var watch = MeetingNudgeWatch()
        let sources = TickerSources(events: [event("standup", startsIn: 3), event("review", startsIn: 33)])
        let first = watch.nudge(for: sources, at: now)
        XCTAssertNotNil(first)
        let second = watch.nudge(for: sources, at: now.addingTimeInterval(30 * 60))
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first?.key, second?.key)
    }

    func testAMovedMeetingNudgesAgain() {
        var watch = MeetingNudgeWatch()
        XCTAssertNotNil(watch.nudge(for: TickerSources(events: [event("standup", startsIn: 3)]), at: now))
        let moved = TickerSources(events: [event("standup", startsIn: 13)])
        XCTAssertNotNil(watch.nudge(for: moved, at: now.addingTimeInterval(10 * 60)))
    }
}
