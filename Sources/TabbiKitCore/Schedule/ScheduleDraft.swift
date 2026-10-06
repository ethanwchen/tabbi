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

    public init(plan: SchedulePlan) {
        self.plan = plan
        proposal = plan.proposal
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

    /// Blocks still on offer, as proposed items for the timeline.
    public var items: [ScheduleItem] {
        let pending = Set(proposal.pending.map(\.id))
        return plan.blocks.filter { pending.contains($0.id) }.map { scheduled in
            var item = ScheduleItem(scheduled: scheduled)
            item.kind = .proposed
            if scheduled.parts > 1 { item.title += " (\(scheduled.part) of \(scheduled.parts))" }
            return item
        }
    }

    /// Work the plan left out, and why.
    public var unplaced: [UnplacedWork] { plan.unplaced }

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
    /// fit", or why there's nothing to offer.
    public var summary: String {
        guard !isEmpty else {
            if let first = unplaced.first {
                return unplaced.count == 1 ? "\(first.work.title) didn't fit: \(first.reason)"
                                           : "\(unplaced.count) tasks didn't fit: \(first.reason)"
            }
            return "Nothing to plan: no open tasks or reviews"
        }
        let count = proposal.pending.count
        var text = "\(count) \(count == 1 ? "block" : "blocks"), \(ScheduleFormat.duration(minutes: pendingMinutes))"
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
