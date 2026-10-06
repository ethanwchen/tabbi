import Foundation

/// A day plan the Schedule offers on its timeline before anything reaches
/// the calendar: the local plan's blocks still waiting for Add or Skip,
/// each with its reason, and what didn't fit.
///
/// Adding and skipping go through `DayPlanProposal`, so blocks are written
/// the way Plan my day writes them (re-checked against the clock and the
/// calendar, marked as planned by Tabbi).
public struct ScheduleDraft: Equatable, Sendable {
    public let plan: SchedulePlan
    public private(set) var proposal: DayPlanProposal
    /// True when the plan covers the coming week rather than today.
    public let isWeek: Bool
    /// The day (midnight) each block of a week plan was planned on.
    private let blockDays: [PlanBlock.ID: Date]

    public init(plan: SchedulePlan) {
        self.plan = plan
        proposal = plan.proposal
        isWeek = false
        blockDays = [:]
    }

    /// A week plan as one draft: every day's blocks and breaks, and what
    /// didn't fit anywhere in the week.
    public init(week: ScheduleWeekPlan) {
        plan = SchedulePlan(day: week.days.first?.day ?? .distantPast, blocks: week.days.flatMap(\.blocks),
                            breaks: week.days.flatMap(\.breaks), unplaced: week.unplaced)
        proposal = plan.proposal
        isWeek = true
        blockDays = Dictionary(week.days.flatMap { day in day.blocks.map { ($0.id, day.day) } },
                               uniquingKeysWith: { first, _ in first })
    }

    /// Plans the rest of the day containing `now` around `items` (the
    /// calendar as the Schedule shows it) with Today's planning settings:
    /// review goals still due, then other modules' open tasks.
    public static func plan(now: Date, items: [ScheduleItem], sharedTasks: [ProvidedTask],
                            progress: [ProgressItem], settings: TodayPlanSettings = TodayPlanSettings(),
                            calendar: Calendar = .current, locale: Locale = .current) -> ScheduleDraft {
        let events = items.filter { $0.kind != .proposed }.map(\.upcomingEvent)
        let plan = settings.localPlan(now: now, events: events, tasks: [], sharedTasks: sharedTasks,
                                      progress: progress, calendar: calendar, locale: locale)
        return ScheduleDraft(plan: plan)
    }

    /// Spreads the same work over today and the `days - 1` days after it,
    /// each day's free time in turn, so what doesn't fit today lands on the
    /// next day with room.
    public static func planWeek(now: Date, days: Int = 7, items: [ScheduleItem], sharedTasks: [ProvidedTask],
                                progress: [ProgressItem], settings: TodayPlanSettings = TodayPlanSettings(),
                                calendar: Calendar = .current, locale: Locale = .current) -> ScheduleDraft {
        let events = items.filter { $0.kind != .proposed }.map(\.upcomingEvent)
        let week = settings.localWeekPlan(now: now, days: days, events: events, tasks: [], sharedTasks: sharedTasks,
                                          progress: progress, calendar: calendar, locale: locale)
        return ScheduleDraft(week: week)
    }

    /// Blocks still on offer, as proposed items for the timeline. Blocks
    /// Claude suggested in place of the local ones say so as their reason.
    public var items: [ScheduleItem] {
        let local = Dictionary(plan.blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return proposal.pending.map { block in
            guard let scheduled = local[block.id] else {
                return ScheduleItem(id: block.id.uuidString, title: block.title, start: block.start, end: block.end,
                                    kind: .proposed, reason: "Suggested by Claude")
            }
            var item = ScheduleItem(scheduled: scheduled)
            item.kind = .proposed
            if scheduled.parts > 1 { item.title += " (\(scheduled.part) of \(scheduled.parts))" }
            return item
        }
    }

    /// What "Refine with Claude" did to this plan, once it has run.
    public var refinement: PlanRefinement? { proposal.refinement }

    /// True while a day plan still has blocks on offer and hasn't been
    /// refined yet. Week plans span days Claude's day prompt can't see.
    public var canRefine: Bool { !isWeek && !proposal.pending.isEmpty && proposal.refinement == nil }

    /// The day Claude refines: the calendar as `items` show it now and the
    /// plan's work (placed or not), so Claude can also fit in what didn't fit.
    public func refineContext(now: Date, items: [ScheduleItem], settings: TodayPlanSettings = TodayPlanSettings(),
                              calendar: Calendar = .current) -> DayPlanContext {
        var work: [String] = []
        for title in plan.blocks.map(\.block.title) + plan.unplaced.map(\.work.title) where !work.contains(title) {
            work.append(title)
        }
        return DayPlanContext(now: now, events: items.filter { $0.kind != .proposed }.map(\.upcomingEvent),
                              tasks: [], sharedWork: work, calendar: calendar, dayEndHour: settings.dayEndHour)
    }

    /// Replaces the blocks still on offer with Claude's (from
    /// `DayPlanner.refinement`); see `DayPlanProposal.refine(with:)`.
    public mutating func refine(with blocks: [PlanBlock]) {
        proposal.refine(with: blocks)
    }

    /// Work the plan left out, and why; a refined plan may have found room.
    public var unplaced: [UnplacedWork] {
        guard proposal.refinement == .changed else { return plan.unplaced }
        return plan.unplaced.filter { work in !proposal.pending.contains { $0.title == work.work.title } }
    }

    /// True when the plan had nothing to offer in the first place.
    public var isEmpty: Bool { plan.blocks.isEmpty }

    /// True once every block has been added or skipped.
    public var isSettled: Bool { proposal.isSettled }

    public var addedCount: Int { proposal.addedCount }

    /// Minutes of focus still on offer.
    public var pendingMinutes: Int {
        proposal.pending.reduce(0) { $0 + max(Int($1.end.timeIntervalSince($1.start) / 60), 0) }
    }

    /// One line on what the draft offers: "3 blocks, 1 h 30 min. 1 didn't
    /// fit" ("5 blocks over 3 days, ..." for a week), or why there's
    /// nothing to offer.
    public var summary: String {
        guard !isEmpty else {
            if let first = unplaced.first {
                return unplaced.count == 1 ? "\(first.work.title) didn't fit: \(first.reason)"
                                           : "\(unplaced.count) tasks didn't fit: \(first.reason)"
            }
            return "Nothing to plan: no open tasks or reviews"
        }
        let count = proposal.pending.count
        var text = "\(count) \(count == 1 ? "block" : "blocks")"
        let days = Set(proposal.pending.compactMap { blockDays[$0.id] }).count
        if days > 1 { text += " over \(days) days" }
        text += ", \(ScheduleFormat.duration(minutes: pendingMinutes))"
        if !unplaced.isEmpty { text += ". \(unplaced.count) didn't fit" }
        return text
    }

    /// A tooltip listing what didn't fit, one line each.
    public var unplacedDetail: String? {
        guard !unplaced.isEmpty else { return nil }
        return unplaced.map { "\($0.work.title), \(ScheduleFormat.duration(minutes: $0.minutes)): \($0.reason)" }
            .joined(separator: "\n")
    }

    /// Takes a block off the offer.
    public mutating func skip(_ id: ScheduleItem.ID) {
        guard let block = proposal.pending.first(where: { $0.id.uuidString == id }) else { return }
        proposal.dismiss(block.id)
    }

    /// Writes one block (every block still on offer when `id` is nil),
    /// re-checked against `now` and the calendar's `events`. Nothing changes
    /// when the writer throws.
    @discardableResult
    public mutating func add(_ id: ScheduleItem.ID? = nil, now: Date, events: [UpcomingEvent],
                             writer: PlanCalendarWriting) throws -> [PlannedCalendarEvent] {
        let ids = id.map { id in Set(proposal.pending.filter { $0.id.uuidString == id }.map(\.id)) }
        if let ids, ids.isEmpty { return [] }
        return try proposal.add(ids, now: now, events: events, writer: writer)
    }
}
