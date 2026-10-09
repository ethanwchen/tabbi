import XCTest
@testable import TabbiKitCore

final class WidgetStateActivityTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-`day` at `hour`:00 UTC.
    private func date(_ hour: Int, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func key(_ day: Int) -> PlannerDayKey {
        PlannerDayKey(date: date(12, day: day), calendar: calendar)
    }

    private func focus(_ minutes: Double, endingAt end: Date, outcome: String = "completed",
                       kind: ActivityKind = .focusCompleted) -> ActivityRecord {
        ActivityRecord(source: .focus, kind: kind, start: end.addingTimeInterval(-minutes * 60), end: end,
                       quantity: minutes, unit: .minutes, metadata: [ActivityMetadata.outcome: outcome])
    }

    func testFocusMinutesCountStoppedStretchesButNotBreaksOrCards() {
        let records = [
            focus(25, endingAt: date(9)),
            focus(12.6, endingAt: date(10), outcome: "abandoned"),
            focus(5, endingAt: date(10), kind: .breakTaken),
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: date(11), quantity: 40, unit: .cards),
        ]
        XCTAssertEqual(WidgetState.focusMinutes(in: records), 37)
    }

    func testFocusDaysWalkBackUntilTheFirstGap() {
        // Focus on the 5th, then the 7th through the 9th; nothing on the 6th.
        var reads: [PlannerDayKey] = []
        let byDay: [PlannerDayKey: [ActivityRecord]] = [
            key(9): [focus(25, endingAt: date(9, day: 9))],
            key(8): [focus(5, endingAt: date(9, day: 8), kind: .breakTaken), focus(30, endingAt: date(10, day: 8))],
            key(7): [focus(25, endingAt: date(9, day: 7))],
            key(5): [focus(25, endingAt: date(9, day: 5))],
        ]
        let days = WidgetState.focusDays(endingOn: key(9), calendar: calendar) { day in
            reads.append(day)
            return byDay[day] ?? []
        }
        XCTAssertEqual(days, [key(7), key(8), key(9)])
        XCTAssertEqual(reads, [key(9), key(8), key(7), key(6)], "stops at the gap, never reads the 5th")
    }

    func testFocusDaysKeepYesterdaysStreakBeforeTodaysFirstSession() {
        let byDay = [key(8): [focus(25, endingAt: date(9, day: 8))], key(7): [focus(25, endingAt: date(9, day: 7))]]
        let days = WidgetState.focusDays(endingOn: key(9), calendar: calendar) { byDay[$0] ?? [] }
        XCTAssertEqual(days, [key(7), key(8)])
        let state = WidgetState(pet: .starter(.cat), timer: nil, todayRecords: [], focusDays: days,
                                now: date(8), calendar: calendar)
        XCTAssertEqual(state.streak(at: date(8), calendar: calendar), 2)
        XCTAssertEqual(state.minutes(at: date(8), calendar: calendar), 0)
    }

    func testFocusDaysAreEmptyWithoutFocusTodayOrYesterday() {
        let byDay = [key(7): [focus(25, endingAt: date(9, day: 7))]]
        XCTAssertEqual(WidgetState.focusDays(endingOn: key(9), calendar: calendar) { byDay[$0] ?? [] }, [])
    }

    func testStateFromTheAppsSourcesShowsTheRunningClock() {
        let now = date(15)
        let end = now.addingTimeInterval(600)
        let clock = ProvidedFocus(source: .focus, phase: .focus, label: "Focus", clock: .countdown(endsAt: end),
                                  phaseLength: 1500)
        let today = [focus(50, endingAt: date(10))]
        let state = WidgetState(pet: .starter(.dog), timer: WidgetState.Timer(clock), todayRecords: today, focusDays: [key(8), key(9)],
                                now: now, calendar: calendar)
        XCTAssertEqual(state.pet, .starter(.dog))
        XCTAssertEqual(state.day, key(9))
        XCTAssertEqual(state.focusMinutes, 50)
        XCTAssertEqual(state.streakDays, 2)
        XCTAssertEqual(state.lastFocusDay, key(9))
        XCTAssertEqual(state.timer?.clock, .countdown(endsAt: end))
    }
}
