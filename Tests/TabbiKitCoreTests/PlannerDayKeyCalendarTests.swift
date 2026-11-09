import XCTest
@testable import TabbiKitCore

/// Day keys under the calendars macOS lets a user pick. A key holds the
/// year, month and day in the calendar it was made with, and some of those
/// are not Gregorian dates (Heshvan 29 is "5787-02-29"); stepping from such a
/// day used to trap, which took the widget's timeline down with it.
final class PlannerDayKeyCalendarTests: XCTestCase {
    private static let identifiers: [Calendar.Identifier] = [
        .gregorian, .hebrew, .persian, .islamicUmmAlQura, .islamicCivil, .buddhist, .japanese, .indian,
        .ethiopicAmeteMihret, .coptic,
    ]

    private func calendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testEveryDayOfThreeYearsStepsToTheNextDayInEveryCalendar() {
        // 2026-11-09 is Heshvan 29 5787: not a Gregorian month-day pair.
        let start = Date(timeIntervalSince1970: 1_778_000_000)
        for identifier in Self.identifiers {
            let calendar = calendar(identifier)
            for offset in 0..<(3 * 366) {
                let date = calendar.date(byAdding: .day, value: offset, to: start)!
                let key = PlannerDayKey(date: date, calendar: calendar)
                let midnight = key.startDate(calendar: calendar)
                XCTAssertEqual(midnight, calendar.startOfDay(for: date), "\(identifier) \(key)")
                let next = key.adding(days: 1, calendar: calendar)
                XCTAssertEqual(next.startDate(calendar: calendar),
                               calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
                               "\(identifier) \(key)")
            }
        }
    }

    func testChineseCalendarLeapMonthsNeverTrap() {
        // A key has no room for a leap month, so a day in one reads back as
        // the same day of the month before; it must still never trap.
        let calendar = calendar(.chinese)
        let start = Date(timeIntervalSince1970: 1_778_000_000)
        for offset in 0..<(3 * 366) {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let key = PlannerDayKey(date: date, calendar: calendar)
            _ = key.adding(days: 1, calendar: calendar)
            let state = WidgetState.empty(at: date, calendar: calendar)
            XCTAssertEqual(state.changeDates(after: date, calendar: calendar).last,
                           calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)), "\(key)")
        }
    }

    func testWidgetTimelineDatesWorkOnAHebrewDayThatIsNotAGregorianDate() throws {
        let hebrew = calendar(.hebrew)
        let heshvan29 = try XCTUnwrap(hebrew.date(from: DateComponents(year: 5787, month: 2, day: 29, hour: 12)))
        let state = WidgetState.empty(at: heshvan29, calendar: hebrew)
        XCTAssertEqual(state.day.rawValue, "5787-02-29")
        XCTAssertEqual(state.changeDates(after: heshvan29, calendar: hebrew),
                       [hebrew.date(from: DateComponents(year: 5787, month: 2, day: 30))!])
        XCTAssertEqual(WidgetState.focusDays(endingOn: state.day, calendar: hebrew, limit: 3) { _ in [] }, [])
    }
}
