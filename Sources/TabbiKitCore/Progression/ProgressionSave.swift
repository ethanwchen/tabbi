import Foundation

/// What the Goals section keeps on disk beside the pet's save, as
/// `Pet/progression.json`: each track's best count so far, the badge tiers
/// reached and when, the months whose quests were all done, which tiers
/// the user has already seen, and the Study Level: the highest reached,
/// the highest seen on the Goals shelf and the nameplate color picked.
///
/// The activity log can tell all of it again, except when day files were
/// deleted by hand; the save makes sure that never takes progress back.
/// It stays on this Mac and is never synced, like the pet's journal.
/// Decoding is forgiving: ids from a newer build are dropped.
public struct ProgressionSave: Hashable, Codable, Sendable {
    /// The highest count each track has shown, in its unit.
    public var best: [ProgressTrack: Int]
    /// When each badge tier was first reached.
    public var reached: [ProgressBadge: Date]
    /// Months whose three quests were all finished.
    public var completedMonths: Set<MonthKey>
    /// Badge tiers the user has seen on the Goals shelf; the rest of
    /// `reached` wear a "new" dot.
    public var seen: Set<ProgressBadge>
    /// The highest Study Level ever reached (`StudyLevel`). The level shown
    /// is never below it, so neither deleted day files nor a future change
    /// to the curve can take a level away.
    public var level: Int
    /// The highest Study Level the user has seen on the Goals shelf; a
    /// higher `level` puts a dot on the Goals pill.
    public var levelSeen: Int
    /// The nameplate color picked in the Closet, nil for plain.
    public var nameplate: Nameplate?

    public init(best: [ProgressTrack: Int] = [:], reached: [ProgressBadge: Date] = [:],
                completedMonths: Set<MonthKey> = [], seen: Set<ProgressBadge> = [], level: Int = 0,
                levelSeen: Int = 0, nameplate: Nameplate? = nil) {
        self.best = best.filter { $0.value > 0 }
        self.reached = reached
        self.completedMonths = completedMonths
        self.seen = seen.intersection(reached.keys)
        self.level = max(0, level)
        self.levelSeen = min(max(0, levelSeen), max(0, level))
        self.nameplate = nameplate == .plain ? nil : nameplate
    }

    /// The format of `progression.json`. Version 1 is the first; a file
    /// without a version reads as the same fields. Version 2 adds the
    /// Study Level (`level`, `levelSeen`, `nameplate`); a version 1 file
    /// has none of them, which reads as level 0 never seen, so the first
    /// launch lands a long-time user at their real level quietly, with
    /// the Goals pill's dot.
    public static let schema = VersionedJSON(current: 2)

    public static func load(from url: URL) throws -> ProgressionSave? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try schema.decode(ProgressionSave.self, from: Data(contentsOf: url), using: decoder)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try Self.schema.encode(self, using: encoder)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }

    private enum CodingKeys: String, CodingKey { case best, reached, completedMonths, seen, level, levelSeen, nameplate }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let best = (try? container.decodeIfPresent([String: Int].self, forKey: .best)) ?? [:]
        let reached = (try? container.decodeIfPresent([String: Date].self, forKey: .reached)) ?? [:]
        let months = (try? container.decodeIfPresent([String].self, forKey: .completedMonths)) ?? []
        let seen = (try? container.decodeIfPresent([String].self, forKey: .seen)) ?? []
        let level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
        let levelSeen = (try? container.decodeIfPresent(Int.self, forKey: .levelSeen)) ?? 0
        let nameplate = (try? container.decodeIfPresent(String.self, forKey: .nameplate)).flatMap { $0 }
        self.init(
            best: Dictionary(best.compactMap { key, value in ProgressTrack(rawValue: key).map { ($0, value) } },
                             uniquingKeysWith: max),
            reached: Dictionary(reached.compactMap { key, value in ProgressBadge(id: key).map { ($0, value) } },
                                uniquingKeysWith: min),
            completedMonths: Set(months.compactMap(MonthKey.init(rawValue:))),
            seen: Set(seen.compactMap(ProgressBadge.init(id:))),
            level: level,
            levelSeen: levelSeen,
            nameplate: nameplate.flatMap(Nameplate.init(rawValue:))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: best.map { ($0.key.rawValue, $0.value) }), forKey: .best)
        try container.encode(Dictionary(uniqueKeysWithValues: reached.map { ($0.key.id, $0.value) }), forKey: .reached)
        try container.encode(completedMonths.map(\.rawValue).sorted(), forKey: .completedMonths)
        try container.encode(seen.map(\.id).sorted(), forKey: .seen)
        try container.encode(level, forKey: .level)
        try container.encode(levelSeen, forKey: .levelSeen)
        try container.encodeIfPresent(nameplate?.rawValue, forKey: .nameplate)
    }
}
