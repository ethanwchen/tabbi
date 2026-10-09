import Foundation

/// The study habit the Closet's prices are set against, and the price tiers
/// that follow from it. docs/economy.md walks through the math.
///
/// A typical student here finishes three 25 minute focus blocks on a study
/// day and studies five days a week. Each finished block pays 35 points
/// (`PetPointsRules`), so a typical day earns 105 points and a typical week
/// 525. Prices are then picked so the tier says how long an item takes.
public enum PetEconomy {
    /// Finished focus blocks on a typical study day.
    public static let typicalBlocksPerDay = 3
    /// The length of a typical focus block, in minutes.
    public static let typicalBlockMinutes = PetPointsRules.bonusMinutes
    /// Days with some studying in a typical week.
    public static let typicalStudyDaysPerWeek = 5

    /// Points for one typical finished focus block (35).
    public static var pointsPerTypicalBlock: Int {
        PetPointsRules.points(forMinutes: typicalBlockMinutes, completed: true)
    }

    /// Points for a typical study day (105).
    public static var pointsPerTypicalDay: Int { typicalBlocksPerDay * pointsPerTypicalBlock }

    /// Points for a typical study week (525).
    public static var pointsPerTypicalWeek: Int { typicalStudyDaysPerWeek * pointsPerTypicalDay }

    /// How many typical study days `points` take to earn, rounded up, so the
    /// shop can say "about 3 study days". Zero for nothing to earn.
    public static func typicalDays(toEarn points: Int) -> Int {
        guard points > 0 else { return 0 }
        return (points + pointsPerTypicalDay - 1) / pointsPerTypicalDay
    }

    /// How many typical focus blocks `points` take to earn, rounded up.
    public static func typicalBlocks(toEarn points: Int) -> Int {
        guard points > 0 else { return 0 }
        return (points + pointsPerTypicalBlock - 1) / pointsPerTypicalBlock
    }

    /// How many typical study weeks `points` take to earn, rounded up.
    public static func typicalWeeks(toEarn points: Int) -> Int {
        guard points > 0 else { return 0 }
        return (points + pointsPerTypicalWeek - 1) / pointsPerTypicalWeek
    }

    /// The study it takes to earn `points`, in the unit a student plans in:
    /// focus blocks within a day, study days within a week, weeks beyond.
    /// The shop says "2 focus blocks to go" rather than a bare point count,
    /// so it is clear what the next item asks of you. Empty for nothing to earn.
    public static func studyToEarn(_ points: Int) -> String {
        guard points > 0 else { return "" }
        if points <= pointsPerTypicalDay {
            let blocks = typicalBlocks(toEarn: points)
            return blocks == 1 ? "1 focus block" : "\(blocks) focus blocks"
        }
        if points <= pointsPerTypicalWeek {
            return "about \(typicalDays(toEarn: points)) study days"
        }
        // More than a week's points, so always at least two weeks.
        return "about \(typicalWeeks(toEarn: points)) weeks"
    }
}

/// How long an item takes to earn at the typical pace (`PetEconomy`).
/// Every paid price falls inside one tier's range, with gaps between the
/// tiers, so the tiers stay meaningful as prices are tuned.
public enum PetPriceTier: Int, CaseIterable, Comparable, Sendable {
    /// Owned from the start.
    case free
    /// One typical study day or less: the first block buys one.
    case starter
    /// Two to five typical study days: a goal for the week.
    case midTier
    /// Two to four typical study weeks: the long-term showpieces.
    case showpiece

    /// The prices the tier allows, in points.
    public var priceRange: ClosedRange<Int> {
        switch self {
        case .free: 0...0
        case .starter: 1...PetEconomy.pointsPerTypicalDay
        case .midTier: (2 * PetEconomy.pointsPerTypicalDay)...PetEconomy.pointsPerTypicalWeek
        case .showpiece: (2 * PetEconomy.pointsPerTypicalWeek)...(4 * PetEconomy.pointsPerTypicalWeek)
        }
    }

    /// The tier whose range holds `cost`, or nil for a price in a gap.
    public init?(cost: Int) {
        guard let tier = Self.allCases.first(where: { $0.priceRange.contains(cost) }) else { return nil }
        self = tier
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension PetItem {
    /// The item's price tier. Every catalog price sits in a tier (a unit
    /// test checks it); a price in a gap counts as the tier below.
    public var tier: PetPriceTier {
        PetPriceTier(cost: cost)
            ?? PetPriceTier.allCases.last { $0.priceRange.upperBound < cost }
            ?? .free
    }
}
