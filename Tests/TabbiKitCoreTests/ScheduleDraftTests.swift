import Foundation
import Testing
@testable import TabbiKitCore

@Suite("Schedule draft")
struct ScheduleDraftTests {
    /// Records what it was asked to write, or fails like a denied calendar.
    private final class RecordingWriter: PlanCalendarWriting {
        struct Denied: Error {}
        var written: [PlannedCalendarEvent] = []
        var fails = false

        func write(_ events: [PlannedCalendarEvent]) throws {
            if fails { throw Denied() }
            written += events
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    private static let locale = Locale(identifier: "en_US")

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
    }

    private static func task(_ id: String, _ minutes: Int?, done: Bool = false) -> ProvidedTask {
        ProvidedTask(id: id, source: "planner", title: id, isDone: done, estimatedMinutes: minutes)
    }

    private static func draft(now: Date = at(9), items: [ScheduleItem] = [], tasks: [ProvidedTask],
                              progress: [ProgressItem] = []) -> ScheduleDraft {
        ScheduleDraft.plan(now: now, items: items, sharedTasks: tasks, progress: progress,
                           calendar: calendar, locale: locale)
    }

    @Test func plansAroundTheCalendarWithReasons() {
        let meeting = ScheduleItem(id: "standup", title: "Standup", start: Self.at(9, 30), end: Self.at(10))
        let draft = Self.draft(items: [meeting], tasks: [Self.task("Write spec", 60), Self.task("Inbox", 15)])
        let items = draft.items
        #expect(items.map(\.title) == ["Inbox", "Write spec"])
        let explained = items.allSatisfy { $0.kind == .proposed && $0.reason == "Next on your list" }
        #expect(explained)
        // 9:00 to 9:20 is free (10 min buffer before the standup), so the short task goes there.
        #expect(items.first?.start == Self.at(9))
        #expect(items.last?.start == Self.at(10, 10))
        #expect(draft.summary == "2 blocks, 1 h 15 min")
    }

    @Test func proposedItemsNeverBlockTheirOwnReplan() {
        let first = Self.draft(tasks: [Self.task("Write spec", 60)])
        let again = Self.draft(items: first.items, tasks: [Self.task("Write spec", 60)])
        #expect(again.items.map(\.start) == first.items.map(\.start))
    }

    @Test func reviewGoalsComeFirst() {
        let reviews = ProgressItem(id: "deck", source: "anki", title: "Anki reviews", completed: 0, target: 120,
                                   unit: "cards")
        let draft = Self.draft(tasks: [Self.task("Write spec", 30)], progress: [reviews])
        #expect(draft.items.first?.title == "Anki reviews")
        #expect(draft.items.first?.reason == "Reviews first, while you are fresh")
    }

    @Test func splitWorkIsNumbered() {
        let draft = Self.draft(tasks: [Self.task("Thesis", 150)])
        #expect(draft.items.map(\.title) == ["Thesis (1 of 2)", "Thesis (2 of 2)"])
    }

    @Test func finishedTasksAreLeftOut() {
        let draft = Self.draft(tasks: [Self.task("Done already", 30, done: true)])
        #expect(draft.isEmpty)
        #expect(draft.summary == "Nothing to plan: no open tasks or reviews")
    }

    @Test func summaryNamesWhatDidNotFit() {
        let busy = ScheduleItem(id: "offsite", title: "Offsite", start: Self.at(9), end: Self.at(18))
        let one = Self.draft(items: [busy], tasks: [Self.task("Write spec", 60)])
        #expect(one.isEmpty)
        #expect(one.summary == "Write spec didn't fit: No free time left today")
        let two = Self.draft(items: [busy], tasks: [Self.task("Write spec", 60), Self.task("Inbox", 15)])
        #expect(two.summary == "2 tasks didn't fit: No free time left today")
        #expect(two.unplacedDetail == "Write spec, 1 h: No free time left today\nInbox, 15 min: No free time left today")

        let partly = Self.draft(now: Self.at(16), tasks: [Self.task("Write spec", 60), Self.task("Big", 120)])
        #expect(partly.summary.hasSuffix(". 1 didn't fit"))
    }

    @Test func skipTakesABlockOffTheOffer() {
        var draft = Self.draft(tasks: [Self.task("Write spec", 60), Self.task("Inbox", 15)])
        let inbox = try! #require(draft.items.first { $0.title == "Inbox" })
        draft.skip(inbox.id)
        #expect(draft.items.map(\.title) == ["Write spec"])
        #expect(draft.summary == "1 block, 1 h")
        draft.skip("unknown")
        #expect(draft.items.count == 1)
    }

    @Test func addWritesOneOrAllBlocksMarkedAsPlanned() throws {
        var draft = Self.draft(tasks: [Self.task("Write spec", 60), Self.task("Inbox", 15)])
        let writer = RecordingWriter()
        let spec = try #require(draft.items.first { $0.title == "Write spec" })
        try draft.add(spec.id, now: Self.at(9), events: [], writer: writer)
        #expect(writer.written.map(\.title) == ["Write spec"])
        #expect(writer.written.first?.notes == DayPlanner.eventNote)
        #expect(draft.items.map(\.title) == ["Inbox"])
        #expect(try draft.add("unknown", now: Self.at(9), events: [], writer: writer).isEmpty)
        try draft.add(now: Self.at(9), events: [], writer: writer)
        #expect(writer.written.map(\.title) == ["Write spec", "Inbox"])
        #expect(draft.isSettled)
        #expect(draft.addedCount == 2)
    }

    @Test func aFailedWriteKeepsTheOffer() {
        var draft = Self.draft(tasks: [Self.task("Write spec", 60)])
        let writer = RecordingWriter()
        writer.fails = true
        #expect(throws: RecordingWriter.Denied.self) {
            try draft.add(now: Self.at(9), events: [], writer: writer)
        }
        #expect(draft.items.count == 1)
        #expect(draft.addedCount == 0)
    }

    @Test func demoTasksFillTheDemoAfternoonAndLeaveOneOver() {
        let date = Self.at(20)
        let draft = ScheduleDraft.plan(now: ScheduleSampleData.now(on: date, calendar: Self.calendar),
                                       items: ScheduleSampleData.items(on: date, calendar: Self.calendar),
                                       sharedTasks: ScheduleSampleData.tasks, progress: [],
                                       calendar: Self.calendar, locale: Self.locale)
        #expect(draft.items.map(\.title) == ["Review PR #142", "Reply to Priya", "Prep beta review notes"])
        let afternoon = draft.items.allSatisfy { $0.start >= Self.at(15) }
        #expect(afternoon)
        #expect(draft.unplaced.map(\.work.title) == ["Outline the Q4 roadmap"])
        #expect(draft.summary == "3 blocks, 1 h 30 min. 1 didn't fit")
    }

    // MARK: Refine with Claude

    @Test func refiningReplacesTheOfferAndExplainsClaudesBlocks() throws {
        var draft = Self.draft(tasks: [Self.task("Write spec", 60), Self.task("Inbox", 15)])
        #expect(draft.canRefine)
        let suggested = PlanBlock(start: Self.at(10), end: Self.at(11), title: "Write spec")
        draft.refine(with: [suggested])
        #expect(draft.refinement == .changed)
        #expect(!draft.canRefine)
        let item = try #require(draft.items.first)
        #expect(draft.items.count == 1)
        #expect(item.kind == .proposed)
        #expect(item.start == Self.at(10))
        #expect(item.reason == "Suggested by Claude")
        #expect(draft.summary == "1 block, 1 h")

        let writer = RecordingWriter()
        try draft.add(item.id, now: Self.at(9), events: [], writer: writer)
        #expect(writer.written.map(\.start) == [Self.at(10)])
        #expect(draft.isSettled)
    }

    @Test func anUnchangedRefinementKeepsTheLocalReasons() {
        var draft = Self.draft(tasks: [Self.task("Write spec", 60)])
        let before = draft.items
        draft.refine(with: draft.proposal.pending)
        #expect(draft.refinement == .unchanged)
        #expect(draft.items == before)
        #expect(!draft.canRefine)
    }

    @Test func workClaudeFitsInNoLongerCountsAsLeftOut() {
        var draft = Self.draft(now: Self.at(16), tasks: [Self.task("Write spec", 60), Self.task("Big", 120)])
        let left = try! #require(draft.unplaced.first?.work.title)
        draft.refine(with: [PlanBlock(start: Self.at(16), end: Self.at(17), title: left)])
        #expect(draft.unplaced.isEmpty)
        #expect(!draft.summary.contains("didn't fit"))
    }

    @Test func theRefineContextSeesTheCalendarAndAllTheWork() {
        let meeting = ScheduleItem(id: "standup", title: "Standup", start: Self.at(9, 30), end: Self.at(10))
        let draft = Self.draft(now: Self.at(16), items: [meeting],
                               tasks: [Self.task("Write spec", 60), Self.task("Big", 120)])
        let context = draft.refineContext(now: Self.at(16), items: [meeting] + draft.items, calendar: Self.calendar)
        #expect(context.events.map(\.id) == ["standup"])
        #expect(Set(context.sharedWork) == ["Write spec", "Big"])
        #expect(context.tasks.isEmpty)
    }

    @Test func weekPlansAreNotRefined() {
        let draft = Self.weekDraft(tasks: [Self.task("Write spec", 60)])
        #expect(!draft.canRefine)
    }

    // MARK: Week

    private static func weekDraft(now: Date = at(9), items: [ScheduleItem] = [], tasks: [ProvidedTask],
                                  progress: [ProgressItem] = []) -> ScheduleDraft {
        ScheduleDraft.planWeek(now: now, items: items, sharedTasks: tasks, progress: progress,
                               calendar: calendar, locale: locale)
    }

    private static func on(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: day, to: at(hour, minute))!
    }

    @Test func weekPlanMovesWhatTodayCannotHoldToTheNextDay() {
        let meeting = ScheduleItem(id: "review", title: "Design review", start: Self.at(16, 30), end: Self.at(18))
        let draft = Self.weekDraft(now: Self.at(16), items: [meeting],
                                   tasks: [Self.task("Inbox", 15), Self.task("Write spec", 60)])
        #expect(draft.isWeek)
        // 16:00 to 16:20 is all today has left before the meeting's buffer.
        #expect(draft.items.map(\.title) == ["Inbox", "Write spec"])
        #expect(draft.items.map(\.start) == [Self.at(16), Self.on(1, 9)])
        #expect(draft.unplaced.isEmpty)
        #expect(draft.summary == "2 blocks over 2 days, 1 h 15 min")
    }

    @Test func weekPlanKeepsUsualHoursWhenPlanningLate() {
        // At 21:00 today's working day is over, so the work starts tomorrow at 9:00 and ends by 18:00.
        let draft = Self.weekDraft(now: Self.at(21), tasks: [Self.task("Write spec", 60)])
        #expect(draft.items.map(\.start) == [Self.on(1, 9)])
        #expect(draft.summary == "1 block, 1 h")
    }

    @Test func weekPlanSpreadsLongWorkAcrossDays() {
        // The 6 h daily focus limit leaves 4 of the 10 h for the next day.
        let busy = (0..<7).map { day in
            ScheduleItem(id: "lunch-\(day)", title: "Lunch", start: Self.on(day, 12), end: Self.on(day, 13))
        }
        let draft = Self.weekDraft(items: busy, tasks: (1...5).map { Self.task("Project \($0)", 120) })
        let days = Set(draft.items.map { Self.calendar.startOfDay(for: $0.start) })
        #expect(days == [Self.day, Self.on(1, 0)])
        let clear = draft.items.allSatisfy { item in
            busy.allSatisfy { item.end <= $0.start.addingTimeInterval(-600) || item.start >= $0.end.addingTimeInterval(600) }
        }
        #expect(clear)
        let workingHours = draft.items.allSatisfy {
            let start = Self.calendar.dateComponents([.hour], from: $0.start).hour ?? 0
            let end = Self.calendar.dateComponents([.hour, .minute], from: $0.end)
            return start >= 9 && ((end.hour ?? 0) < 18 || (end.hour == 18 && end.minute == 0))
        }
        #expect(workingHours)
        #expect(draft.unplaced.isEmpty)
    }

    @Test func weekPlanListsWhatNoDayCouldHold() {
        let busy = (0..<7).map { day in
            ScheduleItem(id: "trip-\(day)", title: "Conference", start: Self.on(day, 8), end: Self.on(day, 19))
        }
        let draft = Self.weekDraft(items: busy, tasks: [Self.task("Write spec", 60)])
        #expect(draft.isEmpty)
        #expect(draft.summary == "Write spec didn't fit: No free time left this week")
    }

    @Test func weekPlanAddsBlocksOnEveryDayMarkedAsPlanned() throws {
        let meeting = ScheduleItem(id: "review", title: "Design review", start: Self.at(16, 30), end: Self.at(18))
        var draft = Self.weekDraft(now: Self.at(16), items: [meeting],
                                   tasks: [Self.task("Inbox", 15), Self.task("Write spec", 60)])
        let writer = RecordingWriter()
        try draft.add(now: Self.at(16), events: [meeting.upcomingEvent], writer: writer)
        #expect(writer.written.map(\.start) == [Self.at(16), Self.on(1, 9)])
        let marked = writer.written.allSatisfy { $0.notes == DayPlanner.eventNote }
        #expect(marked)
        #expect(draft.isSettled)
    }

    @Test func demoWeekSpreadsTheSampleTasksOverSeveralDays() {
        let date = Self.at(20)
        let draft = ScheduleDraft.planWeek(now: ScheduleSampleData.now(on: date, calendar: Self.calendar),
                                           items: ScheduleSampleData.weekItems(from: date, calendar: Self.calendar),
                                           sharedTasks: ScheduleSampleData.weekTasks, progress: [],
                                           calendar: Self.calendar, locale: Self.locale)
        let days = Set(draft.items.map { Self.calendar.startOfDay(for: $0.start) })
        #expect(days.count >= 2)
        #expect(draft.unplaced.isEmpty)
        let titles = Set(draft.items.map(\.title).map { $0.components(separatedBy: " (").first ?? $0 })
        #expect(titles == Set(ScheduleSampleData.weekTasks.map(\.title)))
    }
}
