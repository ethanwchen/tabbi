import XCTest
@testable import TabbiKitCore

final class RecapStatsTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func week(_ raw: String) -> RecapWeek { RecapWeek(start: PlannerDayKey(rawValue: raw)!, calendar: calendar)! }

    func testHeavyWeekShowsEveryStatInOrder() {
        let recap = WeeklyRecap(week: week("2026-10-05"), minutesByDay: [100, 125, 75, 150, 100, 50, 75],
                                sessions: 27, cardsReviewed: 1_320, tasksDone: 17, points: 1_240, longestStreak: 7)
        let stats = recap.stats(calendar: calendar, locale: locale)
        XCTAssertEqual(stats.map(\.kind), [.sessions, .bestDay, .streak, .cards, .tasks, .points])
        XCTAssertEqual(stats.map(\.value), ["27", "Thu", "7", "1,320", "17", "1,240"])
        XCTAssertEqual(stats.map(\.label), ["sessions", "best day", "day streak", "cards", "tasks", "points"])
    }

    func testLightWeekLeavesOutWhatItDidNotHave() {
        let recap = WeeklyRecap(week: week("2026-10-05"), minutesByDay: [0, 0, 0, 0, 0, 25, 0],
                                sessions: 1, cardsReviewed: 0, tasksDone: 1, points: 0, longestStreak: 1)
        let stats = recap.stats(calendar: calendar, locale: locale)
        // No zero counts and no one-day "streak".
        XCTAssertEqual(stats.map(\.kind), [.sessions, .bestDay, .tasks])
        XCTAssertEqual(stats.map(\.label), ["session", "best day", "task"])
        XCTAssertEqual(stats[1].value, "Sat")
    }

    func testWeekWithoutFocusHasNoBestDay() {
        let recap = WeeklyRecap(week: week("2026-10-05"), minutesByDay: Array(repeating: 0, count: 7),
                                sessions: 0, cardsReviewed: 40, tasksDone: 0, points: 0, longestStreak: 3)
        XCTAssertEqual(recap.stats(calendar: calendar, locale: locale).map(\.kind), [.streak, .cards])
    }

    func testTitleNamesTheMonthOnceOrTwice() {
        XCTAssertEqual(week("2026-10-05").title(calendar: calendar, locale: locale), "Oct 5 - 11")
        XCTAssertEqual(week("2026-09-28").title(calendar: calendar, locale: locale), "Sep 28 - Oct 4")
        XCTAssertEqual(week("2026-12-28").title(calendar: calendar, locale: locale), "Dec 28 - Jan 3")
    }

    func testDayInitialsStartOnMondayWhateverTheFirstWeekday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(RecapWeek.dayInitials(calendar: sundayFirst, locale: locale), ["M", "T", "W", "T", "F", "S", "S"])
    }
}
