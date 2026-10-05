import Foundation

/// Result of `requestPermission`. A native app (no `Origin` header) is
/// always trusted, so `granted` is the normal answer.
public struct AnkiPermission: Hashable, Sendable, Decodable {
    public let granted: Bool
    /// Whether the user configured an API key that every other call must send.
    public let requireAPIKey: Bool
    /// AnkiConnect API version; only present when granted.
    public let version: Int?

    public init(granted: Bool, requireAPIKey: Bool, version: Int?) {
        self.granted = granted
        self.requireAPIKey = requireAPIKey
        self.version = version
    }

    private enum CodingKeys: String, CodingKey {
        case permission, version
        // The add-on code sends `requireApikey`; its README says `requireApiKey`.
        case requireApikey, requireApiKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        granted = try c.decode(String.self, forKey: .permission) == "granted"
        requireAPIKey = try c.decodeIfPresent(Bool.self, forKey: .requireApikey)
            ?? c.decodeIfPresent(Bool.self, forKey: .requireApiKey)
            ?? false
        version = try c.decodeIfPresent(Int.self, forKey: .version)
    }
}

/// A deck from `deckNamesAndIds`. Names nest with `::`; ids are stable.
public struct AnkiDeck: Hashable, Sendable, Codable, Identifiable {
    public let id: Int64
    public let name: String

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }

    /// The last path component, e.g. "Cardio" for "Step1::Cardio".
    public var leafName: String {
        name.components(separatedBy: "::").last ?? name
    }

    /// Nesting depth: 0 for a top-level deck.
    public var depth: Int {
        name.components(separatedBy: "::").count - 1
    }
}

/// Due counts for one deck from `getDeckStats`. The numbers match Anki's
/// deck list: daily limits applied and child decks rolled up.
public struct AnkiDeckStats: Hashable, Sendable, Codable {
    public let deckID: Int64
    public let name: String
    public let newCount: Int
    public let learnCount: Int
    public let reviewCount: Int
    public let totalInDeck: Int

    public init(deckID: Int64, name: String, newCount: Int, learnCount: Int, reviewCount: Int, totalInDeck: Int) {
        self.deckID = deckID
        self.name = name
        self.newCount = newCount
        self.learnCount = learnCount
        self.reviewCount = reviewCount
        self.totalInDeck = totalInDeck
    }

    /// Everything Anki would show today.
    public var dueTotal: Int { newCount + learnCount + reviewCount }

    private enum CodingKeys: String, CodingKey {
        case deckID = "deck_id"
        case name
        case newCount = "new_count"
        case learnCount = "learn_count"
        case reviewCount = "review_count"
        case totalInDeck = "total_in_deck"
    }
}

/// A calendar day as AnkiConnect reports it ("2026-09-30"), already shifted
/// by the user's day-rollover hour. Kept as plain components so streak math
/// never crosses a time zone.
public struct AnkiDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`; returns nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The day containing `date` in `calendar`'s time zone, after shifting
    /// back by Anki's rollover hour (a review at 2am with a 4am rollover
    /// belongs to the previous day).
    public init(date: Date, rolloverHour: Int = 4, calendar: Calendar = .current) {
        let shifted = date.addingTimeInterval(-TimeInterval(rolloverHour) * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The day `offset` days later (negative for earlier).
    public func adding(days offset: Int) -> AnkiDay {
        let date = Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
        let moved = Self.utc.date(byAdding: .day, value: offset, to: date) ?? date
        let c = Self.utc.dateComponents([.year, .month, .day], from: moved)
        return AnkiDay(year: c.year ?? year, month: c.month ?? month, day: c.day ?? day)
    }

    public static func < (lhs: AnkiDay, rhs: AnkiDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

/// One row of `getNumCardsReviewedByDay`: `["2026-09-30", 412]`.
public struct AnkiDayCount: Hashable, Sendable, Codable {
    public let day: AnkiDay
    public let count: Int

    public init(day: AnkiDay, count: Int) {
        self.day = day
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let text = try c.decode(String.self)
        guard let day = AnkiDay(text) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad day \(text)")
        }
        self.day = day
        count = try c.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(day.description)
        try c.encode(count)
    }
}

/// One review-log row from `cardReviews`, decoded from AnkiConnect's
/// 9-tuple `(reviewTime ms, cardID, usn, ease, newIvl, lastIvl, factor, durationMs, type)`.
public struct AnkiReview: Hashable, Sendable, Codable {
    /// Review-log kinds as stored in Anki's `revlog.type` column.
    public enum Kind: Int, Hashable, Sendable, Codable {
        case learn = 0
        case review = 1
        case relearn = 2
        case filtered = 3
        case manual = 4
        case unknown = -1
    }

    /// Review id: the answer time in milliseconds since 1970. Also the
    /// exclusive `startID` cursor for incremental fetches.
    public let id: Int64
    public let cardID: Int64
    /// Answer button: 1 Again, 2 Hard, 3 Good, 4 Easy (0 for manual entries).
    public let ease: Int
    public let interval: Int
    public let lastInterval: Int
    public let factor: Int
    public let durationMilliseconds: Int
    public let kind: Kind

    public init(id: Int64, cardID: Int64, ease: Int, interval: Int, lastInterval: Int, factor: Int, durationMilliseconds: Int, kind: Kind) {
        self.id = id
        self.cardID = cardID
        self.ease = ease
        self.interval = interval
        self.lastInterval = lastInterval
        self.factor = factor
        self.durationMilliseconds = durationMilliseconds
        self.kind = kind
    }

    public var reviewedAt: Date { Date(timeIntervalSince1970: TimeInterval(id) / 1000) }

    /// True when the user pressed Again (a lapse for review cards).
    public var isFailure: Bool { ease == 1 }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        id = try c.decode(Int64.self)
        cardID = try c.decode(Int64.self)
        _ = try c.decode(Int.self) // usn: sync bookkeeping, unused
        ease = try c.decode(Int.self)
        interval = try c.decode(Int.self)
        lastInterval = try c.decode(Int.self)
        factor = try c.decode(Int.self)
        durationMilliseconds = try c.decode(Int.self)
        kind = Kind(rawValue: try c.decode(Int.self)) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(id)
        try c.encode(cardID)
        try c.encode(-1)
        try c.encode(ease)
        try c.encode(interval)
        try c.encode(lastInterval)
        try c.encode(factor)
        try c.encode(durationMilliseconds)
        try c.encode(kind.rawValue)
    }
}
