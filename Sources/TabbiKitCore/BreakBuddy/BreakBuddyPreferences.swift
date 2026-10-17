import Foundation

/// The break buddy's settings, plus the little history its planner keeps so
/// moves rotate across breaks and relaunches.
///
/// The history only steers which move comes next. Nothing counts against
/// the user: no streaks, no misses, no totals.
public struct BreakBuddyPreferences: Codable, Equatable, Sendable {
    /// Whether the pet models a move at the start of breaks.
    public var isOn: Bool
    /// Moves the user turned off; the planner never picks them.
    public var disabledMoves: Set<BreakMove>
    /// Whether the break card shows today's glasses of water and its + button.
    public var tracksWater: Bool
    /// The move of the last planned moment, so the next break picks another.
    public var lastMove: BreakMove?
    /// Planned breaks since the last sip, so a sip comes round every few breaks.
    public var breaksSinceSip: Int
    /// The last break a moment was planned for (`BreakBuddyPlanner.breakKey`),
    /// so a break seen twice (a relaunch, a clock republished) moves the
    /// rotation on once.
    public var lastBreakKey: String?

    public init(isOn: Bool = true, disabledMoves: Set<BreakMove> = [], tracksWater: Bool = true,
                lastMove: BreakMove? = nil, breaksSinceSip: Int = 0, lastBreakKey: String? = nil) {
        self.isOn = isOn
        self.disabledMoves = disabledMoves
        self.tracksWater = tracksWater
        self.lastMove = lastMove
        self.breaksSinceSip = max(breaksSinceSip, 0)
        self.lastBreakKey = lastBreakKey
    }

    /// The moves the planner may pick, in `BreakMove.allCases` order.
    public var enabledMoves: [BreakMove] {
        BreakMove.allCases.filter { !disabledMoves.contains($0) }
    }

    /// Whether `move` may be picked.
    public func isEnabled(_ move: BreakMove) -> Bool { !disabledMoves.contains(move) }

    /// Turns `move` on or off.
    public mutating func setEnabled(_ move: BreakMove, _ enabled: Bool) {
        if enabled { disabledMoves.remove(move) } else { disabledMoves.insert(move) }
    }

    private enum CodingKeys: String, CodingKey {
        case isOn, disabledMoves, tracksWater, lastMove, breaksSinceSip, lastBreakKey
    }

    /// Lenient: a value this build can't read keeps its default instead of
    /// losing every preference, and a move a newer build added is skipped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = (try? container.decodeIfPresent(Bool.self, forKey: .isOn)) ?? true
        let disabled = (try? container.decodeIfPresent([String].self, forKey: .disabledMoves)) ?? []
        disabledMoves = Set(disabled.compactMap(BreakMove.init(rawValue:)))
        tracksWater = (try? container.decodeIfPresent(Bool.self, forKey: .tracksWater)) ?? true
        let last = try? container.decodeIfPresent(String.self, forKey: .lastMove)
        lastMove = last.flatMap(BreakMove.init(rawValue:))
        breaksSinceSip = max((try? container.decodeIfPresent(Int.self, forKey: .breaksSinceSip)) ?? 0, 0)
        lastBreakKey = try? container.decodeIfPresent(String.self, forKey: .lastBreakKey)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isOn, forKey: .isOn)
        // Sorted, so the saved document doesn't change with set order.
        try container.encode(disabledMoves.map(\.rawValue).sorted(), forKey: .disabledMoves)
        try container.encode(tracksWater, forKey: .tracksWater)
        try container.encodeIfPresent(lastMove, forKey: .lastMove)
        try container.encode(breaksSinceSip, forKey: .breaksSinceSip)
        try container.encodeIfPresent(lastBreakKey, forKey: .lastBreakKey)
    }
}

/// Where the break buddy's preferences live in `UserDefaults`, and their
/// versioned JSON format.
public struct BreakBuddyPreferencesStorage {
    public static let key = "breakBuddy.preferences"
    /// Version 1 is the first format.
    public static let schema = VersionedJSON(current: 1)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved preferences, or the defaults when none are saved or they
    /// can't be read.
    public func load() -> BreakBuddyPreferences {
        defaults.data(forKey: Self.key)
            .flatMap { try? Self.schema.decode(BreakBuddyPreferences.self, from: $0) } ?? BreakBuddyPreferences()
    }

    public func save(_ preferences: BreakBuddyPreferences) {
        if let data = try? Self.schema.encode(preferences) { defaults.set(data, forKey: Self.key) }
    }
}
