import Foundation
import Testing
@testable import TabbiKitCore

@Suite("Schedule week layout")
struct ScheduleWeekLayoutTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday, October 5, 2026.
    private static let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!

    private static func at(day: Int = 0, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: (day * 24 + hour) * 60 + minute, to: monday)!
    }

    private static func item(_ id: String, _ start: Date, _ end: Date, kind: ScheduleItem.Kind = .event,
                             allDay: Bool = false) -> ScheduleItem {
        ScheduleItem(id: id, title: id, start: start, end: end, kind: kind, isAllDay: allDay)
    }

    private static func layout(_ items: [ScheduleItem], now: Date = at(8)) -> ScheduleWeekLayout {
        ScheduleWeekLayout(now: now, items: items, calendar: calendar)
    }

    @Test func emptyWeekIsSevenFreeWorkingDaysFromToday() {
        let layout = Self.layout([])
        #expect(layout.days.count == 7)
        #expect(layout.days.map(\.date) == (0..<7).map { Self.at(day: $0, 0) })
        #expect(layout.days.map(\.isToday) == [true, false, false, false, false, false, false])
        #expect(layout.startMinute == 9 * 60)
        #expect(layout.endMinute == 18 * 60)
        #expect(layout.hourMarks.count == 10)
        let allFree = layout.days.allSatisfy { $0.freeMinutes == 9 * 60 && $0.placed.isEmpty }
        #expect(allFree)
        #expect(layout.freeMinutes == 7 * 9 * 60)
    }

    @Test func todayCountsOnlyTheFreeTimeLeft() {
        let layout = Self.layout([], now: Self.at(15))
        #expect(layout.days[0].freeMinutes == 3 * 60)
        #expect(layout.days[1].freeMinutes == 9 * 60)
        #expect(layout.freeMinutes == 3 * 60 + 6 * 9 * 60)
    }

    @Test func everyRowSharesTheHoursOfTheWeeksEarliestAndLatestItems() {
        let layout = Self.layout([
            Self.item("gym", Self.at(day: 2, 7, 30), Self.at(day: 2, 8, 15)),
            Self.item("dinner", Self.at(day: 4, 19), Self.at(day: 4, 20, 30)),
        ])
        #expect(layout.startMinute == 7 * 60)
        #expect(layout.endMinute == 21 * 60)
        for (offset, day) in layout.days.enumerated() {
            #expect(day.range == DateInterval(start: Self.at(day: offset, 7), end: Self.at(day: offset, 21)))
        }
        #expect(layout.position(ofMinute: 14 * 60) == 0.5)
    }

    @Test func itemsLandOnTheirOwnDayAtTheSameClockPosition() throws {
        let layout = Self.layout([
            Self.item("standup", Self.at(10), Self.at(10, 30)),
            Self.item("standup-tue", Self.at(day: 1, 10), Self.at(day: 1, 10, 30)),
            Self.item("deck", Self.at(day: 1, 13), Self.at(day: 1, 15), kind: .planned),
        ])
        #expect(layout.days[0].placed.map(\.id) == ["standup"])
        #expect(layout.days[1].placed.map(\.id) == ["standup-tue", "deck"])
        #expect(layout.days[2].placed.isEmpty)
        let monday = try #require(layout.days[0].placed.first)
        let tuesday = try #require(layout.days[1].placed.first)
        #expect(monday.x == tuesday.x)
        #expect(abs(monday.x - 1.0 / 9) < 1e-9)
        #expect(layout.days[1].eventCount == 1)
        #expect(layout.days[1].plannedCount == 1)
    }

    @Test func freeTimeKeepsABufferAroundEachEvent() {
        // 9-18 is 540 min; a 60 min event plus a 10 min buffer each side.
        let layout = Self.layout([Self.item("review", Self.at(day: 3, 12), Self.at(day: 3, 13))])
        #expect(layout.days[3].freeMinutes == 540 - 80)
        #expect(layout.days[2].freeMinutes == 540)
    }

    @Test func overlappingItemsTakeLanes() {
        let layout = Self.layout([
            Self.item("a", Self.at(day: 1, 14), Self.at(day: 1, 15)),
            Self.item("b", Self.at(day: 1, 14, 30), Self.at(day: 1, 15, 15)),
        ])
        #expect(layout.days[1].placed.map(\.lane) == [0, 1])
        let lanes = layout.days[1].placed.map(\.lanes)
        #expect(lanes == [2, 2])
    }

    @Test func allDayItemsBelongToTheirDaysAndNeverBlockTime() {
        let layout = Self.layout([
            Self.item("trip", Self.at(day: 2, 0), Self.at(day: 4, 0), allDay: true),
        ])
        #expect(layout.days.map { $0.allDay.map(\.id) } == [[], [], ["trip"], ["trip"], [], [], []])
        #expect(layout.days[2].freeMinutes == 9 * 60)
        #expect(layout.days[2].placed.isEmpty)
    }

    @Test func lateItemsRunTheRowsToMidnight() {
        let layout = Self.layout([Self.item("flight", Self.at(day: 5, 22), Self.at(day: 6, 1))])
        #expect(layout.endMinute == 24 * 60)
        #expect(layout.days[5].placed.map(\.id) == ["flight"])
        #expect(layout.days[6].placed.isEmpty, "the after-midnight part falls before the shared hours")
    }

    @Test func itemsOutsideTheWeekAreLeftOut() {
        let layout = Self.layout([
            Self.item("last-week", Self.at(day: -3, 10), Self.at(day: -3, 11)),
            Self.item("next-week", Self.at(day: 8, 10), Self.at(day: 8, 11)),
        ])
        let placed = layout.days.flatMap(\.placed)
        #expect(placed.isEmpty)
        #expect(layout.startMinute == 9 * 60)
    }

    @Test func dayLayoutKeepsOnlyItsOwnAllDayItems() {
        let items = [
            Self.item("payday", Self.at(0), Self.at(24), allDay: true),
            Self.item("trip", Self.at(day: 2, 0), Self.at(day: 3, 0), allDay: true),
        ]
        let day = ScheduleDayLayout(day: Self.monday, now: Self.at(8), items: items, calendar: Self.calendar)
        #expect(day.allDay.map(\.id) == ["payday"])
    }

    @Test func demoWeekKeepsWorkOffTheWeekend() {
        let items = ScheduleSampleData.weekItems(from: Self.monday, calendar: Self.calendar)
        let layout = ScheduleWeekLayout(now: ScheduleSampleData.now(on: Self.monday, calendar: Self.calendar),
                                        items: items, calendar: Self.calendar)
        #expect(layout.days.count == 7)
        let busyDays = layout.days.filter { !$0.placed.isEmpty }.count
        #expect(busyDays == 7)
        let saturday = layout.days[5]
        #expect(Self.calendar.isDateInWeekend(saturday.date))
        #expect(!saturday.placed.contains { $0.item.title == "Design standup" })
        #expect(layout.days[1].placed.contains { $0.item.title == "Design standup" })
        #expect(layout.days[1].plannedCount == 1)
    }
}
