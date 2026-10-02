import Foundation

/// One study stretch in the saved log: a focus (or question review) phase
/// that ran for at least a minute, with the points it earned.
public struct StudyLogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var method: StudyMethodKind
    public var startedAt: Date
    public var endedAt: Date
    /// Whole minutes the clock ran, excluding pauses.
    public var minutes: Int
    /// Ran its full length, hit its card goal, or was a stopped Flowtime
    /// stretch; false for skipped or abandoned stretches.
    public var completed: Bool
    /// Cards answered, for an Anki sprint.
    public var cards: Int?
    /// Study points earned, fixed when logged so later rule changes never
    /// rewrite history.
    public var points: Int

    public init(
        id: UUID = UUID(),
        method: StudyMethodKind,
        startedAt: Date,
        endedAt: Date,
        minutes: Int,
        completed: Bool,
        cards: Int? = nil,
        points: Int
    ) {
        self.id = id
        self.method = method
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.minutes = max(minutes, 0)
        self.completed = completed
        self.cards = cards.map { max($0, 0) }
        self.points = max(points, 0)
    }

    /// The entry for a phase that ran, or nil for breaks and stretches under
    /// a minute, which are not study time. Points follow `PetPointsRules`.
    public init?(_ record: StudyPhaseRecord, id: UUID = UUID()) {
        guard !record.phase.isBreak, record.activeDuration.isFinite else { return nil }
        let minutes = Int(max(record.activeDuration, 0) / 60)
        guard minutes >= 1 else { return nil }
        let completed = record.outcome.countsAsDone
        self.init(
            id: id, method: record.method, startedAt: record.startedAt, endedAt: record.endedAt,
            minutes: minutes, completed: completed, cards: record.cards,
            points: PetPointsRules.points(forMinutes: minutes, completed: completed)
        )
    }

    // Decodes through the clamping init so a hand-edited file can't carry
    // negative minutes or points.
    private enum CodingKeys: String, CodingKey {
        case id, method, startedAt, endedAt, minutes, completed, cards, points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            method: try container.decode(StudyMethodKind.self, forKey: .method),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decode(Date.self, forKey: .endedAt),
            minutes: try container.decode(Int.self, forKey: .minutes),
            completed: try container.decode(Bool.self, forKey: .completed),
            cards: try container.decodeIfPresent(Int.self, forKey: .cards),
            points: try container.decode(Int.self, forKey: .points)
        )
    }
}

/// Study totals for one day.
public struct StudyDaySummary: Hashable, Sendable {
    public var minutes: Int
    /// Stretches that counted as done.
    public var completedSessions: Int
    public var points: Int

    public init(minutes: Int = 0, completedSessions: Int = 0, points: Int = 0) {
        self.minutes = minutes
        self.completedSessions = completedSessions
        self.points = points
    }
}

/// The persisted history of study stretches, and the points not yet handed
/// to the pet's `PetPointsLedger`.
///
/// The timer's `StudySession` only buffers phase records until
/// `takeLog()`; this log keeps them across launches, feeds the day's totals,
/// and holds earned points in `uncredited` until whoever owns the pet save
/// collects them with `takeUncredited()`. Keeping that hand-off explicit
/// means the Study timer never writes the pet save itself, so the save has
/// one writer and points are credited exactly once.
public struct StudyLog: Codable, Hashable, Sendable {
    /// The most entries kept; the oldest fall off first. Roughly a year of
    /// heavy daily use.
    public static let capacity = 3000

    /// Oldest first.
    public private(set) var entries: [StudyLogEntry]
    /// Entries whose points the pet ledger hasn't received yet, oldest first.
    public private(set) var uncredited: [StudyLogEntry]

    public init(entries: [StudyLogEntry] = [], uncredited: [StudyLogEntry] = []) {
        self.entries = Array(entries.suffix(Self.capacity))
        self.uncredited = Array(uncredited.suffix(Self.capacity))
    }

    /// Logs the study stretches among `records` (breaks and stretches under a
    /// minute are dropped) and returns the new entries.
    @discardableResult
    public mutating func record(_ records: [StudyPhaseRecord]) -> [StudyLogEntry] {
        let added = records.compactMap { StudyLogEntry($0) }
        guard !added.isEmpty else { return [] }
        entries = Array((entries + added).suffix(Self.capacity))
        uncredited = Array((uncredited + added.filter { $0.points > 0 }).suffix(Self.capacity))
        return added
    }

    /// Points waiting for the pet ledger.
    public var uncreditedPoints: Int { uncredited.reduce(0) { $0 + $1.points } }

    /// Hands the uncredited entries over (credit each with
    /// `PetPointsLedger.recordStudy(minutes:completed:)`) and clears them.
    public mutating func takeUncredited() -> [StudyLogEntry] {
        defer { uncredited.removeAll() }
        return uncredited
    }

    /// Totals for the stretches that ended on `day`'s calendar day.
    public func summary(on day: Date, calendar: Calendar = .current) -> StudyDaySummary {
        entries
            .filter { calendar.isDate($0.endedAt, inSameDayAs: day) }
            .reduce(into: StudyDaySummary()) { total, entry in
                total.minutes += entry.minutes
                total.points += entry.points
                if entry.completed { total.completedSessions += 1 }
            }
    }

    /// Every point the log has earned, credited or not.
    public var totalPoints: Int { entries.reduce(0) { $0 + $1.points } }

    // MARK: Persistence

    private enum CodingKeys: String, CodingKey { case entries, uncredited }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entries: try container.decodeIfPresent([StudyLogEntry].self, forKey: .entries) ?? [],
            uncredited: try container.decodeIfPresent([StudyLogEntry].self, forKey: .uncredited) ?? []
        )
    }

    /// Loads the log at `url`, or returns nil when there is none yet.
    /// A corrupt file throws so the caller can decide not to overwrite it.
    public static func load(from url: URL) throws -> StudyLog? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(StudyLog.self, from: Data(contentsOf: url))
    }

    /// Writes atomically, creating the parent folder if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
