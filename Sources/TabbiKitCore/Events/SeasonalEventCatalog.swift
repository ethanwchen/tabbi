import Foundation

/// The year of seasonal events, read from an `events.v1` JSON file: each
/// event's id, name, tagline, calendar, first and last day, and the items it
/// offers with the focused minutes that earn each one.
///
/// Events are data so a new season is a JSON edit, and so the Mac app and
/// the Windows port run the same calendar.
public struct SeasonalEventCatalog: Hashable, Sendable {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case unsupportedSchema(String)
        case invalidValue(path: String, reason: String)

        public var description: String {
            switch self {
            case .unsupportedSchema(let schema): "Unsupported schema \"\(schema)\"; expected \"\(SeasonalEventCatalog.schemaName)\""
            case let .invalidValue(path, reason): "\(path): \(reason)"
            }
        }
    }

    public static let schemaName = "events.v1"

    /// Every event, in file order.
    public let events: [SeasonalEvent]

    public init(events: [SeasonalEvent]) {
        self.events = events
    }

    /// The year of events that ships with Tabbi, `events.json`, described
    /// by `shared/schemas/events.v1.schema.json`. Read once; a broken file
    /// is a build mistake, which the tests catch.
    public static let bundled: SeasonalEventCatalog = {
        guard let url = KitResources.bundle?.url(forResource: "events", withExtension: "json") else {
            preconditionFailure("Missing events.json")
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid events.json: \(error)")
        }
    }()

    /// The event with `id`, if the catalog has one.
    public func event(id: String) -> SeasonalEvent? {
        events.first { $0.id == id }
    }

    /// The runs going on at `date`, the one ending soonest first, so a short
    /// event inside a longer one gets the spotlight while it lasts.
    public func active(at date: Date, calendar: Calendar = .current) -> [SeasonalEventOccurrence] {
        events.compactMap { $0.occurrence(containing: date, calendar: calendar) }
            .sorted { ($0.end, $0.event.id) < ($1.end, $1.event.id) }
    }

    /// The next run to start after `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> SeasonalEventOccurrence? {
        events.compactMap { $0.nextOccurrence(after: date, calendar: calendar) }
            .min { ($0.start, $0.event.id) < ($1.start, $1.event.id) }
    }

    /// The event that offers `item`, if any.
    public func event(offering item: PetItem) -> SeasonalEvent? {
        events.first { event in event.rewards.contains { $0.item == item } }
    }

    // MARK: Decoding

    private struct File: Decodable {
        struct Reward: Decodable {
            let item: String
            let focusMinutes: Int
        }

        struct Event: Decodable {
            let id: String
            let name: String
            let tagline: String
            let calendar: SeasonalEventCalendar
            let start: SeasonalEventDay
            let end: SeasonalEventDay
            let rewards: [Reward]
        }

        let schema: String
        let events: [Event]
    }

    /// Parses and checks a file: its schema version, unique ids, real dates
    /// (never February 29, which most years lack), a name and tagline, and
    /// at least one known item per event, each offered by one event only,
    /// with goals that rise through the event and read cleanly
    /// (`SeasonalEventProgress.progress(of:)`).
    public static func decode(_ data: Data) throws -> SeasonalEventCatalog {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == schemaName else { throw LoadError.unsupportedSchema(file.schema) }
        func require(_ condition: Bool, _ path: String, _ reason: String) throws {
            if !condition { throw LoadError.invalidValue(path: path, reason: reason) }
        }
        var ids = Set<String>()
        var offered = Set<PetItem>()
        var events: [SeasonalEvent] = []
        for (index, entry) in file.events.enumerated() {
            let path = "events[\(index)]"
            try require(entry.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil,
                        "\(path).id", "must be lowercase words joined by hyphens")
            try require(ids.insert(entry.id).inserted, "\(path).id", "\"\(entry.id)\" is used twice")
            try require(!entry.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(path).name", "must not be empty")
            try require(!entry.tagline.trimmingCharacters(in: .whitespaces).isEmpty, "\(path).tagline", "must not be empty")
            for (name, day) in [("start", entry.start), ("end", entry.end)] {
                try require(isValid(day, in: entry.calendar), "\(path).\(name)", "not a day every year has")
            }
            try require(!entry.rewards.isEmpty, "\(path).rewards", "must offer at least one item")
            var rewards: [SeasonalEventReward] = []
            for (rewardIndex, reward) in entry.rewards.enumerated() {
                let rewardPath = "\(path).rewards[\(rewardIndex)]"
                guard let item = PetItem(id: reward.item) else {
                    throw LoadError.invalidValue(path: "\(rewardPath).item", reason: "no item \"\(reward.item)\"")
                }
                try require(offered.insert(item).inserted, "\(rewardPath).item", "\"\(reward.item)\" is offered twice")
                try require(reward.focusMinutes > 0, "\(rewardPath).focusMinutes", "must be above 0")
                try require(reward.focusMinutes < SeasonalEventProgress.hourLabelMinutes || reward.focusMinutes % 60 == 0,
                            "\(rewardPath).focusMinutes", "goals of two hours or more must be whole hours")
                try require(rewards.last.map { $0.focusMinutes < reward.focusMinutes } ?? true,
                            "\(rewardPath).focusMinutes", "must be above the item before it")
                rewards.append(SeasonalEventReward(item: item, focusMinutes: reward.focusMinutes))
            }
            events.append(SeasonalEvent(id: entry.id, name: entry.name, tagline: entry.tagline,
                                        calendar: entry.calendar, start: entry.start, end: entry.end,
                                        rewards: rewards))
        }
        return SeasonalEventCatalog(events: events)
    }

    /// Whether every year has `day`: months 1...12 and days up to the
    /// shortest length that month can have (28 for February, 29 for any
    /// Chinese month, which has 29 or 30 days).
    private static func isValid(_ day: SeasonalEventDay, in calendar: SeasonalEventCalendar) -> Bool {
        guard (1...12).contains(day.month), day.day >= 1 else { return false }
        switch calendar {
        case .gregorian:
            let shortest = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][day.month - 1]
            return day.day <= shortest
        case .chinese:
            return day.day <= 29
        }
    }
}
