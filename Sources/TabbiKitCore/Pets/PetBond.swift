import Foundation

/// How close the pet and the user have grown, from 1 ("Just met") to 10
/// ("Forever friends").
///
/// The bond is derived from the activity log the app already keeps
/// (`PetMilestoneProgress`): every focused minute counts, and every study day
/// adds a consistency bonus, so steady study grows it faster than one long
/// cram. Nothing new is tracked and nothing ever takes bond away: a break
/// from studying leaves the pet exactly as close as before, because guilt
/// mechanics backfire.
public struct PetBond: Hashable, Sendable {
    public static let maxLevel = 10

    /// Bond points needed to reach each level, level 1 first. The steps grow
    /// gently (100, 200, 300, 400, 600, 800, 1100, 1500, 2000), so the first levels come within a
    /// day or two and the last ones take a few months of a typical habit
    /// (`PetEconomy`: about 75 focused minutes a day, plus the day bonus).
    public static let thresholds: [Int] = [0, 100, 300, 600, 1000, 1600, 2400, 3500, 5000, 7000]

    /// Bond points one study day adds on top of its minutes. A day counts
    /// once it has `PetMilestoneProgress.minutesForStudyDay` focused minutes.
    public static let pointsPerStudyDay = 30

    /// Total bond points earned so far.
    public let points: Int

    public init(points: Int) {
        self.points = max(0, points)
    }

    /// The bond for focused minutes and study days, from the activity log.
    public init(progress: PetMilestoneProgress) {
        let minutes = progress.focusMinutes.isFinite ? Int(progress.focusMinutes.rounded(.down)) : 0
        self.init(points: minutes + progress.studyDays.count * Self.pointsPerStudyDay)
    }

    public init(records: some Sequence<ActivityRecord>, calendar: Calendar = .current) {
        self.init(progress: PetMilestoneProgress(records: records, calendar: calendar))
    }

    /// The bond level, 1 to `maxLevel`.
    public var level: Int {
        Self.level(forPoints: points)
    }

    public static func level(forPoints points: Int) -> Int {
        thresholds.lastIndex { points >= $0 }.map { $0 + 1 } ?? 1
    }

    /// The warm name for the current level.
    public var tierName: String { Self.tierName(forLevel: level) }

    /// The name for each level, from first meeting to lifelong friends.
    public static func tierName(forLevel level: Int) -> String {
        let names = ["Just met", "New friends", "Pals", "Best friends", "Study buddies",
                     "Partners in focus", "Inseparable", "Kindred spirits", "Soulmates", "Forever friends"]
        return names[min(max(level, 1), maxLevel) - 1]
    }

    /// Whether the bond is at the top level.
    public var isMaxed: Bool { level == Self.maxLevel }

    /// Points to reach the next level, or nil at the top.
    public var pointsToNextLevel: Int? {
        isMaxed ? nil : Self.thresholds[level] - points
    }

    /// How far into the current level the bond is, 0 to 1 (1 at the top),
    /// for the pet card's progress ring.
    public var progressInLevel: Double {
        guard !isMaxed else { return 1 }
        let floor = Self.thresholds[level - 1]
        let ceiling = Self.thresholds[level]
        return Double(points - floor) / Double(ceiling - floor)
    }

    /// What the pet shows at this bond (`PetBondLook`).
    public var look: PetBondLook { PetBondLook(level: level) }
}

/// The collar the pet wears at a bond level. It is drawn as a
/// breed-agnostic overlay, so it fits every breed and stance.
public enum PetCollar: String, CaseIterable, Comparable, Sendable {
    case none, plain, bell, star, gold

    /// The bond level that unlocks each collar.
    public var unlockLevel: Int {
        switch self {
        case .none: 1
        case .plain: 2
        case .bell: 4
        case .star: 6
        case .gold: 8
        }
    }

    public var displayName: String {
        switch self {
        case .none: "No collar"
        case .plain: "Plain collar"
        case .bell: "Bell collar"
        case .star: "Star tag"
        case .gold: "Gold tag"
        }
    }

    public static func < (lhs: PetCollar, rhs: PetCollar) -> Bool {
        lhs.unlockLevel < rhs.unlockLevel
    }
}

/// The visible growth that comes with a bond level: a collar that upgrades,
/// a happier idle, and a soft sparkle near the top. None of it depends on
/// breed, so 18 breeds grow without redrawing any of them.
public struct PetBondLook: Hashable, Sendable {
    /// The bond level that adds the happier idle (a little extra bounce).
    public static let happyIdleLevel = 3
    /// The bond level that adds the soft sparkle.
    public static let sparkleLevel = 9

    public let collar: PetCollar
    public let happyIdle: Bool
    public let sparkle: Bool

    /// A pet that has just met its owner: nothing grown in yet.
    public static let none = PetBondLook(level: 1)

    public init(level: Int) {
        collar = PetCollar.allCases.last { level >= $0.unlockLevel } ?? .none
        happyIdle = level >= Self.happyIdleLevel
        sparkle = level >= Self.sparkleLevel
    }

    /// What the next level up unlocks, for a "Next: Bell collar" hint, or
    /// nil when it adds nothing new (or the bond is maxed).
    public static func unlock(atLevel level: Int) -> String? {
        if let collar = PetCollar.allCases.first(where: { $0.unlockLevel == level && $0 != .none }) {
            return collar.displayName
        }
        if level == happyIdleLevel { return "Happy wiggle" }
        if level == sparkleLevel { return "Sparkle" }
        return nil
    }
}
