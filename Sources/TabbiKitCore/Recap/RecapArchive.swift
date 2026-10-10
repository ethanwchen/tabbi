import Foundation

/// Every weekly recap built so far, plus what the user has already been
/// shown, saved as one small versioned JSON file in the edition's storage.
///
/// The archive decides which weeks still need building and which recap is
/// new to the user, so the app's store only reads the activity log, builds
/// what `weeksToBuild(at:)` asks for and saves. Weeks with nothing logged
/// are never kept: a fresh install or a week off shows no card at all.
public struct RecapArchive: Codable, Hashable, Sendable {
    /// Two years of weeks; the oldest fall off first.
    public static let capacity = 104

    /// How many weeks back a check catches up on, so a few weeks away from
    /// the Mac still leave their recaps in the list.
    public static let catchUpWeeks = 4

    /// Newest first, one per week, never empty weeks.
    public private(set) var recaps: [WeeklyRecap]
    /// The newest week built after it was over, so its numbers are final.
    /// Weeks up to it are never built again.
    public private(set) var settledWeek: RecapWeek?
    /// The newest week whose recap the user has seen in the notch.
    public private(set) var seenWeek: RecapWeek?
    /// The newest week a notification went out for.
    public private(set) var notifiedWeek: RecapWeek?

    public init(recaps: [WeeklyRecap] = [], settledWeek: RecapWeek? = nil, seenWeek: RecapWeek? = nil,
                notifiedWeek: RecapWeek? = nil) {
        var byWeek: [RecapWeek: WeeklyRecap] = [:]
        for recap in recaps where !recap.isEmpty { byWeek[recap.week] = byWeek[recap.week] ?? recap }
        self.recaps = Array(byWeek.values.sorted { $0.week > $1.week }.prefix(Self.capacity))
        self.settledWeek = settledWeek
        self.seenWeek = seenWeek
        self.notifiedWeek = notifiedWeek
    }

    /// The weeks to build from the activity log at `now`, oldest first: the
    /// newest ready week (see `RecapWeek.latestReady`) and up to
    /// `catchUpWeeks - 1` before it, skipping weeks already settled. The
    /// newest ready week stays on the list until a build after its Sunday
    /// ends, so activity on Sunday night still makes it in.
    public func weeksToBuild(at now: Date, readyHour: Int = RecapWeek.defaultReadyHour,
                             calendar: Calendar = .current) -> [RecapWeek] {
        let latest = RecapWeek.latestReady(at: now, readyHour: readyHour, calendar: calendar)
        return (0..<Self.catchUpWeeks).reversed()
            .map { latest.adding(weeks: -$0, calendar: calendar) }
            .filter { week in settledWeek.map { week > $0 } ?? true }
    }

    /// Saves `recap` (replacing an earlier build of its week) unless the week
    /// was empty, and settles its week when `now` is past its Sunday.
    /// Returns whether anything changed, so the caller saves only then.
    @discardableResult
    public mutating func record(_ recap: WeeklyRecap, builtAt now: Date, calendar: Calendar = .current) -> Bool {
        let before = self
        recaps.removeAll { $0.week == recap.week }
        if !recap.isEmpty {
            recaps.append(recap)
            recaps.sort { $0.week > $1.week }
            recaps = Array(recaps.prefix(Self.capacity))
        }
        let over = recap.week.adding(weeks: 1, calendar: calendar).start.startDate(calendar: calendar)
        if now >= over, settledWeek.map({ recap.week > $0 }) ?? true { settledWeek = recap.week }
        return self != before
    }

    /// The newest recap, when the user hasn't seen it yet: the card the open
    /// notch shows once. Only the newest counts, so catching up after weeks
    /// away shows one card, not a pile, and `skipStaleWeeks(at:)` keeps an
    /// old week from showing when the latest one had nothing logged.
    public var unseen: WeeklyRecap? {
        guard let newest = recaps.first, seenWeek.map({ newest.week > $0 }) ?? true else { return nil }
        return newest
    }

    /// The newest recap, when no notification has gone out for it and the
    /// user hasn't already seen it.
    public var unnotified: WeeklyRecap? {
        guard let newest = unseen, notifiedWeek.map({ newest.week > $0 }) ?? true else { return nil }
        return newest
    }

    /// Records that the user has seen `week`'s recap (and so every older one).
    @discardableResult
    public mutating func markSeen(_ week: RecapWeek) -> Bool {
        guard seenWeek.map({ week > $0 }) ?? true else { return false }
        seenWeek = week
        return true
    }

    /// Marks every week before the newest ready one at `now` as seen without
    /// showing it, so after weeks away only the week that just ended can
    /// show, never a recap from a month ago. They stay in the list.
    @discardableResult
    public mutating func skipStaleWeeks(at now: Date, readyHour: Int = RecapWeek.defaultReadyHour,
                                        calendar: Calendar = .current) -> Bool {
        let latest = RecapWeek.latestReady(at: now, readyHour: readyHour, calendar: calendar)
        return markSeen(latest.adding(weeks: -1, calendar: calendar))
    }

    /// Takes in `other`'s recaps and markers (another Mac's, or a copy read
    /// back from disk). Markers keep the newer week, so a merge never makes
    /// a week the user has seen show again; a week both have keeps this
    /// archive's recap.
    @discardableResult
    public mutating func merge(_ other: RecapArchive) -> Bool {
        let before = self
        let mine = Set(recaps.map(\.week))
        self = RecapArchive(recaps: recaps + other.recaps.filter { !mine.contains($0.week) },
                            settledWeek: Self.newer(settledWeek, other.settledWeek),
                            seenWeek: Self.newer(seenWeek, other.seenWeek),
                            notifiedWeek: Self.newer(notifiedWeek, other.notifiedWeek))
        return self != before
    }

    private static func newer(_ lhs: RecapWeek?, _ rhs: RecapWeek?) -> RecapWeek? {
        guard let lhs, let rhs else { return lhs ?? rhs }
        return max(lhs, rhs)
    }

    /// Records that a notification went out for `week`'s recap.
    @discardableResult
    public mutating func markNotified(_ week: RecapWeek) -> Bool {
        guard notifiedWeek.map({ week > $0 }) ?? true else { return false }
        notifiedWeek = week
        return true
    }

    /// The saved recap for `week`, if that week had anything logged.
    public func recap(for week: RecapWeek) -> WeeklyRecap? { recaps.first { $0.week == week } }

    /// `recap`'s warm line, measured against the weeks saved before it.
    public func cheer(for recap: WeeklyRecap, calendar: Calendar = .current) -> RecapCheer {
        recap.cheer(comparedTo: recaps, calendar: calendar)
    }

    // MARK: Persistence

    /// The folder in an edition's storage, `Application Support/<edition>/Recaps`.
    public static let folderName = "Recaps"
    public static let fileName = "recaps.json"

    /// The archive file format. Version 1 is the first.
    public static let schema = VersionedJSON(current: 1)

    private enum CodingKeys: String, CodingKey { case recaps, settledWeek, seenWeek, notifiedWeek }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            recaps: try container.decodeIfPresent([WeeklyRecap].self, forKey: .recaps) ?? [],
            settledWeek: try? container.decodeIfPresent(RecapWeek.self, forKey: .settledWeek),
            seenWeek: try? container.decodeIfPresent(RecapWeek.self, forKey: .seenWeek),
            notifiedWeek: try? container.decodeIfPresent(RecapWeek.self, forKey: .notifiedWeek)
        )
    }

    /// The archive file in `directory`.
    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Loads the archive at `url`, or returns nil when there is none yet.
    /// A corrupt file throws so the caller can decide not to overwrite it.
    public static func load(from url: URL) throws -> RecapArchive? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try schema.decode(RecapArchive.self, from: Data(contentsOf: url))
    }

    /// Writes atomically, creating the parent folder if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Self.schema.encode(self, using: encoder).write(to: url, options: .atomic)
    }
}
