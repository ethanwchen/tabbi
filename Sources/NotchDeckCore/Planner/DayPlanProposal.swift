import Foundation

/// A calendar event Plan My Day is about to write.
public struct PlannedCalendarEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var notes: String

    public init(title: String, start: Date, end: Date, notes: String) {
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }
}

/// Writes accepted plan blocks to the user's calendar.
///
/// The app implements this with EventKit (default calendar, so accounts
/// added in Internet Accounts such as Google just work); demo mode and dry
/// runs use writers that never touch the calendar. Keeping it a protocol
/// lets the writing path be tested without EventKit.
public protocol PlanCalendarWriting {
    /// Writes every event or throws without writing any of them.
    func write(_ events: [PlannedCalendarEvent]) throws
}

/// The proposal shown in place of the checklist: blocks still waiting for
/// a decision, plus how many have been added so far.
public struct DayPlanProposal: Equatable, Sendable {
    /// Blocks the user hasn't accepted or dismissed yet, in time order.
    public private(set) var pending: [PlanBlock]
    /// How many blocks have been written to the calendar.
    public private(set) var addedCount = 0
    /// How many accepted blocks were left out because, by the time they
    /// were added, they had run out or a meeting had taken their time.
    public private(set) var skippedCount = 0

    public init(blocks: [PlanBlock]) {
        pending = blocks.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// True once every block has been added or dismissed.
    public var isSettled: Bool { pending.isEmpty }

    /// Removes a block the user doesn't want.
    public mutating func dismiss(_ id: PlanBlock.ID) {
        pending.removeAll { $0.id == id }
    }

    /// Writes the given pending blocks (all of them when `ids` is nil) and
    /// removes them from the proposal. Each block is re-checked against
    /// `now` and the calendar as it is at that moment (`events`), since time
    /// passes and meetings may arrive while the proposal is open: blocks are
    /// trimmed to the free time left or skipped, and skipped ones are
    /// counted in `skippedCount`. Nothing changes when the writer throws.
    ///
    /// - Returns: The events that were written.
    @discardableResult
    public mutating func add(
        _ ids: Set<PlanBlock.ID>? = nil,
        now: Date,
        events: [UpcomingEvent],
        writer: PlanCalendarWriting
    ) throws -> [PlannedCalendarEvent] {
        let chosen = pending.filter { ids?.contains($0.id) ?? true }
        let written = DayPlanner.calendarEvents(for: chosen, now: now, events: events)
        if !written.isEmpty { try writer.write(written) }
        let chosenIDs = Set(chosen.map(\.id))
        pending.removeAll { chosenIDs.contains($0.id) }
        addedCount += written.count
        skippedCount += chosen.count - written.count
        return written
    }
}

public extension DayPlanner {
    /// Note on every event Plan My Day writes, so they're easy to recognize.
    static let eventNote = "Planned with NotchDeck"

    /// Calendar events for `blocks`, re-checked against `now` and today's
    /// `events`: a block that has started is trimmed to begin on the next
    /// five-minute mark, a block a timed event now overlaps keeps its longest
    /// free piece, and one with less than `minimumBlockMinutes` left is
    /// dropped.
    static func calendarEvents(
        for blocks: [PlanBlock],
        now: Date,
        events: [UpcomingEvent]
    ) -> [PlannedCalendarEvent] {
        let minimum = TimeInterval(minimumBlockMinutes * 60)
        let busy = events.filter { !$0.isAllDay && $0.end > $0.start }
        return blocks.compactMap { block in
            let start = block.start >= now ? block.start : nextSlot(onOrAfter: now)
            guard block.end > start else { return nil }
            var pieces = [DateInterval(start: start, end: block.end)]
            for event in busy {
                pieces = pieces.flatMap { piece -> [DateInterval] in
                    guard event.start < piece.end, piece.start < event.end else { return [piece] }
                    var rest: [DateInterval] = []
                    if piece.start < event.start { rest.append(DateInterval(start: piece.start, end: event.start)) }
                    if event.end < piece.end { rest.append(DateInterval(start: event.end, end: piece.end)) }
                    return rest
                }
            }
            guard let longest = pieces.max(by: { $0.duration < $1.duration }), longest.duration >= minimum
            else { return nil }
            return PlannedCalendarEvent(title: block.title, start: longest.start, end: longest.end, notes: eventNote)
        }
    }

    /// A realistic proposal for demo mode, fitted around
    /// `UpcomingEvent.samples(now:)` and the sample checklist. Never calls
    /// Claude.
    static func sampleProposal(now: Date) -> [PlanBlock] {
        let minute: TimeInterval = 60
        let slotLength = 5 * minute
        let slot = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate / slotLength).rounded(.down) * slotLength)
        func block(_ from: Int, _ to: Int, _ title: String, _ task: Int? = nil) -> PlanBlock {
            PlanBlock(
                start: slot.addingTimeInterval(TimeInterval(from) * minute),
                end: slot.addingTimeInterval(TimeInterval(to) * minute),
                title: title,
                linkedTaskID: task.map { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0))! }
            )
        }
        // Gaps around the samples: after the review (+45) and after the run (+125).
        return [
            block(50, 90, "Ship planner beta", 3),
            block(135, 180, "Draft release notes"),
            block(190, 220, "Triage beta feedback"),
        ]
    }
}
