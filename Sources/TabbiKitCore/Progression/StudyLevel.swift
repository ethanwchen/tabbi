import Foundation

/// The pet's Study Level: an endless level earned only from total focus
/// hours, the same focused minutes the Focus time badge counts
/// (`ProgressTrack.focusHours`, from the activity log). It never resets
/// and never goes down, and it pays no study points: points stay tied to
/// studying itself (`PetPointsRules`). docs/design/progression.md has the
/// curve's table and the reasons.
///
/// Every level the pet celebrates, every 5 levels a new nameplate color
/// unlocks (`Nameplate`), and every 10 levels a new rank (`StudyRank`).
public struct StudyLevel: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The level, from 0 (under 4 hours) up, with no cap.
    public let value: Int

    public init(_ value: Int) { self.value = max(0, value) }

    /// The level `focusMinutes` of focus in total reach: the highest `n`
    /// whose `minutesToReach(n)` is covered.
    public init(focusMinutes: Int) {
        var level = 0
        // The curve grows past every Int long before minutes could, so the
        // walk ends; a closed form would round differently at the edges.
        while Self.minutesToReach(level + 1) <= focusMinutes { level += 1 }
        self.init(level)
    }

    /// The curve, in one place: whole hours of focus in total to reach
    /// level `n` are `round(4 * n^1.6)`. Level 1 takes 4 hours, level 5
    /// 53, level 10 159, level 25 690, level 50 2,091 and level 100 6,340,
    /// so early levels come within days and each later one asks a little
    /// more, never a wall. Level 0 and below need nothing.
    ///
    /// `pow` and rounding half away from zero match JavaScript's
    /// `Math.round(4 * n ** 1.6)` exactly (no `n` up to 5,000 lands within
    /// 0.0001 of a half), so the Windows port agrees to the hour.
    public static func hoursToReach(_ level: Int) -> Int {
        guard level > 0 else { return 0 }
        return Int((curveScale * pow(Double(level), curveExponent)).rounded())
    }

    /// `hoursToReach` in minutes, the unit the activity log counts in.
    public static func minutesToReach(_ level: Int) -> Int { hoursToReach(level) * 60 }

    /// The curve's two numbers: hours at level 1, and how steeply it grows.
    public static let curveScale = 4.0
    public static let curveExponent = 1.6

    /// Levels between nameplate colors and between ranks.
    public static let levelsPerNameplate = 5
    public static let levelsPerRank = 10

    /// The highest level friends are told (`PartyProfileUpdate.studyLevel`)
    /// and the server keeps: 999 takes about 252,000 hours, far past any
    /// lifetime, so it only stops a garbled number.
    public static let maxShared = 999

    /// The level the next one up.
    public var next: StudyLevel { StudyLevel(value + 1) }

    /// The rank this level belongs to.
    public var rank: StudyRank { StudyRank(level: value) }

    /// Whether reaching this level unlocked a nameplate color or a rank.
    public var unlocksNameplate: Bool { value > 0 && value.isMultiple(of: Self.levelsPerNameplate) && Nameplate(unlockedAt: value) != nil }
    public var startsRank: Bool { value > 0 && value.isMultiple(of: Self.levelsPerRank) }

    /// How far `focusMinutes` are from this level to the next, 0 to 1, for
    /// the Level card's bar.
    public func fraction(focusMinutes: Int) -> Double {
        let start = Self.minutesToReach(value), end = Self.minutesToReach(value + 1)
        guard end > start else { return 0 }
        return min(1, max(0, Double(focusMinutes - start) / Double(end - start)))
    }

    /// "Lv 12", short enough to sit beside the pet's name.
    public var shortLabel: String { String(localized: "Lv \(value)", bundle: .tabbi) }

    /// "Level 12", where there is room.
    public var label: String { String(localized: "Level \(value)", bundle: .tabbi) }

    public var description: String { "\(value)" }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

/// A rank: the title every 10 study levels bring, each with its own pixel
/// emblem (`RankArt`). Levels 0 to 9 are Spark, then Ember, Comet, Nova,
/// Nebula and, from level 50, Galaxy; past that it keeps counting in Roman
/// numerals, Galaxy II at 60, Galaxy III at 70 and on without end.
public struct StudyRank: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The named ranks, in order.
    public enum Tier: String, CaseIterable, Codable, Sendable {
        case spark, ember, comet, nova, nebula, galaxy

        /// The rank's name, short in every language.
        public var displayName: String {
            switch self {
            case .spark: String(localized: "rank.spark", bundle: .tabbi)
            case .ember: String(localized: "rank.ember", bundle: .tabbi)
            case .comet: String(localized: "rank.comet", bundle: .tabbi)
            case .nova: String(localized: "rank.nova", bundle: .tabbi)
            case .nebula: String(localized: "rank.nebula", bundle: .tabbi)
            case .galaxy: String(localized: "rank.galaxy", bundle: .tabbi)
            }
        }
    }

    public let tier: Tier
    /// 1 for every named rank; 2 for Galaxy II, 3 for Galaxy III and so on.
    public let numeral: Int

    public init(tier: Tier, numeral: Int = 1) {
        self.tier = tier
        self.numeral = tier == .galaxy ? max(1, numeral) : 1
    }

    public init(level: Int) {
        let band = max(0, level) / StudyLevel.levelsPerRank
        let tiers = Tier.allCases
        if band < tiers.count {
            self.init(tier: tiers[band])
        } else {
            self.init(tier: .galaxy, numeral: band - tiers.count + 2)
        }
    }

    /// The first level of this rank.
    public var firstLevel: Int {
        let index = Tier.allCases.firstIndex(of: tier) ?? 0
        return (index + numeral - 1) * StudyLevel.levelsPerRank
    }

    /// The rank after this one.
    public var next: StudyRank { StudyRank(level: firstLevel + StudyLevel.levelsPerRank) }

    /// A stable id for fixtures and logs: `spark`, `galaxy`, `galaxy-2`.
    public var id: String { numeral > 1 ? "\(tier.rawValue)-\(numeral)" : tier.rawValue }

    /// "Ember", "Galaxy II".
    public var displayName: String {
        guard numeral > 1 else { return tier.displayName }
        return String(localized: "rank.numbered \(tier.displayName) \(Self.roman(numeral))", bundle: .tabbi)
    }

    /// How many small stars ring the Galaxy emblem: one for Galaxy II up
    /// to four from Galaxy V on, where the name's numeral carries on.
    public var pips: Int { min(max(numeral - 1, 0), RankArt.maxPips) }

    public var description: String { id }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.firstLevel < rhs.firstLevel }

    /// `n` in Roman numerals ("II", "XIV"), which read the same in every
    /// language the app speaks; above 3,999 it falls back to digits.
    public static func roman(_ n: Int) -> String {
        guard n > 0, n < 4000 else { return "\(n)" }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var left = n, text = ""
        for (value, letters) in table {
            while left >= value {
                text += letters
                left -= value
            }
        }
        return text
    }
}

/// A nameplate color: the tint of the pet's name under it in the Closet
/// and on its Party card. Plain is everyone's from the start; every 5
/// study levels unlock the next, up to Level 60, and the user picks any
/// unlocked one in the Closet's Look section. From Level 40 the name also
/// glows softly. The ids go over the wire (`PartyProfileUpdate.nameplate`)
/// and are listed in the Party catalog, so they are only ever added.
public enum Nameplate: String, CaseIterable, Codable, Sendable {
    case plain, peach, ember, honey, sky, mint, rose, lilac, nebula, coral, gold, aurora, starlight

    /// The level that unlocks it: 0 for plain, then 5, 10 ... 60.
    public var unlockLevel: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) * StudyLevel.levelsPerNameplate
    }

    /// The nameplate a level of exactly `level` unlocks, if any.
    public init?(unlockedAt level: Int) {
        guard level >= 0, level.isMultiple(of: StudyLevel.levelsPerNameplate) else { return nil }
        let index = level / StudyLevel.levelsPerNameplate
        guard index < Self.allCases.count else { return nil }
        self = Self.allCases[index]
    }

    /// Every nameplate unlocked at `level`, plain first.
    public static func unlocked(at level: StudyLevel) -> [Nameplate] {
        allCases.filter { $0.unlockLevel <= level.value }
    }

    /// The next nameplate still to unlock above `level`, or nil once all are.
    public static func next(after level: StudyLevel) -> Nameplate? {
        allCases.first { $0.unlockLevel > level.value }
    }

    /// The tint. Plain is the notch's primary text; the rest are light
    /// enough to read on the black notch and on every theme's card
    /// (`StudyLevelTests` holds each to 7:1 on black).
    public var color: PetColor {
        switch self {
        case .plain: PetColor(hex: "#F5F5F7")!
        case .peach: PetColor(hex: "#FFC2A6")!
        case .ember: PetColor(hex: "#FFA06B")!
        case .honey: PetColor(hex: "#FFD873")!
        case .sky: PetColor(hex: "#9AD8FF")!
        case .mint: PetColor(hex: "#8FE8C0")!
        case .rose: PetColor(hex: "#FFA3C9")!
        case .lilac: PetColor(hex: "#CDB4FF")!
        case .nebula: PetColor(hex: "#B5A3FF")!
        case .coral: PetColor(hex: "#FF9E94")!
        case .gold: PetColor(hex: "#FFCF4D")!
        case .aurora: PetColor(hex: "#7FF2DC")!
        case .starlight: PetColor(hex: "#ECE4FF")!
        }
    }

    /// The rarer colors, from Level 40, also glow softly around the name.
    public var glows: Bool { unlockLevel >= 40 }

    public var displayName: String {
        switch self {
        case .plain: String(localized: "nameplate.plain", bundle: .tabbi)
        case .peach: String(localized: "nameplate.peach", bundle: .tabbi)
        case .ember: String(localized: "nameplate.ember", bundle: .tabbi)
        case .honey: String(localized: "nameplate.honey", bundle: .tabbi)
        case .sky: String(localized: "nameplate.sky", bundle: .tabbi)
        case .mint: String(localized: "nameplate.mint", bundle: .tabbi)
        case .rose: String(localized: "nameplate.rose", bundle: .tabbi)
        case .lilac: String(localized: "nameplate.lilac", bundle: .tabbi)
        case .nebula: String(localized: "nameplate.nebula", bundle: .tabbi)
        case .coral: String(localized: "nameplate.coral", bundle: .tabbi)
        case .gold: String(localized: "nameplate.gold", bundle: .tabbi)
        case .aurora: String(localized: "nameplate.aurora", bundle: .tabbi)
        case .starlight: String(localized: "nameplate.starlight", bundle: .tabbi)
        }
    }
}

/// What friends see of the Study Level in Party: the level (the rank
/// follows from it, so it is never sent) and the nameplate color picked.
public struct StudyStanding: Hashable, Sendable {
    public var level: StudyLevel
    public var nameplate: Nameplate

    public init(level: StudyLevel = StudyLevel(0), nameplate: Nameplate = .plain) {
        self.level = level
        self.nameplate = nameplate
    }

    public var rank: StudyRank { level.rank }
}
