import Foundation

/// The End-of-Day Review: what got done, what carries over, and how much
/// focused work happened, plus a short encouraging line from Claude.
///
/// Saved as `Reviews/yyyy-MM-dd.json` when the user taps Done, so it stores
/// plain titles rather than item ids that may later be renamed or deleted.
public struct DayReview: Hashable, Codable, Sendable {
    public let date: PlannerDayKey
    /// Titles of tasks finished today, in list order.
    public var done: [String]
    /// Titles of unfinished tasks that roll over to tomorrow, in list order.
    public var carryingOver: [String]
    /// Focus phases that ran to their end today.
    public var focusSessions: Int
    /// Minutes of completed focus time today.
    public var focusMinutes: Int
    /// Study minutes, sessions and points from the modules that keep them
    /// (`ProviderSnapshot.study`); nil when none does, and the review falls
    /// back to focus sessions.
    public var study: StudyDayTally?
    /// What other modules' goals got done today, such as cards reviewed.
    public var progress: [DayReviewCount]
    /// One or two encouraging sentences; nil until Claude (or the fallback) answers.
    public var summary: String?

    public init(
        date: PlannerDayKey,
        done: [String],
        carryingOver: [String],
        focusSessions: Int,
        focusMinutes: Int,
        study: StudyDayTally? = nil,
        progress: [DayReviewCount] = [],
        summary: String? = nil
    ) {
        self.date = date
        self.done = done
        self.carryingOver = carryingOver
        self.focusSessions = focusSessions
        self.focusMinutes = focusMinutes
        self.study = study
        self.progress = progress
        self.summary = summary
    }

    /// Reviews saved before study stats existed have no `progress` key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(PlannerDayKey.self, forKey: .date)
        done = try container.decode([String].self, forKey: .done)
        carryingOver = try container.decode([String].self, forKey: .carryingOver)
        focusSessions = try container.decode(Int.self, forKey: .focusSessions)
        focusMinutes = try container.decode(Int.self, forKey: .focusMinutes)
        study = try container.decodeIfPresent(StudyDayTally.self, forKey: .study)
        progress = try container.decodeIfPresent([DayReviewCount].self, forKey: .progress) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
    }

    /// Whether there is anything to look back on at all.
    public var isEmpty: Bool {
        done.isEmpty && carryingOver.isEmpty && focusSessions == 0
            && (study?.minutes ?? 0) == 0 && !progress.contains { $0.count > 0 }
    }
}

/// How much of one shared goal got done today, e.g. 112 cards of "Anki
/// reviews". Stores the title and unit rather than the live item, so a saved
/// review reads the same later.
public struct DayReviewCount: Hashable, Codable, Sendable {
    public var title: String
    public var count: Int
    /// Plural noun for the count, e.g. "cards".
    public var unit: String

    public init(title: String, count: Int, unit: String) {
        self.title = title
        self.count = count
        self.unit = unit
    }
}

/// One figure on the Wrap Up card: an SF Symbol, a short caption and a tooltip.
public struct DayReviewStat: Hashable, Sendable {
    public var symbol: String
    public var text: String
    public var help: String

    public init(symbol: String, text: String, help: String) {
        self.symbol = symbol
        self.text = text
        self.help = help
    }
}

/// Completed focus phases, stamped with when each one ended.
///
/// `FocusTimer.completedFocusCount` is a lifetime total; the review needs a
/// per-day count, so the focus store records each completion here too.
/// Only recent days are kept so the log never grows without bound.
public struct FocusSessionLog: Hashable, Codable, Sendable {
    public struct Session: Hashable, Codable, Sendable {
        public let endedAt: Date
        public let duration: TimeInterval

        public init(endedAt: Date, duration: TimeInterval) {
            self.endedAt = endedAt
            self.duration = duration
        }
    }

    /// Days of history kept by `record`.
    public static let retentionDays = 7

    public private(set) var sessions: [Session]

    public init(sessions: [Session] = []) {
        self.sessions = sessions
    }

    /// Adds the focus phases among `completions` (breaks are ignored) and
    /// drops sessions older than `retentionDays` before `now`.
    public mutating func record(
        _ completions: [FocusPhaseCompletion],
        config: FocusTimerConfig,
        now: Date,
        calendar: Calendar = .current
    ) {
        sessions += completions
            .filter { $0.phase == .focus }
            .map { Session(endedAt: $0.endedAt, duration: config.focusDuration) }
        let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: calendar.startOfDay(for: now)) ?? now
        sessions.removeAll { $0.endedAt < cutoff }
    }

    /// Sessions that ended on `day` in `calendar`'s time zone.
    public func sessions(on day: PlannerDayKey, calendar: Calendar = .current) -> [Session] {
        sessions.filter { PlannerDayKey(date: $0.endedAt, calendar: calendar) == day }
    }
}

/// Pure logic behind the End-of-Day Review: aggregation, the Claude prompt
/// and CLI flags, cleanup of the answer, and a local fallback line.
public enum DayReviewer {
    /// Fast model alias; the answer is a sentence or two.
    public static let model = "haiku"
    /// From this local hour on, "Wrap up" is offered prominently.
    public static let wrapUpHour = 17
    /// Longest summary the review card shows before it is cut at a word.
    public static let maximumSummaryLength = 220

    /// Whether the day is far enough along to suggest wrapping up.
    public static func isWrapUpTime(_ now: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: now) >= wrapUpHour
    }

    /// Builds the review for `day`'s checklist and today's focus sessions,
    /// plus what other modules share: their study `tally` and how far each
    /// `progress` goal got (goals with nothing due today are left out).
    public static func review(
        of day: PlannerDay,
        focusLog: FocusSessionLog,
        study tally: StudyDayTally? = nil,
        progress: [ProgressItem] = [],
        calendar: Calendar = .current
    ) -> DayReview {
        let sessions = focusLog.sessions(on: day.date, calendar: calendar)
        let minutes = sessions.reduce(0) { $0 + $1.duration } / 60
        return DayReview(
            date: day.date,
            done: day.items.filter(\.isDone).map(\.title),
            carryingOver: day.items.filter { !$0.isDone }.map(\.title),
            focusSessions: sessions.count,
            focusMinutes: Int(minutes.rounded()),
            study: tally,
            progress: progress
                .filter { $0.target > 0 || $0.completed > 0 }
                .map { DayReviewCount(title: $0.title, count: max($0.completed, 0), unit: $0.unit) }
        )
    }

    /// The figures under the summary, in order: study time and sessions (or
    /// focus sessions when no module keeps a study tally), each shared goal's
    /// count, then points earned.
    public static func stats(for review: DayReview) -> [DayReviewStat] {
        var stats: [DayReviewStat] = []
        if let study = review.study {
            let text = study.minutes > 0 || study.sessions > 0
                ? "\(duration(minutes: study.minutes)) · \(count(study.sessions, "session"))"
                : "No study yet"
            stats.append(DayReviewStat(symbol: "book.closed.fill", text: text,
                                       help: "Time studied today and study sessions finished"))
        } else {
            let text = review.focusSessions > 0
                ? "\(count(review.focusSessions, "focus session")) · \(duration(minutes: review.focusMinutes))"
                : "No focus sessions today"
            stats.append(DayReviewStat(symbol: "scope", text: text, help: "Focus sessions completed today"))
        }
        for goal in review.progress {
            stats.append(DayReviewStat(symbol: "checkmark.circle", text: "\(goal.count) \(goal.unit)",
                                       help: "\(goal.title): \(goal.count) \(goal.unit) done today"))
        }
        if let points = review.study?.points {
            stats.append(DayReviewStat(symbol: "star.fill", text: "\(points) pts",
                                       help: "Study points earned today, to spend on your pet's outfits"))
        }
        return stats
    }

    /// "45m", "2h", "1h 15m".
    static func duration(minutes: Int) -> String {
        let minutes = max(minutes, 0)
        guard minutes >= 60 else { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    /// Arguments inserted before `-- <prompt>`. No tools and no MCP servers:
    /// the CLI can only answer with text.
    public static func extraArguments() -> [String] {
        ["--model", model, "--tools", "", "--strict-mcp-config"]
    }

    /// The prompt for `claude -p`.
    public static func prompt(for review: DayReview) -> String {
        func list(_ titles: [String]) -> String {
            titles.isEmpty ? "- none" : titles.map { "- \($0)" }.joined(separator: "\n")
        }
        return """
        Someone is wrapping up their workday. Write one or two short, warm, specific sentences \
        that acknowledge what they finished and set up tomorrow. \
        No greeting, no emoji, no lists, no quotes, under 40 words. Plain text only.

        Done today:
        \(list(review.done))

        Carrying over to tomorrow:
        \(list(review.carryingOver))

        Focus sessions completed: \(review.focusSessions) (\(review.focusMinutes) minutes)\(studyLines(review))
        """
    }

    /// Study tally and shared goals for the prompt; empty when there are none.
    private static func studyLines(_ review: DayReview) -> String {
        var lines: [String] = []
        if let study = review.study {
            lines.append("Studied: \(study.minutes) minutes over \(study.sessions) sessions, \(study.points) points earned")
        }
        lines += review.progress.map { "\($0.title): \($0.count) \($0.unit) done" }
        return lines.map { "\n" + $0 }.joined()
    }

    /// Turns Claude's answer into a card-sized summary.
    ///
    /// Strips code fences, wrapping quotes, and line breaks, keeps at most
    /// two sentences, and cuts overly long text at a word boundary with an
    /// ellipsis. Returns nil when nothing readable remains.
    public static func summary(from text: String) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "```", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let quotes: Set<Character> = ["\"", "'", "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
        while let first = cleaned.first, let last = cleaned.last, cleaned.count > 1, quotes.contains(first), quotes.contains(last) {
            cleaned = String(cleaned.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !cleaned.isEmpty else { return nil }

        var sentences: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..., options: .bySentences) { sentence, _, _, stop in
            if let sentence = sentence?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty { sentences.append(sentence) }
            if sentences.count == 2 { stop = true }
        }
        let joined = sentences.isEmpty ? cleaned : sentences.joined(separator: " ")
        guard joined.count > maximumSummaryLength else { return joined }
        let prefix = joined.prefix(maximumSummaryLength - 1)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "\u{2026}"
    }

    /// A friendly line written locally, used when Claude is unavailable or
    /// its answer is unusable, so the review never ends in an error.
    public static func fallbackSummary(for review: DayReview) -> String {
        let finished = review.done.count
        let focus = review.focusSessions == 1 ? "1 focus session" : "\(review.focusSessions) focus sessions"
        switch (finished, review.carryingOver.count) {
        case (0, 0):
            if let minutes = review.study?.minutes, minutes > 0 {
                return "You put in \(duration(minutes: minutes)) of study today. Rest up and start fresh tomorrow."
            }
            return review.focusSessions > 0
                ? "You put in \(focus) today. Rest up and start fresh tomorrow."
                : "A quiet day. Rest up and start fresh tomorrow."
        case (0, _):
            return "Not every day is a checklist day. Tomorrow starts with \(taskCount(review.carryingOver.count)) ready to go."
        case (_, 0):
            return "You cleared all \(taskCount(finished)) today. Enjoy the evening."
        default:
            return "You finished \(taskCount(finished)) today. \(taskCount(review.carryingOver.count).capitalizedFirst) will be waiting tomorrow."
        }
    }

    private static func taskCount(_ count: Int) -> String {
        count == 1 ? "1 task" : "\(count) tasks"
    }
}

/// Stores one review per day as `yyyy-MM-dd.json` in a directory.
/// Not thread-safe; own it from a single actor.
public final class DayReviewRepository {
    public let directory: URL
    private let fileManager: FileManager

    /// The folder in an edition's storage, `Application Support/<edition>/Reviews`.
    public static let folderName = "Reviews"

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// The edition's review folder.
    public convenience init(storage: EditionStorage) {
        self.init(directory: storage.folder(Self.folderName))
    }

    public func fileURL(for date: PlannerDayKey) -> URL {
        directory.appendingPathComponent("\(date.rawValue).json", isDirectory: false)
    }

    /// The saved review, or nil if none exists. Throws on unreadable files.
    public func load(_ date: PlannerDayKey) throws -> DayReview? {
        let url = fileURL(for: date)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DayReview.self, from: Data(contentsOf: url))
    }

    /// Writes atomically, replacing an earlier review of the same day.
    public func save(_ review: DayReview) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(review).write(to: fileURL(for: review.date), options: .atomic)
    }
}

public extension DayReview {
    /// The review of `PlannerDay.sample` (of `kind`) for demo mode, with a canned
    /// summary so no Claude call is needed. Pass shared `progress` and a
    /// `study` tally to preview a study day's wrap-up.
    static func sample(
        on date: PlannerDayKey,
        kind: PlannerSampleDay = .work,
        study: StudyDayTally? = nil,
        progress: [ProgressItem] = [],
        calendar: Calendar = .current
    ) -> DayReview {
        var review = DayReviewer.review(of: .sample(on: date, kind: kind, calendar: calendar),
                                        focusLog: FocusSessionLog(), study: study, progress: progress,
                                        calendar: calendar)
        review.focusSessions = 3
        review.focusMinutes = 75
        review.summary = switch kind {
        case .work:
            "Strong day: the pull request, design feedback, and flights are all off your plate. "
                + "Start tomorrow with the planner beta while your focus is fresh."
        case .medicine:
            "Solid study day: First Aid, the lecture recording, and the shift email are done. "
                + "Start tomorrow with UWorld while your focus is fresh."
        }
        return review
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
