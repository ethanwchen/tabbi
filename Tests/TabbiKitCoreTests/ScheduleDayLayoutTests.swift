import Foundation
import Testing
@testable import TabbiKitCore

@Suite("Schedule day layout")
struct ScheduleDayLayoutTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    private static func item(_ id: String, _ start: Date, _ end: Date, kind: ScheduleItem.Kind = .event,
                             allDay: Bool = false) -> ScheduleItem {
        ScheduleItem(id: id, title: id, start: start, end: end, kind: kind, isAllDay: allDay)
    }

    private static func layout(_ items: [ScheduleItem], now: Date = at(8)) -> ScheduleDayLayout {
        ScheduleDayLayout(day: day, now: now, items: items, calendar: calendar)
    }

    @Test func emptyDaySpansTheWorkingHours() {
        let layout = Self.layout([])
        #expect(layout.range == DateInterval(start: Self.at(9), end: Self.at(18)))
        #expect(layout.hours.count == 10)
        #expect(layout.hours.first == Self.at(9))
        #expect(layout.hours.last == Self.at(18))
        #expect(layout.placed.isEmpty)
        #expect(layout.freeMinutes == 9 * 60)
    }

    @Test func rangeStretchesToWholeHoursAroundEarlyAndLateItems() {
        let layout = Self.layout([
            Self.item("gym", Self.at(7, 30), Self.at(8, 15)),
            Self.item("dinner", Self.at(19), Self.at(20, 10)),
        ])
        #expect(layout.range == DateInterval(start: Self.at(7), end: Self.at(21)))
    }

    @Test func rangeStaysInsideTheDay() {
        let previous = Self.at(-2)
        let next = Self.at(25)
        let layout = Self.layout([Self.item("overnight", previous, Self.at(1)), Self.item("late", Self.at(23), next)])
        #expect(layout.range == DateInterval(start: Self.at(0), end: Self.at(24)))
        #expect(layout.placed.first?.x == 0)
    }

    @Test func positionsAreFractionsOfTheRange() {
        let layout = Self.layout([Self.item("standup", Self.at(10, 30), Self.at(11, 15))])
        let placed = try! #require(layout.placed.first)
        #expect(abs(placed.x - 1.5 / 9) < 1e-9)
        #expect(abs(placed.width - 0.75 / 9) < 1e-9)
        #expect(layout.position(of: Self.at(13, 30)) == 0.5)
        #expect(layout.position(of: Self.at(8)) == nil)
    }

    @Test func overlappingItemsTakeSeparateLanes() {
        let layout = Self.layout([
            Self.item("a", Self.at(10), Self.at(11)),
            Self.item("b", Self.at(10, 30), Self.at(11, 30)),
            Self.item("c", Self.at(11), Self.at(12)),
            Self.item("d", Self.at(14), Self.at(15)),
        ])
        let lanes = Dictionary(uniqueKeysWithValues: layout.placed.map { ($0.id, ($0.lane, $0.lanes)) })
        #expect(lanes["a"]! == (0, 2))
        #expect(lanes["b"]! == (1, 2))
        // "c" starts as "a" ends, so it reuses the first lane of the same group.
        #expect(lanes["c"]! == (0, 2))
        #expect(lanes["d"]! == (0, 1))
    }

    @Test func lanesStopAtTheMaximum() {
        let items = (0..<5).map { Self.item("e\($0)", Self.at(10), Self.at(11)) }
        let layout = Self.layout(items)
        #expect(layout.placed.allSatisfy { $0.lanes == ScheduleDayLayout.maximumLanes })
        #expect(layout.placed.map(\.lane).max() == ScheduleDayLayout.maximumLanes - 1)
    }

    @Test func allDayItemsStayOffTheTimelineAndNeverBlockTime() {
        let layout = Self.layout([Self.item("holiday", Self.at(0), Self.at(24), allDay: true)])
        #expect(layout.placed.isEmpty)
        #expect(layout.allDay.map(\.id) == ["holiday"])
        #expect(layout.freeMinutes == 9 * 60)
    }

    @Test func freeTimeKeepsBuffersAndSkipsThePast() {
        let layout = Self.layout([Self.item("meeting", Self.at(14), Self.at(15))], now: Self.at(12))
        // 12:00 to 18:00 is 6 h; the meeting and 10 min either side take 80 min.
        #expect(layout.freeMinutes == 6 * 60 - 80)
    }

    @Test func statusIsTheItemUnderWay() {
        let layout = Self.layout([Self.item("long", Self.at(10), Self.at(12)), Self.item("short", Self.at(10), Self.at(11))])
        #expect(layout.status(at: Self.at(10, 30)) == .busy(layout.placed.first { $0.id == "short" }!.item))
    }

    @Test func statusIsFreeUntilTheNextItem() {
        let next = Self.item("lunch", Self.at(12, 30), Self.at(13, 30))
        let layout = Self.layout([next])
        #expect(layout.status(at: Self.at(11)) == .free(until: Self.at(12, 30), next: next))
        #expect(layout.status(at: Self.at(14)) == .free(until: nil, next: nil))
        #expect(layout.status(at: Self.at(18, 30)) == .dayOver)
    }

    @Test func planningHoursKeepTheEveningOpen() {
        // Plan my day stretches the day to two hours after now, so the layout does too.
        let now = Self.at(18, 10)
        let preferences = TodayPlanSettings().schedulePreferences(now: now, calendar: Self.calendar)
        let layout = ScheduleDayLayout(day: Self.day, now: now, items: [], preferences: preferences,
                                       calendar: Self.calendar)
        #expect(layout.freeMinutes == 120)
        #expect(layout.status(at: now) == .free(until: nil, next: nil))
    }

    @Test func plannedMarkerInTheNotesMakesAPlannedItem() {
        let event = UpcomingEvent(id: "x", title: "Focus", start: Self.at(10), end: Self.at(11))
        #expect(ScheduleItem(event: event, notes: "Planned with Tabbi").kind == .planned)
        #expect(ScheduleItem(event: event, notes: "Agenda").kind == .event)
        #expect(ScheduleItem(event: event).kind == .event)
    }

    @Test func scheduledBlocksKeepTheirReason() {
        let block = PlanBlock(start: Self.at(10), end: Self.at(11), title: "Write")
        let item = ScheduleItem(scheduled: ScheduledBlock(block: block, workID: "w", reason: "Due by 12:00"))
        #expect(item.kind == .planned)
        #expect(item.reason == "Due by 12:00")
        #expect(item.minutes == 60)
    }

    @Test func formatsDurationsAndStatus() {
        let locale = Locale(identifier: "en_US")
        let utc = TimeZone(identifier: "UTC")!
        #expect(ScheduleFormat.duration(minutes: 45) == "45 min")
        #expect(ScheduleFormat.duration(minutes: 120) == "2 h")
        #expect(ScheduleFormat.duration(minutes: 75) == "1 h 15 min")
        #expect(ScheduleFormat.range(Self.at(10, 45), Self.at(12), locale: locale, timeZone: utc) == "10:45-12:00")
        let lunch = Self.item("Lunch", Self.at(12, 30), Self.at(13, 30))
        #expect(ScheduleFormat.status(.free(until: lunch.start, next: lunch), now: Self.at(11, 20), locale: locale,
                                      timeZone: utc) == "Free for 1 h 10 min, then Lunch at 12:30")
        #expect(ScheduleFormat.status(.busy(lunch), now: Self.at(13), locale: locale, timeZone: utc)
            == "Now: Lunch, until 1:30")
        #expect(ScheduleFormat.title(Self.item("  ", Self.at(9), Self.at(10))) == "Untitled event")
    }

    @Test func sampleDayIsSeenFromLateMorning() {
        let now = ScheduleSampleData.now(on: Self.day, calendar: Self.calendar)
        let items = ScheduleSampleData.items(on: Self.day, calendar: Self.calendar)
        let layout = ScheduleDayLayout(day: Self.day, now: now, items: items, calendar: Self.calendar)
        #expect(now == Self.at(11, 20))
        #expect(items.contains { $0.kind == .planned })
        #expect(layout.allDay.count == 1)
        #expect(layout.placed.contains { $0.lanes == 2 })
        if case .busy = layout.status(at: now) {} else {
            Issue.record("The demo should be in a block at 11:20")
        }
    }
}
