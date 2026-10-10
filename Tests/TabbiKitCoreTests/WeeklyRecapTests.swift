import XCTest
@testable import TabbiKitCore

final class WeeklyRecapTests: XCTestCase {
    private func calendar(_ zone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// October `day`, 2026 at `hour`:`minute` in `calendar`'s zone. October 5 is a Monday.
    private func date(day: Int, _ hour: Int, _ minute: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func key(_ raw: String) -> PlannerDayKey { PlannerDayKey(rawValue: raw)! }

    private func focus(endingAt end: Date, minutes: Double, source: ModuleID = .focus,
                       outcome: StudyPhaseOutcome? = .completed, friends: Int? = nil) -> ActivityRecord {
        var metadata: [String: String] = [:]
        if let outcome { metadata[ActivityMetadata.outcome] = outcome.rawValue }
        if let friends { metadata[PartySessionCompletion.friendsKey] = String(friends) }
        return ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes, metadata: metadata)
    }

    // MARK: Week boundaries

    func testWeekRunsMondayThroughSundayWhateverTheFirstWeekday() {
        for firstWeekday in [1, 2, 7] {
            let calendar = calendar(firstWeekday: firstWeekday)
            XCTAssertEqual(RecapWeek(containing: date(day: 5, 0, in: calendar), calendar: calendar).start, key("2026-10-05"))
            XCTAssertEqual(RecapWeek(containing: date(day: 11, 23, 59, in: calendar), calendar: calendar).start,
                           key("2026-10-05"))
            XCTAssertEqual(RecapWeek(containing: date(day: 12, 0, in: calendar), calendar: calendar).start,
                           key("2026-10-12"))
        }
    }

    func testWeekDaysAndEnd() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 8, 12, in: calendar), calendar: calendar)
        XCTAssertEqual(week.end(calendar: calendar), key("2026-10-11"))
        XCTAssertEqual(week.days(calendar: calendar).map(\.rawValue),
                       ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"])
        XCTAssertEqual(week.adding(weeks: -1, calendar: calendar).start, key("2026-09-28"))
        XCTAssertEqual(week.adding(weeks: 4, calendar: calendar).start, key("2026-11-02"))
    }

    func testStartMustBeAMonday() {
        let calendar = calendar()
        XCTAssertNotNil(RecapWeek(start: key("2026-10-05"), calendar: calendar))
        XCTAssertNil(RecapWeek(start: key("2026-10-04"), calendar: calendar))
    }

    func testRecapIsReadySundayEvening() {
        let calendar = calendar("America/Los_Angeles")
        let thisWeek = RecapWeek(containing: date(day: 7, 12, in: calendar), calendar: calendar)
        let lastWeek = thisWeek.adding(weeks: -1, calendar: calendar)
        XCTAssertEqual(RecapWeek.latestReady(at: date(day: 7, 12, in: calendar), calendar: calendar), lastWeek)
        XCTAssertEqual(RecapWeek.latestReady(at: date(day: 11, 17, 59, in: calendar), calendar: calendar), lastWeek)
        XCTAssertEqual(RecapWeek.latestReady(at: date(day: 11, 18, in: calendar), calendar: calendar), thisWeek)
        XCTAssertEqual(RecapWeek.latestReady(at: date(day: 12, 9, in: calendar), calendar: calendar), thisWeek)
        XCTAssertEqual(thisWeek.readyDate(calendar: calendar), date(day: 11, 18, in: calendar))
    }

    func testReadyDateAcrossDaylightSavingChange() {
        // Europe moves its clocks back on Sunday, October 25, 2026.
        let calendar = calendar("Europe/Berlin")
        let week = RecapWeek(containing: date(day: 21, 12, in: calendar), calendar: calendar)
        XCTAssertEqual(week.end(calendar: calendar), key("2026-10-25"))
        XCTAssertEqual(calendar.component(.hour, from: week.readyDate(calendar: calendar)), 18)
    }

    func testRecordsCountTowardTheLocalDayTheyEnded() {
        // 23:30 Sunday in Los Angeles is Monday morning in UTC.
        let losAngeles = calendar("America/Los_Angeles")
        let record = focus(endingAt: date(day: 11, 23, 30, in: losAngeles), minutes: 30)
        let week = RecapWeek(containing: date(day: 8, 12, in: losAngeles), calendar: losAngeles)
        XCTAssertEqual(WeeklyRecap(week: week, records: [record], calendar: losAngeles).minutesByDay.last, 30)

        let utc = calendar()
        let utcWeek = RecapWeek(containing: date(day: 8, 12, in: utc), calendar: utc)
        XCTAssertTrue(WeeklyRecap(week: utcWeek, records: [record], calendar: utc).isEmpty)
        XCTAssertEqual(WeeklyRecap(week: utcWeek.adding(weeks: 1, calendar: utc), records: [record], calendar: utc)
            .minutesByDay.first, 30)
    }

    // MARK: Aggregation

    func testAggregatesAWeek() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let records = [
            focus(endingAt: date(day: 5, 10, in: calendar), minutes: 25),
            focus(endingAt: date(day: 5, 11, in: calendar), minutes: 25),
            focus(endingAt: date(day: 6, 10, in: calendar), minutes: 50),
            focus(endingAt: date(day: 6, 12, in: calendar), minutes: 12, outcome: .skipped),
            focus(endingAt: date(day: 9, 10, in: calendar), minutes: 3, outcome: .abandoned),
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: date(day: 7, 9, in: calendar),
                           quantity: 40, unit: .cards),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: date(day: 8, 9, in: calendar), subject: "a"),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: date(day: 8, 10, in: calendar), subject: "a"),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: date(day: 10, 9, in: calendar), subject: "b"),
            ActivityRecord(source: .focus, kind: .breakTaken, start: date(day: 5, 10, in: calendar),
                           end: date(day: 5, 10, 5, in: calendar), quantity: 5, unit: .minutes),
        ]
        let recap = WeeklyRecap(week: week, records: records, calendar: calendar)
        XCTAssertEqual(recap.minutesByDay, [50, 62, 0, 0, 3, 0, 0])
        XCTAssertEqual(recap.focusMinutes, 115)
        XCTAssertEqual(recap.sessions, 3)
        XCTAssertEqual(recap.cardsReviewed, 40)
        XCTAssertEqual(recap.tasksDone, 2)
        // 25+10, 25+10, 50+10, 12 skipped, 3 too short.
        XCTAssertEqual(recap.points, 142)
        // Monday through Thursday: focus, focus, cards, a task. Friday's 3 minutes don't count.
        XCTAssertEqual(recap.longestStreak, 4)
        XCTAssertEqual(recap.bestDay(calendar: calendar)?.day, key("2026-10-06"))
        XCTAssertEqual(recap.bestDay(calendar: calendar)?.minutes, 62)
        XCTAssertFalse(recap.isEmpty)
    }

    func testIgnoresRecordsOutsideTheWeekAndDuplicates() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let inside = focus(endingAt: date(day: 5, 10, in: calendar), minutes: 25)
        let records = [
            inside, inside,
            focus(endingAt: date(day: 4, 23, 59, in: calendar), minutes: 25),
            focus(endingAt: date(day: 12, 0, 1, in: calendar), minutes: 25),
        ]
        let recap = WeeklyRecap(week: week, records: records, calendar: calendar)
        XCTAssertEqual(recap.focusMinutes, 25)
        XCTAssertEqual(recap.sessions, 1)
    }

    func testPartyStaysEarnTheTeamBonus() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let records = [
            focus(endingAt: date(day: 5, 10, in: calendar), minutes: 25, source: .party, friends: 2),
            focus(endingAt: date(day: 6, 10, in: calendar), minutes: 20, source: .party, outcome: .skipped, friends: 2),
        ]
        let recap = WeeklyRecap(week: week, records: records, calendar: calendar)
        XCTAssertEqual(recap.points, PetPointsRules.sharedPoints(forMinutes: 25, friends: 2)
            + PetPointsRules.sharedPoints(forMinutes: 20, friends: 2, finished: false))
        XCTAssertEqual(recap.sessions, 1)
    }

    func testEmptyWeek() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let recap = WeeklyRecap(week: week, records: [], calendar: calendar)
        XCTAssertTrue(recap.isEmpty)
        XCTAssertEqual(recap.minutesByDay, Array(repeating: 0, count: 7))
        XCTAssertEqual(recap.longestStreak, 0)
        XCTAssertNil(recap.bestDay(calendar: calendar))
        XCTAssertEqual(recap.cheer(comparedTo: []), .rest)
    }

    func testStreakCanSpanTheWholeWeek() {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let records = (5...11).map { focus(endingAt: date(day: $0, 9, in: calendar), minutes: 10) }
        XCTAssertEqual(WeeklyRecap(week: week, records: records, calendar: calendar).longestStreak, 7)
    }

    func testDecodesAndClampsSavedRecaps() throws {
        let calendar = calendar()
        let week = RecapWeek(containing: date(day: 5, 12, in: calendar), calendar: calendar)
        let recap = WeeklyRecap(week: week, minutesByDay: [10, -5], sessions: 1, cardsReviewed: 2, tasksDone: 3,
                                points: 4, longestStreak: 9)
        XCTAssertEqual(recap.minutesByDay, [10, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(recap.longestStreak, 7)
        let decoded = try JSONDecoder().decode(WeeklyRecap.self, from: JSONEncoder().encode(recap))
        XCTAssertEqual(decoded, recap)
    }

    // MARK: Cheer

    private func recap(weeksAgo: Int, minutes: Int, cards: Int = 0) -> WeeklyRecap {
        let calendar = Calendar.current
        let week = RecapWeek(containing: Date(), calendar: calendar).adding(weeks: -weeksAgo, calendar: calendar)
        return WeeklyRecap(week: week, minutesByDay: [minutes], sessions: 0, cardsReviewed: cards, tasksDone: 0,
                           points: 0, longestStreak: 0)
    }

    func testCheerIsAlwaysKind() {
        let lastWeek = recap(weeksAgo: 1, minutes: 300)
        let older = recap(weeksAgo: 3, minutes: 600)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 700).cheer(comparedTo: [lastWeek, older]), .bestYet)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 400).cheer(comparedTo: [lastWeek, older]), .moreThanLastWeek)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 200).cheer(comparedTo: [lastWeek, older]), .steady)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 30).cheer(comparedTo: [lastWeek, older]), .light)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 0, cards: 20).cheer(comparedTo: [lastWeek]), .light)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 200).cheer(comparedTo: []), .firstWeek)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 0).cheer(comparedTo: [lastWeek]), .rest)
    }

    func testCheerIgnoresLaterAndEmptyWeeks() {
        let later = recap(weeksAgo: 0, minutes: 900)
        let empty = recap(weeksAgo: 2, minutes: 0)
        XCTAssertEqual(recap(weeksAgo: 1, minutes: 200).cheer(comparedTo: [later, empty]), .firstWeek)
    }

    func testMoreThanLastWeekNeedsTheWeekRightBefore() {
        let twoWeeksAgo = recap(weeksAgo: 2, minutes: 100)
        let older = recap(weeksAgo: 5, minutes: 600)
        XCTAssertEqual(recap(weeksAgo: 0, minutes: 200).cheer(comparedTo: [twoWeeksAgo, older]), .steady)
    }

    func testEveryCheerLineIsWarm() {
        for cheer in RecapCheer.allCases {
            XCTAssertFalse(cheer.line.isEmpty)
        }
    }
}
