import Foundation

/// What the Goals section keeps on disk beside the pet's save, as
/// `Pet/progression.json`: each track's best count so far, the badge tiers
/// reached and when, the months whose quests were all done, and which tiers
/// the user has already seen.
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

    public init(best: [ProgressTrack: Int] = [:], reached: [ProgressBadge: Date] = [:],
                completedMonths: Set<MonthKey> = [], seen: Set<ProgressBadge> = []) {
        self.best = best.filter { $0.value > 0 }
        self.reached = reached
        self.completedMonths = completedMonths
        self.seen = seen.intersection(reached.keys)
    }

    /// The format of `progression.json`. Version 1 is the first; a file
    /// without a version reads as the same fields.
    public static let schema = VersionedJSON(current: 1)

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

    private enum CodingKeys: String, CodingKey { case best, reached, completedMonths, seen }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let best = (try? container.decodeIfPresent([String: Int].self, forKey: .best)) ?? [:]
        let reached = (try? container.decodeIfPresent([String: Date].self, forKey: .reached)) ?? [:]
        let months = (try? container.decodeIfPresent([String].self, forKey: .completedMonths)) ?? []
        let seen = (try? container.decodeIfPresent([String].self, forKey: .seen)) ?? []
        self.init(
            best: Dictionary(best.compactMap { key, value in ProgressTrack(rawValue: key).map { ($0, value) } },
                             uniquingKeysWith: max),
            reached: Dictionary(reached.compactMap { key, value in ProgressBadge(id: key).map { ($0, value) } },
                                uniquingKeysWith: min),
            completedMonths: Set(months.compactMap(MonthKey.init(rawValue:))),
            seen: Set(seen.compactMap(ProgressBadge.init(id:)))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: best.map { ($0.key.rawValue, $0.value) }), forKey: .best)
        try container.encode(Dictionary(uniqueKeysWithValues: reached.map { ($0.key.id, $0.value) }), forKey: .reached)
        try container.encode(completedMonths.map(\.rawValue).sorted(), forKey: .completedMonths)
        try container.encode(seen.map(\.id).sorted(), forKey: .seen)
    }
}
