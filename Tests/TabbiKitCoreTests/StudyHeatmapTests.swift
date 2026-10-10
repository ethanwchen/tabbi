import XCTest
@testable import TabbiKitCore

final class StudyHeatmapTests: XCTestCase {
    private func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func key(_ raw: String) -> PlannerDayKey { PlannerDayKey(rawValue: raw)! }

    /// Tuesday, October 7, 2025, mid-afternoon in New York.
    private func tuesday(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 10, day: 7, hour: 15))!
    }

    // MARK: Levels

    func testLevelsFollowStudyMinuteThresholds() {
        XCTAssertEqual([0, 1, 14, 15, 44, 45, 89, 90, 600].map(StudyHeatmap.level(forMinutes:)),
                       [0, 1, 1, 2, 2, 3, 3, 4, 4])
        XCTAssertEqual(StudyHeatmap.level(forMinutes: -5), 0)
        XCTAssertEqual(StudyHeatmap.levelCount, 5)
    }

    // MARK: Grid

    func testWeeksAreColumnsFromTheFirstWeekdayEndingWithToday() {
        let calendar = calendar()
        let heatmap = StudyHeatmap(minutesByDay: [:], weeks: 3, today: tuesday(in: calendar), calendar: calendar)
        XCTAssertEqual(heatmap.weeks.map(\.start), [key("2025-09-21"), key("2025-09-28"), key("2025-10-05")])
        XCTAssertTrue(heatmap.weeks.allSatisfy { $0.days.count == 7 })
        // Sunday, Monday, Tuesday so far; the rest of the week is still to come.
        let current = heatmap.weeks.last!.days
        XCTAssertEqual(current.compactMap { $0?.key }, [key("2025-10-05"), key("2025-10-06"), key("2025-10-07")])
        XCTAssertEqual(current.suffix(4).filter { $0 == nil }.count, 4)
        XCTAssertEqual(current.compactMap { $0 }.filter(\.isToday).map(\.key), [key("2025-10-07")])
        XCTAssertEqual(heatmap.today, key("2025-10-07"))
    }

    func testWeeksFollowTheLocalesFirstWeekday() {
        let calendar = calendar(firstWeekday: 2)
        let heatmap = StudyHeatmap(minutesByDay: [:], weeks: 1, today: tuesday(in: calendar), calendar: calendar)
        XCTAssertEqual(heatmap.weeks.map(\.start), [key("2025-10-06")])
        XCTAssertEqual(heatmap.weeks[0].days.compactMap { $0?.key }, [key("2025-10-06"), key("2025-10-07")])
    }

    func testAlwaysShowsTheCurrentWeek() {
        let calendar = calendar()
        let heatmap = StudyHeatmap(minutesByDay: [:], weeks: 0, today: tuesday(in: calendar), calendar: calendar)
        XCTAssertEqual(heatmap.weeks.count, 1)
    }

    func testDaysCarryRoundedMinutesAndIgnoreTheFuture() {
        let calendar = calendar()
        let heatmap = StudyHeatmap(
            minutesByDay: [key("2025-10-06"): 84.6, key("2025-10-07"): 0.4, key("2025-10-08"): 300,
                           key("2025-10-05"): .nan],
            weeks: 1, today: tuesday(in: calendar), calendar: calendar
        )
        let days = heatmap.weeks[0].days.compactMap { $0 }
        XCTAssertEqual(days.map(\.minutes), [0, 85, 0])
        XCTAssertEqual(days.map(\.level), [0, 3, 0])
        XCTAssertEqual(heatmap.weeks[0].minutes, 85)
        XCTAssertEqual(heatmap.weeks[0].studiedDays, 1)
        XCTAssertEqual(heatmap.bestDay?.key, key("2025-10-06"))
    }

    // MARK: Summary

    func testSummaryCountsTheLastThirtyDaysAndTheBestDayEver() {
        let calendar = calendar()
        let heatmap = StudyHeatmap(
            minutesByDay: [
                key("2025-10-07"): 30, // today
                key("2025-09-08"): 20, // 29 days ago, the window's first day
                key("2025-09-07"): 40, // 30 days ago, outside the window
                key("2025-05-01"): 130, // months ago, still the best day
                key("2025-06-01"): 130, // a tie: the later one wins
            ],
            weeks: 2, today: tuesday(in: calendar), calendar: calendar
        )
        XCTAssertEqual(heatmap.lastThirtyDaysMinutes, 50)
        XCTAssertEqual(heatmap.bestDay?.key, key("2025-06-01"))
        XCTAssertEqual(heatmap.bestDay?.minutes, 130)
        XCTAssertFalse(heatmap.bestDay?.isToday ?? true)
    }

    func testNoStudyHasNoBestDay() {
        let calendar = calendar()
        let heatmap = StudyHeatmap(minutesByDay: [key("2025-10-07"): 0], weeks: 4,
                                   today: tuesday(in: calendar), calendar: calendar)
        XCTAssertNil(heatmap.bestDay)
        XCTAssertEqual(heatmap.lastThirtyDaysMinutes, 0)
        XCTAssertTrue(heatmap.weeks.allSatisfy { $0.days.allSatisfy { ($0?.level ?? 0) == 0 } })
    }

    func testStudiedLabelGivesTheExactTime() {
        let day = { StudyHeatmap.Day(key: self.key("2025-10-07"), minutes: $0, isToday: false).studiedLabel }
        XCTAssertEqual(day(0), "No study")
        XCTAssertEqual(day(25), "25 min studied")
        XCTAssertEqual(day(85), "1h 25m studied")
    }

    // MARK: Demo

    func testDemoHistoryFillsMonthsWithEveryLevelAndAStudiedToday() {
        let calendar = calendar()
        let today = tuesday(in: calendar)
        let demo = PetMilestoneProgress.demo(today: today, calendar: calendar)
        let heatmap = StudyHeatmap(minutesByDay: demo.minutesByDay, weeks: 26, today: today, calendar: calendar)
        let days = heatmap.weeks.flatMap { $0.days.compactMap { $0 } }
        XCTAssertEqual(Set(days.map(\.level)), Set(0..<StudyHeatmap.levelCount))
        XCTAssertGreaterThan(days.filter { $0.minutes > 0 }.count, 50)
        XCTAssertGreaterThan(days.last?.minutes ?? 0, 0)
        XCTAssertEqual(heatmap.bestDay?.minutes, 120)
    }
}
