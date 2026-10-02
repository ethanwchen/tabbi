import Foundation

/// One proposed focus block from Plan My Day.
public struct PlanBlock: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var start: Date
    public var end: Date
    public var title: String
    /// The checklist item this block works on, when Claude linked one.
    public var linkedTaskID: UUID?

    public init(id: UUID = UUID(), start: Date, end: Date, title: String, linkedTaskID: UUID? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
        self.linkedTaskID = linkedTaskID
    }

    public var interval: DateInterval { DateInterval(start: start, end: end) }
}

/// Everything Plan My Day knows when it asks Claude for a schedule.
///
/// Built once per request so the prompt, the parser (which resolves `HH:mm`
/// and short task ids), and the validator all agree on the same day and gaps.
public struct DayPlanContext: Sendable {
    public let now: Date
    public let events: [UpcomingEvent]
    /// Unfinished checklist items, in list order.
    public let tasks: [PlannerItem]
    public let calendar: Calendar
    /// When planned work should stop for the day.
    public let dayEnd: Date
    /// Free time between `now` and `dayEnd`, never overlapping a timed event.
    public let gaps: [DateInterval]

    public init(now: Date, events: [UpcomingEvent], tasks: [PlannerItem], calendar: Calendar = .current) {
        self.now = now
        self.events = events
        self.tasks = tasks.filter { !$0.isDone }
        self.calendar = calendar
        let dayEnd = DayPlanner.dayEnd(now: now, calendar: calendar)
        self.dayEnd = dayEnd
        self.gaps = DayPlanner.freeGaps(events: events, from: now, until: dayEnd)
    }

    /// Short, stable ids ("t1", "t2", ...) for the prompt; UUIDs waste tokens
    /// and invite typos when echoed back.
    public var taskKeys: [(key: String, task: PlannerItem)] {
        tasks.enumerated().map { ("t\($0.offset + 1)", $0.element) }
    }

    /// Whether there is any free time worth planning.
    public var hasFreeTime: Bool { !gaps.isEmpty }
}

/// Pure logic behind Plan My Day: free-gap finding, the Claude prompt and
/// CLI flags, defensive JSON parsing, and validation of what comes back.
public enum DayPlanner {
    /// Fast model alias; the plan is a small, structured answer.
    public static let model = "haiku"
    /// Gaps shorter than this aren't worth a block.
    public static let minimumBlockMinutes = 15
    /// Proposal rows the panel can show without scrolling.
    public static let maximumBlocks = 5
    /// Longest block title Claude is asked for; a proposal row shows about
    /// this many characters before truncating.
    public static let maximumTitleLength = 22
    /// Planned blocks start on these minute marks.
    static let slotMinutes = 5

    /// JSON Schema handed to `claude --json-schema` so the result text is
    /// the bare plan object.
    public static let jsonSchema = """
    {"type":"object","properties":{"blocks":{"type":"array","items":{"type":"object","properties":{\
    "start":{"type":"string","pattern":"^[0-2][0-9]:[0-5][0-9]$"},\
    "end":{"type":"string","pattern":"^[0-2][0-9]:[0-5][0-9]$"},\
    "title":{"type":"string"},"task":{"type":"string"}},\
    "required":["start","end","title"],"additionalProperties":false}}},\
    "required":["blocks"],"additionalProperties":false}
    """

    /// Arguments inserted before `-- <prompt>`. No tools and no MCP servers,
    /// so the CLI can only answer with the structured plan.
    public static func extraArguments() -> [String] {
        ["--model", model, "--tools", "", "--strict-mcp-config", "--json-schema", jsonSchema]
    }

    /// A sensible stop time: 6 pm, or two hours from now when planning
    /// later, but never past 10 pm. After 10 pm there is nothing to plan.
    public static func dayEnd(now: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: now)
        let sixPM = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: midnight)!
        let tenPM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: midnight)!
        return min(max(sixPM, now.addingTimeInterval(2 * 3600)), tenPM)
    }

    /// Free intervals between `start` and `end` that no timed event touches.
    ///
    /// All-day events don't block time (they're usually holidays or
    /// reminders). The first gap starts on the next five-minute mark so
    /// blocks read naturally, and slivers under `minimumMinutes` are dropped.
    public static func freeGaps(
        events: [UpcomingEvent],
        from start: Date,
        until end: Date,
        minimumMinutes: Int = minimumBlockMinutes
    ) -> [DateInterval] {
        let slot = TimeInterval(slotMinutes * 60)
        var cursor = Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / slot).rounded(.up) * slot)
        var gaps: [DateInterval] = []
        let busy = events
            .filter { !$0.isAllDay && $0.end > $0.start && $0.end > cursor && $0.start < end }
            .sorted { $0.start < $1.start }
        func close(at boundary: Date) {
            let gapEnd = min(boundary, end)
            if gapEnd.timeIntervalSince(cursor) >= TimeInterval(minimumMinutes * 60) {
                gaps.append(DateInterval(start: cursor, end: gapEnd))
            }
        }
        for event in busy {
            if event.start > cursor { close(at: event.start) }
            cursor = max(cursor, event.end)
            if cursor >= end { return gaps }
        }
        if cursor < end { close(at: end) }
        return gaps
    }

    /// The prompt for `claude -p`. Times are local 24-hour `HH:mm` so Claude
    /// never has to reason about time zones.
    public static func prompt(for context: DayPlanContext) -> String {
        let clock = clockFormatter(context.calendar)
        func range(_ start: Date, _ end: Date) -> String { "\(clock.string(from: start))-\(clock.string(from: end))" }

        let events = context.events
            .filter { !$0.isAllDay && $0.end > context.now && $0.start < context.dayEnd }
            .sorted { $0.start < $1.start }
            .map { "- \(range($0.start, $0.end)) \(UpcomingEventFormat.title($0))" }
        let gaps = context.gaps.map { "- \(range($0.start, $0.end))" }
        let tasks = context.taskKeys.map { "- \($0.key): \($0.task.title)" }

        return """
        You plan the rest of someone's day. It is now \(clock.string(from: context.now)). \
        Planned work should end by \(clock.string(from: context.dayEnd)).

        Calendar events (fixed, do not move or overlap):
        \(events.isEmpty ? "- none" : events.joined(separator: "\n"))

        Free time you may use:
        \(gaps.isEmpty ? "- none" : gaps.joined(separator: "\n"))

        Unfinished tasks:
        \(tasks.isEmpty ? "- none" : tasks.joined(separator: "\n"))

        Propose at most \(maximumBlocks) focused time blocks that fit entirely inside the free time. \
        Each block is \(minimumBlockMinutes) to 120 minutes, starts on a 5-minute mark, and blocks never overlap. \
        Prefer the most important tasks first and leave short breaks. \
        Titles are at most \(maximumTitleLength) characters, a shortened form of the task's words \
        (for example "Draft release notes", not "Write the release notes for the beta launch"). \
        Set "task" to the task id (like "t1") when a block works on a task; omit it otherwise. \
        Use 24-hour local times as "HH:mm". If there is no useful free time, return no blocks.

        Answer with JSON only: {"blocks":[{"start":"HH:mm","end":"HH:mm","title":"...","task":"t1"}]}
        """
    }

    /// Why a response couldn't become a plan.
    public enum ParseError: Error, Equatable {
        /// No JSON object or array could be found in the text.
        case noJSON
    }

    /// Reads Claude's answer into blocks on the context's day.
    ///
    /// Defensive by design: tolerates code fences and surrounding prose,
    /// a bare array instead of `{"blocks": [...]}`, `H:mm` times, and
    /// unknown task ids. Malformed entries are skipped rather than failing
    /// the whole plan. Throws only when no JSON is present at all.
    public static func parse(_ text: String, context: DayPlanContext) throws -> [PlanBlock] {
        guard let json = extractJSON(from: text),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { throw ParseError.noJSON }

        let entries: [Any]
        if let array = object as? [Any] {
            entries = array
        } else if let dict = object as? [String: Any] {
            entries = (dict["blocks"] as? [Any]) ?? []
        } else {
            throw ParseError.noJSON
        }

        let tasksByKey = Dictionary(uniqueKeysWithValues: context.taskKeys.map { ($0.key.lowercased(), $0.task.id) })
        let tasksByID = Dictionary(uniqueKeysWithValues: context.tasks.map { ($0.id.uuidString.lowercased(), $0.id) })
        let midnight = context.calendar.startOfDay(for: context.now)

        return entries.compactMap { entry -> PlanBlock? in
            guard let dict = entry as? [String: Any],
                  let start = (dict["start"] as? String).flatMap({ time($0, on: midnight, calendar: context.calendar) }),
                  let end = (dict["end"] as? String).flatMap({ time($0, on: midnight, calendar: context.calendar) }),
                  end > start,
                  let title = (dict["title"] as? String).flatMap(PlannerDay.normalized)
            else { return nil }
            let taskKey = ((dict["task"] ?? dict["taskId"] ?? dict["linkedTaskID"]) as? String)?
                .trimmingCharacters(in: .whitespaces).lowercased()
            let linked = taskKey.flatMap { tasksByKey[$0] ?? tasksByID[$0] }
            return PlanBlock(start: start, end: end, title: title, linkedTaskID: linked)
        }
    }

    /// Makes a proposal safe to write to the calendar.
    ///
    /// Each block is clipped to the free gaps (so it can't overlap an event,
    /// start in the past, or run past `dayEnd`), keeping its longest piece.
    /// Blocks are then ordered, overlaps between blocks are trimmed off the
    /// later one, anything shorter than `minimumBlockMinutes` is dropped,
    /// and the list is capped at `maximumBlocks`.
    public static func validate(_ blocks: [PlanBlock], context: DayPlanContext) -> [PlanBlock] {
        let minimum = TimeInterval(minimumBlockMinutes * 60)
        let clipped = blocks.compactMap { block -> PlanBlock? in
            let pieces = context.gaps.compactMap { $0.intersection(with: block.interval) }
            guard let longest = pieces.max(by: { $0.duration < $1.duration }), longest.duration >= minimum else { return nil }
            var result = block
            result.start = longest.start
            result.end = longest.end
            return result
        }
        var accepted: [PlanBlock] = []
        for var block in clipped.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let previous = accepted.last, block.start < previous.end { block.start = previous.end }
            guard block.end.timeIntervalSince(block.start) >= minimum else { continue }
            accepted.append(block)
            if accepted.count == maximumBlocks { break }
        }
        return accepted
    }

    /// Parses and validates in one step, as the panel uses it.
    public static func proposal(from text: String, context: DayPlanContext) throws -> [PlanBlock] {
        validate(try parse(text, context: context), context: context)
    }

    // MARK: - Helpers

    /// The outermost JSON object or array in `text`, ignoring fences and prose.
    static func extractJSON(from text: String) -> String? {
        let openers = [text.firstIndex(of: "{"), text.firstIndex(of: "[")].compactMap { $0 }
        guard let start = openers.min() else { return nil }
        let closer: Character = text[start] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), end > start else { return nil }
        return String(text[start...end])
    }

    /// `HH:mm` or `H:mm` on the day starting at `midnight`; nil when invalid.
    /// Resolved as wall-clock time through `calendar` so DST days stay right.
    static func time(_ string: String, on midnight: Date, calendar: Calendar) -> Date? {
        let fields = string.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard fields.count == 2, fields[1].count == 2,
              let hour = Int(fields[0]), let minute = Int(fields[1]),
              (0...24).contains(hour), (0..<60).contains(minute), hour * 60 + minute <= 24 * 60
        else { return nil }
        if hour == 24 { return calendar.date(byAdding: .day, value: 1, to: midnight) }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: midnight)
    }

    static func clockFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}
