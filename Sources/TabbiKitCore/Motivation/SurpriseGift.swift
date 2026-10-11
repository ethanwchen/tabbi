import Foundation

/// A fur color only a surprise gift brings, on top of the Closet's swatches.
public struct RareFur: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var color: PetColor

    public init(id: String, name: String, color: PetColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// The rare colors, in the order a collector would find them listed.
    /// Soft enough to keep every breed's face readable, and none of them
    /// pink, which would swallow the nose and cheeks.
    public static let all: [RareFur] = [
        RareFur(id: "mint", name: "Mint", color: PetColor(hex: "#A9DCC4")!),
        RareFur(id: "honey", name: "Honey", color: PetColor(hex: "#E6C36A")!),
        RareFur(id: "midnight", name: "Midnight", color: PetColor(hex: "#5C6A8E")!),
        RareFur(id: "moonstone", name: "Moonstone", color: PetColor(hex: "#D7DCE8")!),
    ]

    public static func named(_ id: String) -> RareFur? { all.first { $0.id == id } }
}

/// What the cat brings back. Gifts are earned by finishing focus sessions
/// only: never sold, never tied to payment, and nothing is ever spent to roll.
public enum SurpriseGift: Hashable, Sendable {
    /// A few bonus points for the Closet.
    case bonusPoints(Int)
    /// A rare fur color to keep.
    case rareFur(RareFur)
    /// Focused minutes added toward the seasonal event running now.
    case seasonMinutes(eventID: String, minutes: Int)

    /// What the gift is, short enough for one line in the coach's bubble.
    public var message: String {
        switch self {
        case .bonusPoints(let points): "A gift: \(points) bonus points"
        case .rareFur(let fur): "A gift: the rare \(fur.name) fur"
        case .seasonMinutes(_, let minutes): "A gift: \(minutes) min toward the event"
        }
    }
}

/// A gift as the cat hands it over, with the moment it came back. This is
/// what the app publishes, so whatever shows the pet (the coach's bubble,
/// the pet returning from an adventure) can show what it carries.
public struct SurpriseGiftDelivery: Hashable, Sendable {
    public var gift: SurpriseGift
    public var date: Date

    public init(gift: SurpriseGift, date: Date) {
        self.gift = gift
        self.date = date
    }
}

/// A gift given, kept so the same session can never pay twice.
public struct SurpriseGiftRecord: Codable, Hashable, Sendable {
    public var day: PlannerDayKey
    /// When the session that earned it ended.
    public var sessionEnd: Date
    /// `bonusPoints`, `rareFur` or `seasonMinutes`.
    public var kind: String
    /// The points or minutes, or the rare fur's id.
    public var value: String

    public init(day: PlannerDayKey, sessionEnd: Date, gift: SurpriseGift) {
        self.day = day
        self.sessionEnd = sessionEnd
        switch gift {
        case .bonusPoints(let points): (kind, value) = ("bonusPoints", String(points))
        case .rareFur(let fur): (kind, value) = ("rareFur", fur.id)
        case .seasonMinutes(let eventID, let minutes): (kind, value) = ("seasonMinutes", "\(eventID):\(minutes)")
        }
    }
}

/// The odds and sizes of surprise gifts, in one place for the tests and docs.
public enum SurpriseGiftRules {
    /// Shorter sessions never roll.
    public static let minimumMinutes = 15
    /// About one qualifying session in five brings a gift.
    public static let chance = 0.2
    /// After this many qualifying sessions in a row without a gift, the
    /// next one always brings one, so a long dry spell can't happen.
    public static let pityAfter = 7
    /// Bonus point sizes: a small treat next to a block's 35 points.
    public static let bonusPoints = [10, 15, 20]
    /// Minutes a seasonal gift adds toward the event's items.
    public static let seasonMinutes = 15
    /// How many records the history keeps.
    public static let historyLimit = 60
}

/// The persisted state behind surprise gifts: the pity counter, the daily
/// cap, the rare furs found and the last session rolled, so a restart or a
/// replayed session can never roll again.
public struct SurpriseGiftState: Codable, Hashable, Sendable {
    public static let schema = VersionedJSON(current: 1)

    /// Qualifying sessions since the last gift.
    public private(set) var dryRolls: Int
    /// When the last rolled session ended; older or equal sessions don't roll.
    public private(set) var lastRolledSessionEnd: Date?
    /// Rare fur ids found so far.
    public private(set) var rareFursFound: [String]
    /// Gifts given, newest last, capped at `SurpriseGiftRules.historyLimit`.
    public private(set) var history: [SurpriseGiftRecord]

    public init() {
        dryRolls = 0
        rareFursFound = []
        history = []
    }

    /// Two rare furs found, so a demo shows the Closet's Rare row.
    public static var demo: SurpriseGiftState {
        var state = SurpriseGiftState()
        state.rareFursFound = Array(RareFur.all.prefix(2).map(\.id))
        return state
    }

    /// The day of the last gift, for the daily cap.
    public var lastGiftDay: PlannerDayKey? { history.last?.day }

    /// The rare furs found so far, in catalog order.
    public var rareFurs: [RareFur] { RareFur.all.filter { rareFursFound.contains($0.id) } }

    /// Rolls for a gift for a focus session that ran to its end at
    /// `sessionEnd` after `focusMinutes` of focus. Returns the gift, or nil.
    ///
    /// Sessions shorter than `SurpriseGiftRules.minimumMinutes`, sessions
    /// no newer than the last one rolled, and sessions on a day that already
    /// had a gift don't roll and don't move the pity counter.
    /// `activeSeasonID` is the seasonal event running now, if any; a
    /// seasonal gift is only possible while one runs.
    public mutating func roll<G: RandomNumberGenerator>(
        sessionEnd: Date,
        focusMinutes: Int,
        activeSeasonID: String? = nil,
        calendar: Calendar = .current,
        using generator: inout G
    ) -> SurpriseGift? {
        guard focusMinutes >= SurpriseGiftRules.minimumMinutes,
              lastRolledSessionEnd.map({ sessionEnd > $0 }) ?? true else { return nil }
        lastRolledSessionEnd = sessionEnd
        let day = PlannerDayKey(date: sessionEnd, calendar: calendar)
        guard lastGiftDay != day else { return nil }

        let wins = dryRolls >= SurpriseGiftRules.pityAfter
            || Double.random(in: 0..<1, using: &generator) < SurpriseGiftRules.chance
        guard wins else {
            dryRolls += 1
            return nil
        }
        let gift = pickGift(activeSeasonID: activeSeasonID, using: &generator)
        dryRolls = 0
        if case .rareFur(let fur) = gift { rareFursFound.append(fur.id) }
        history.append(SurpriseGiftRecord(day: day, sessionEnd: sessionEnd, gift: gift))
        if history.count > SurpriseGiftRules.historyLimit {
            history.removeFirst(history.count - SurpriseGiftRules.historyLimit)
        }
        return gift
    }

    /// Rolls for the focus session behind `award`, credited at `date`.
    /// Only an award for sessions that ran to their end rolls (an early
    /// Stop never does), at the length of one of those sessions.
    public mutating func roll<G: RandomNumberGenerator>(
        after award: PetStudyAward,
        at date: Date,
        activeSeasonID: String? = nil,
        calendar: Calendar = .current,
        using generator: inout G
    ) -> SurpriseGift? {
        guard award.completedSessions > 0 else { return nil }
        return roll(sessionEnd: date, focusMinutes: award.minutes / award.completedSessions,
                    activeSeasonID: activeSeasonID, calendar: calendar, using: &generator)
    }

    /// Bonus points most of the time; a rare fur (while any is left) or
    /// seasonal minutes (while an event runs) now and then.
    private func pickGift<G: RandomNumberGenerator>(activeSeasonID: String?, using generator: inout G) -> SurpriseGift {
        let points = SurpriseGiftRules.bonusPoints.randomElement(using: &generator)!
        var options: [(weight: Double, gift: SurpriseGift)] = [(0.6, .bonusPoints(points))]
        if let fur = RareFur.all.first(where: { !rareFursFound.contains($0.id) }) {
            options.append((0.2, .rareFur(fur)))
        }
        if let activeSeasonID {
            options.append((0.2, .seasonMinutes(eventID: activeSeasonID, minutes: SurpriseGiftRules.seasonMinutes)))
        }
        var draw = Double.random(in: 0..<options.reduce(0) { $0 + $1.weight }, using: &generator)
        for option in options {
            if draw < option.weight { return option.gift }
            draw -= option.weight
        }
        return options[0].gift
    }

    /// The state as its versioned JSON file (`schemaVersion` stamped).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try Self.schema.encode(self, using: encoder)
    }

    /// Reads a file written by `encoded()`, running any migrations.
    public static func decode(_ data: Data) throws -> SurpriseGiftState {
        try schema.decode(SurpriseGiftState.self, from: data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dryRolls = try container.decodeIfPresent(Int.self, forKey: .dryRolls) ?? 0
        lastRolledSessionEnd = try container.decodeIfPresent(Date.self, forKey: .lastRolledSessionEnd)
        rareFursFound = try container.decodeIfPresent([String].self, forKey: .rareFursFound) ?? []
        history = try container.decodeIfPresent([SurpriseGiftRecord].self, forKey: .history) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case dryRolls, lastRolledSessionEnd, rareFursFound, history
    }
}
