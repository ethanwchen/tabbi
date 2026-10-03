import XCTest
import NotchKitCore

final class PartyPresenceTrackerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// 2026-10-02 09:00 in New York.
    private lazy var morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!

    private func running(_ start: Date, focus: TimeInterval = 25 * 60, rest: TimeInterval = 5 * 60) -> FocusTimer {
        var timer = FocusTimer(config: FocusTimerConfig(focusDuration: focus, restDuration: rest))
        timer.start(at: start)
        return timer
    }

    func testIdleWithoutATimer() {
        var tracker = PartyPresenceTracker()
        XCTAssertTrue(tracker.observe(nil, at: morning, calendar: calendar), "the heartbeat at launch")
        XCTAssertFalse(tracker.observe(nil, at: morning.addingTimeInterval(60), calendar: calendar))
        let beat = tracker.heartbeat(at: morning, calendar: calendar)
        XCTAssertEqual(beat.status, .idle)
        XCTAssertNil(beat.method)
        XCTAssertNil(beat.phaseEndsAt)
        XCTAssertEqual(beat.sessionMinutes, 0)
        XCTAssertEqual(beat.todayMinutes, 0)
        XCTAssertEqual(beat.streakDays, 0)
        XCTAssertEqual(beat.day, "2026-10-02")
    }

    func testRunningFocusIsStudyingWithMethodAndPhaseEnd() {
        var tracker = PartyPresenceTracker(method: "52-17")
        XCTAssertTrue(tracker.observe(running(morning), at: morning, calendar: calendar))
        let beat = tracker.heartbeat(at: morning, calendar: calendar)
        XCTAssertEqual(beat.status, .studying)
        XCTAssertEqual(beat.method, "52-17")
        XCTAssertEqual(beat.phaseEndsAt, morning.addingTimeInterval(25 * 60))
    }

    func testBreakAndPauseAreBreaks() {
        var tracker = PartyPresenceTracker()
        var timer = running(morning)
        timer.pause(at: morning.addingTimeInterval(60))
        tracker.observe(timer, at: morning.addingTimeInterval(60), calendar: calendar)
        XCTAssertEqual(tracker.status, .onBreak)
        XCTAssertNil(tracker.heartbeat(at: morning.addingTimeInterval(60), calendar: calendar).phaseEndsAt)

        let breakTime = morning.addingTimeInterval(26 * 60)
        tracker.observe(running(morning), at: breakTime, calendar: calendar)
        let beat = tracker.heartbeat(at: breakTime, calendar: calendar)
        XCTAssertEqual(beat.status, .onBreak)
        XCTAssertEqual(beat.method, "pomodoro")
        XCTAssertEqual(beat.phaseEndsAt, morning.addingTimeInterval(30 * 60))
    }

    func testOnlyStatusMethodOrPhaseChangesAskForAnImmediateHeartbeat() {
        var tracker = PartyPresenceTracker()
        let timer = running(morning)
        XCTAssertTrue(tracker.observe(timer, at: morning, calendar: calendar))
        // Ticks of the same phase only grow counters.
        XCTAssertFalse(tracker.observe(timer, at: morning.addingTimeInterval(60), calendar: calendar))
        XCTAssertFalse(tracker.observe(timer, at: morning.addingTimeInterval(120), calendar: calendar))
        // The focus phase rolling into the break is a status change.
        XCTAssertTrue(tracker.observe(timer, at: morning.addingTimeInterval(25 * 60 + 1), calendar: calendar))
        // Changing the method while on a break is reported too.
        tracker.method = "flowtime"
        XCTAssertTrue(tracker.observe(timer, at: morning.addingTimeInterval(26 * 60), calendar: calendar))
    }

    func testMinutesCountOnlyRunningFocusClippedToThePhaseEnd() {
        var tracker = PartyPresenceTracker()
        tracker.observe(running(morning), at: morning, calendar: calendar)
        // The Mac slept through the focus phase and the whole break.
        let later = morning.addingTimeInterval(3 * 3600)
        tracker.observe(running(morning), at: later, calendar: calendar)
        let beat = tracker.heartbeat(at: later, calendar: calendar)
        XCTAssertEqual(beat.status, .idle)
        XCTAssertEqual(beat.todayMinutes, 25)
        // The session ended, so its counter resets.
        XCTAssertEqual(beat.sessionMinutes, 0)
        XCTAssertEqual(tracker.todayMinutes(at: later, calendar: calendar), 25)
    }

    func testSessionMinutesAccumulateAcrossFocusPhasesAndPausesDoNotCount() {
        var tracker = PartyPresenceTracker()
        var timer = running(morning, focus: 10 * 60, rest: 2 * 60)
        tracker.observe(timer, at: morning, calendar: calendar)
        let pausedAt = morning.addingTimeInterval(4 * 60)
        timer.pause(at: pausedAt)
        tracker.observe(timer, at: pausedAt, calendar: calendar)
        let resumedAt = pausedAt.addingTimeInterval(30 * 60)
        timer.start(at: resumedAt)
        tracker.observe(timer, at: resumedAt, calendar: calendar)
        let beat = tracker.heartbeat(at: resumedAt.addingTimeInterval(3 * 60), calendar: calendar)
        XCTAssertEqual(beat.status, .studying)
        XCTAssertEqual(beat.sessionMinutes, 7)
        XCTAssertEqual(beat.todayMinutes, 7)
    }

    func testMinutesSplitAtLocalMidnightAndStreakGrows() {
        var tracker = PartyPresenceTracker()
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 23, minute: 50))!
        tracker.observe(running(lateNight), at: lateNight, calendar: calendar)
        let afterMidnight = lateNight.addingTimeInterval(25 * 60)
        let beat = tracker.heartbeat(at: afterMidnight, calendar: calendar)
        XCTAssertEqual(beat.day, "2026-10-03")
        XCTAssertEqual(beat.todayMinutes, 15)
        XCTAssertEqual(beat.sessionMinutes, 25)
        XCTAssertEqual(beat.streakDays, 2)
    }

    func testStreakSurvivesTheNextDayAndBreaksAfterAMissedDay() {
        var tracker = PartyPresenceTracker()
        tracker.observe(running(morning), at: morning, calendar: calendar)
        tracker.observe(nil, at: morning.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(tracker.streakDays(at: morning, calendar: calendar), 1)

        let nextDay = morning.addingTimeInterval(86_400)
        let beat = tracker.heartbeat(at: nextDay, calendar: calendar)
        XCTAssertEqual(beat.streakDays, 1)
        XCTAssertEqual(beat.todayMinutes, 0, "yesterday's minutes are not today's")

        tracker.observe(running(nextDay), at: nextDay, calendar: calendar)
        tracker.observe(nil, at: nextDay.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(tracker.streakDays(at: nextDay, calendar: calendar), 2)

        XCTAssertEqual(tracker.streakDays(at: nextDay.addingTimeInterval(2 * 86_400), calendar: calendar), 0)
        let comeback = nextDay.addingTimeInterval(2 * 86_400)
        tracker.observe(running(comeback), at: comeback, calendar: calendar)
        XCTAssertEqual(tracker.heartbeat(at: comeback.addingTimeInterval(60), calendar: calendar).streakDays, 1)
    }

    func testInvisibleSendsOfflineAndKeepsCountingLocally() {
        var tracker = PartyPresenceTracker()
        tracker.observe(running(morning), at: morning, calendar: calendar)
        XCTAssertTrue(tracker.setInvisible(true))
        XCTAssertFalse(tracker.setInvisible(true))
        // Phase changes while invisible are not worth a heartbeat.
        XCTAssertFalse(tracker.observe(running(morning), at: morning.addingTimeInterval(26 * 60), calendar: calendar))
        XCTAssertEqual(tracker.heartbeat(at: morning.addingTimeInterval(26 * 60), calendar: calendar), .offline)
        XCTAssertEqual(tracker.todayMinutes(at: morning.addingTimeInterval(26 * 60), calendar: calendar), 25)

        XCTAssertTrue(tracker.setInvisible(false))
        XCTAssertEqual(tracker.heartbeat(at: morning.addingTimeInterval(27 * 60), calendar: calendar).status, .onBreak)
    }

    func testRoundTripsThroughCodableToPersistAcrossLaunches() throws {
        var tracker = PartyPresenceTracker(method: "anki")
        tracker.observe(running(morning), at: morning, calendar: calendar)
        tracker.observe(nil, at: morning.addingTimeInterval(10 * 60), calendar: calendar)
        let restored = try JSONDecoder().decode(
            PartyPresenceTracker.self, from: JSONEncoder().encode(tracker)
        )
        XCTAssertEqual(restored, tracker)
        XCTAssertEqual(restored.todayMinutes(at: morning.addingTimeInterval(3600), calendar: calendar), 10)
    }

    func testHeartbeatBodyNeverMentionsWhatIsStudied() throws {
        var tracker = PartyPresenceTracker()
        tracker.observe(running(morning), at: morning, calendar: calendar)
        let body = try PartyClient.makeEncoder().encode(tracker.heartbeat(at: morning, calendar: calendar))
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any]).keys
        XCTAssertEqual(
            Set(keys),
            ["status", "method", "phaseEndsAt", "sessionMinutes", "todayMinutes", "streakDays", "day"]
        )
    }

    func testDayStringUsesTheLocalCalendar() {
        let utcNextDay = Date(timeIntervalSince1970: 1_790_998_200) // 2026-10-03 03:30 UTC
        XCTAssertEqual(PartyPresenceTracker.dayString(utcNextDay, calendar: calendar), "2026-10-02")
    }
}
