import Foundation

/// What kind of thing happened, as an open string id such as
/// `focus.completed`, so a new module can log its own kinds without a
/// shared enum to edit. Kinds several modules log live here.
public struct ActivityKind: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral,
                            CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// A focus stretch ended (finished or stopped early, see `outcome`);
    /// the quantity is the minutes focused.
    public static let focusCompleted: ActivityKind = "focus.completed"
    /// A break ended; the quantity is its minutes.
    public static let breakTaken: ActivityKind = "break.taken"
    /// Flashcards were answered; the quantity is the number of cards.
    public static let cardsReviewed: ActivityKind = "cards.reviewed"
    /// A task was checked off; `subject` is the task's id.
    public static let taskCompleted: ActivityKind = "task.completed"
}

/// One thing that happened, for gamification, insights and the pet: a focus
/// stretch, a break, cards reviewed, a task done.
///
/// `ProviderSnapshot` says what is true now; the activity log says what
/// happened, so a streak or a weekly chart never has to reach into the store
/// of the module that did it. Records only ever get appended. They stay on
/// this Mac, in the edition's folder.
public struct ActivityRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// The module that logged it (the one that owns the timer or the list).
    public let source: ModuleID
    public let kind: ActivityKind
    /// Whole seconds, so a record reads back from its ISO 8601 day file
    /// exactly as it was logged.
    public let start: Date
    /// Equal to `start` for something that happened at one moment.
    public let end: Date
    /// How much, in `unit`: minutes, cards, tasks.
    public let quantity: Double?
    public let unit: ActivityUnit?
    /// The stable id of what it was about (a task's id), so a reader can tell
    /// a task checked, unchecked and checked again from two tasks.
    public let subject: String?
    /// Small, module-defined details, such as the study method.
    public let metadata: [String: String]

    public init(id: UUID = UUID(), source: ModuleID, kind: ActivityKind, start: Date, end: Date? = nil,
                quantity: Double? = nil, unit: ActivityUnit? = nil, subject: String? = nil,
                metadata: [String: String] = [:]) {
        self.id = id
        self.source = source
        self.kind = kind
        let start = Self.wholeSeconds(start)
        self.start = start
        self.end = max(Self.wholeSeconds(end ?? start), start)
        self.quantity = quantity
        self.unit = unit
        self.subject = subject
        self.metadata = metadata
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded())
    }

    /// The local day the record counts toward: the day it ended.
    public func day(calendar: Calendar = .current) -> PlannerDayKey {
        PlannerDayKey(date: end, calendar: calendar)
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, kind, start, end, quantity, unit, subject, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            source: try container.decode(ModuleID.self, forKey: .source),
            kind: try container.decode(ActivityKind.self, forKey: .kind),
            start: try container.decode(Date.self, forKey: .start),
            end: try container.decodeIfPresent(Date.self, forKey: .end),
            quantity: try container.decodeIfPresent(Double.self, forKey: .quantity),
            unit: try container.decodeIfPresent(ActivityUnit.self, forKey: .unit),
            subject: try container.decodeIfPresent(String.self, forKey: .subject),
            metadata: try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        )
    }
}

/// The unit of an `ActivityRecord.quantity`, open like `ActivityKind`.
public struct ActivityUnit: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let minutes: ActivityUnit = "min"
    public static let cards: ActivityUnit = "cards"
}

/// Metadata keys several modules use.
public enum ActivityMetadata {
    /// How a focus stretch ended: `completed`, `stopped`, `skipped` or `abandoned`.
    public static let outcome = "outcome"
    /// The study method or timer that ran it, such as `pomodoro`.
    public static let method = "method"
}
