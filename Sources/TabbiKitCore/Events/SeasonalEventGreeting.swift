import Foundation

/// Remembers which seasonal event runs the pet has already greeted, so each
/// run gets one quiet moment beside the closed notch (a little dance) and
/// never another, even across relaunches. Saved as
/// `<edition>/Pet/events.json`.
public struct SeasonalEventGreeting: Codable, Hashable, Sendable {
    /// Version 1 is the first format.
    public static let schema = VersionedJSON(current: 1)

    /// Run ids (`SeasonalEventOccurrence.id(calendar:)`) already greeted.
    public private(set) var greetedRuns: Set<String>

    public init(greetedRuns: Set<String> = []) {
        self.greetedRuns = greetedRuns
    }

    /// The runs going on at `now` that have not been greeted yet, the one
    /// ending soonest first. Empty between events and once greeted.
    public func due(at now: Date, catalog: SeasonalEventCatalog = .bundled,
                    calendar: Calendar = .current) -> [SeasonalEventOccurrence] {
        catalog.active(at: now, calendar: calendar).filter { !greetedRuns.contains($0.id(calendar: calendar)) }
    }

    /// Greets every run due at `now` at once, so two overlapping events
    /// share one moment, and returns them. Ids of runs that are over are
    /// dropped: a run id carries its year, so it can never come back.
    @discardableResult
    public mutating func greet(at now: Date, catalog: SeasonalEventCatalog = .bundled,
                               calendar: Calendar = .current) -> [SeasonalEventOccurrence] {
        let due = due(at: now, catalog: catalog, calendar: calendar)
        let active = Set(catalog.active(at: now, calendar: calendar).map { $0.id(calendar: calendar) })
        greetedRuns = greetedRuns.intersection(active).union(due.map { $0.id(calendar: calendar) })
        return due
    }

    /// When a greeting can next become due: the start of the next run, so
    /// Tabbi left open over an event's first midnight still greets it.
    public static func nextCheck(after now: Date, catalog: SeasonalEventCatalog = .bundled,
                                 calendar: Calendar = .current) -> Date? {
        catalog.next(after: now, calendar: calendar)?.start
    }

    private enum CodingKeys: String, CodingKey { case greetedRuns }

    /// Reads leniently: a damaged list greets again rather than fail.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        greetedRuns = (try? container.decodeIfPresent(Set<String>.self, forKey: .greetedRuns)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(greetedRuns.sorted(), forKey: .greetedRuns)
    }

    public static func load(from url: URL) throws -> SeasonalEventGreeting? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try schema.decode(SeasonalEventGreeting.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.schema.encode(self).write(to: url, options: .atomic)
    }
}
