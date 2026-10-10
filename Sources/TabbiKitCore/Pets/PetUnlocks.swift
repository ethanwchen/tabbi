import Foundation

/// Anything the pet can wear, as one unlockable thing. Breeds and colors are
/// always free; costume items are bought with study points, except limited
/// edition items (`PetLimitedEdition`), which are earned or granted.
///
/// Encoded as a stable string id (`"outfit.scrubs"`, `"accessory.beanie"`)
/// so saved ledgers survive reordering the enums.
public enum PetItem: Hashable, Codable, Sendable, CustomStringConvertible {
    case outfit(PetOutfit)
    case accessory(PetAccessory)

    /// Every item: the shop in shop order (cheapest first), then the
    /// limited edition items in `PetLimitedEdition.allCases` order.
    public static var allCases: [PetItem] {
        let all = PetOutfit.allCases.map(PetItem.outfit) + PetAccessory.allCases.map(PetItem.accessory)
        return all.filter { !$0.isLimited }.sorted { ($0.cost, $0.id) < ($1.cost, $1.id) }
            + PetLimitedEdition.allCases.map(\.item)
    }

    /// The items points can buy (and the free starters), cheapest first:
    /// every item but the limited edition ones. Prices and tiers are set
    /// for these.
    public static var shopItems: [PetItem] { allCases.filter { !$0.isLimited } }

    public var id: String {
        switch self {
        case .outfit(let outfit): "outfit.\(outfit.rawValue)"
        case .accessory(let accessory): "accessory.\(accessory.rawValue)"
        }
    }

    public init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "outfit": guard let outfit = PetOutfit(rawValue: parts[1]) else { return nil }
            self = .outfit(outfit)
        case "accessory": guard let accessory = PetAccessory(rawValue: parts[1]) else { return nil }
            self = .accessory(accessory)
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .outfit(let outfit): outfit.displayName
        case .accessory(let accessory): accessory.displayName
        }
    }

    public var description: String { id }

    /// Price in study points (1 per focused minute, 35 for a finished
    /// 25 minute block), set against a typical study habit of three blocks
    /// a day, five days a week (`PetEconomy`, docs/economy.md). One starter
    /// per playful theme is free, so a new pet can dress up right away.
    /// Starters take one typical day or less (the first block buys the
    /// beanie), mid-tier items two to five days, and the showpieces (the
    /// sorcerer, the graduation cap) two to four weeks. Every price is
    /// distinct, so the shop order never depends on ids.
    /// Limited edition items have no price (0) and are not for sale.
    public var cost: Int {
        switch self {
        case .outfit(.none), .accessory(.scarf), .accessory(.partyHat), .accessory(.bowTie): 0
        case .accessory(.backwardsCap), .accessory(.flameHeadband), .accessory(.goldenLaurel),
             .accessory(.teamMedal), .accessory(.moonlitWitchHat), .accessory(.pumpkinHat),
             .accessory(.reindeerAntlers), .accessory(.snowScarf), .accessory(.heartGlasses),
             .accessory(.summerShades), .accessory(.lionDanceHat), .accessory(.sakuraSprig): 0
        // Starters: up to one typical day (105).
        case .accessory(.beanie): 35
        case .accessory(.roundGlasses): 50
        case .accessory(.ninjaHeadband): 65
        case .accessory(.bunnyEars): 75
        case .accessory(.coolSunglasses): 90
        case .accessory(.flowerCrown): 105
        // Mid-tier: two to five typical days (210 to 525).
        case .accessory(.frogHat): 210
        case .outfit(.scrubs): 240
        case .accessory(.stethoscope): 270
        case .accessory(.cowboyHat): 300
        case .accessory(.surgicalCap): 330
        case .accessory(.chefHat): 360
        case .outfit(.cozyHoodie): 390
        case .accessory(.chunkyHeadphones): 420
        case .accessory(.headMirror): 450
        case .accessory(.witchHat): 480
        case .accessory(.pirateHat): 520
        // Showpieces: two to four typical weeks (1050 to 2100).
        case .accessory(.tinyCrown): 1050
        case .accessory(.wizardHat): 1150
        case .outfit(.whiteCoat): 1250
        case .outfit(.superheroCape): 1400
        case .outfit(.dinosaurHoodie): 1500
        case .outfit(.wizardRobe): 1650
        case .accessory(.astronautHelmet): 1800
        case .accessory(.blindfoldedSorcerer): 1950
        case .accessory(.graduationCap): 2100
        // Animated showpieces sit at the top of the tier.
        case .accessory(.rainCloud): 1600
        case .accessory(.cherryPetals): 1700
        case .accessory(.sparkleTrail): 1750
        case .accessory(.halo): 1900
        case .accessory(.angelWings): 2000
        case .accessory(.kingsCape): 2050
        }
    }

    /// Owned from the start. Limited edition items cost nothing but are
    /// never free: they have to be earned or granted.
    public var isFree: Bool { cost == 0 && !isLimited }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let item = PetItem(id: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown pet item \(raw)"))
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

/// How study time turns into points. Kept as plain rules so the numbers are
/// easy to tune and test.
public enum PetPointsRules {
    /// One point per full minute studied.
    public static let pointsPerMinute = 1
    /// Sessions shorter than this earn nothing, so starting and stopping a
    /// timer is not a way to farm points.
    public static let minimumMinutes = 5
    /// Finishing a focus block of at least `bonusMinutes` earns a bonus,
    /// which rewards completing sessions over abandoning them.
    public static let completionBonus = 10
    public static let bonusMinutes = 25

    /// Points for one study session.
    public static func points(forMinutes minutes: Int, completed: Bool) -> Int {
        guard minutes >= minimumMinutes else { return 0 }
        let bonus = completed && minutes >= bonusMinutes ? completionBonus : 0
        return minutes * pointsPerMinute + bonus
    }

    /// Finishing a Party shared session with friends earns this much on top
    /// of what the same session earns solo, per friend who studied along.
    public static let sharedBonusPerFriend = 5
    /// The most a shared session's team bonus adds, so a big party is not
    /// worth far more than a small one.
    public static let maxSharedBonus = 15

    /// Points for a stay in a Party shared session. One that ran to its end
    /// with the user in it pays a completed solo session's points, plus the
    /// team bonus when at least one friend was there. One cut short (the
    /// user stepped out, or the host ended it early) pays the minutes
    /// studied like a solo session cut short: no bonuses, so stepping out
    /// and back in is never worth more than staying. Too short a stay
    /// earns nothing.
    public static func sharedPoints(forMinutes minutes: Int, friends: Int, finished: Bool = true) -> Int {
        let solo = points(forMinutes: minutes, completed: finished)
        guard solo > 0, finished else { return solo }
        return solo + min(max(friends, 0) * sharedBonusPerFriend, maxSharedBonus)
    }
}

/// Why a purchase was refused.
public enum PetPurchaseError: Error, Equatable, Sendable {
    case alreadyOwned
    /// A limited edition item, which is earned or granted instead.
    case notForSale
    /// `missing` more points are needed.
    case notEnoughPoints(missing: Int)
}

/// Why an extra streak freeze could not be bought.
public enum StreakFreezePurchaseError: Error, Equatable, Sendable {
    /// `StreakFreezeRules.maxHeld` extras are already held.
    case holdingLimit
    /// `missing` more points are needed.
    case notEnoughPoints(missing: Int)
}

/// The user's study points and the costume items they own.
///
/// Points are tracked as lifetime earned and spent rather than a single
/// balance, so the balance can never drift and "total studied" stats stay
/// available after shopping.
public struct PetPointsLedger: Hashable, Codable, Sendable {
    public private(set) var earned: Int
    public private(set) var spent: Int
    /// Purchased items. Free items are owned implicitly and never stored.
    public private(set) var purchased: Set<PetItem>
    /// Limited edition items earned from a milestone or granted for an
    /// event. Kept for good once given, even if the log that earned one is
    /// gone or a grant is later withdrawn.
    public private(set) var granted: Set<PetItem>
    /// When each extra streak freeze was bought, oldest first. `StudyStreak`
    /// replays them against the study days to know which are still held.
    public private(set) var streakFreezes: [Date]

    public init(earned: Int = 0, spent: Int = 0, purchased: Set<PetItem> = [], granted: Set<PetItem> = [],
                streakFreezes: [Date] = []) {
        self.earned = max(0, earned)
        self.purchased = purchased.filter { !$0.isFree && !$0.isLimited }
        self.granted = granted.filter(\.isLimited)
        self.spent = min(max(0, spent), self.earned)
        self.streakFreezes = streakFreezes.sorted()
    }

    public var balance: Int { earned - spent }

    public func owns(_ item: PetItem) -> Bool {
        item.isFree || purchased.contains(item) || granted.contains(item)
    }

    public func canBuy(_ item: PetItem) -> Bool {
        !item.isLimited && !owns(item) && balance >= item.cost
    }

    /// Gives a limited edition item for free. Returns whether it is new;
    /// shop items are never granted, so points stay the only way to them.
    @discardableResult
    public mutating func grant(_ item: PetItem) -> Bool {
        guard item.isLimited else { return false }
        return granted.insert(item).inserted
    }

    /// Credits a finished or abandoned study session and returns the points
    /// it earned.
    @discardableResult
    public mutating func recordStudy(minutes: Int, completed: Bool) -> Int {
        let points = PetPointsRules.points(forMinutes: minutes, completed: completed)
        earned += points
        return points
    }

    /// Credits a stay in a Party shared session (`PetPointsRules.sharedPoints`)
    /// and returns the points it earned.
    @discardableResult
    public mutating func recordSharedSession(minutes: Int, friends: Int, finished: Bool = true) -> Int {
        let points = PetPointsRules.sharedPoints(forMinutes: minutes, friends: friends, finished: finished)
        earned += points
        return points
    }

    public mutating func buy(_ item: PetItem) throws(PetPurchaseError) {
        guard !owns(item) else { throw .alreadyOwned }
        guard !item.isLimited else { throw .notForSale }
        guard balance >= item.cost else { throw .notEnoughPoints(missing: item.cost - balance) }
        spent += item.cost
        purchased.insert(item)
    }

    /// Buys an extra streak freeze for `StreakFreezeRules.price` points.
    /// `streak` is the streak as it stands at `date` (computed with this
    /// ledger's `streakFreezes`), which says how many extras are held.
    public mutating func buyStreakFreeze(for streak: StudyStreak, at date: Date) throws(StreakFreezePurchaseError) {
        guard streak.canBuyFreeze else { throw .holdingLimit }
        let price = StreakFreezeRules.price
        guard balance >= price else { throw .notEnoughPoints(missing: price - balance) }
        spent += price
        streakFreezes.append(date)
        streakFreezes.sort()
    }

    /// Adds freezes bought on another copy of this ledger (the local save
    /// before a synced ledger replaced it), whose points are already spent.
    public mutating func keepStreakFreezes(of other: PetPointsLedger) {
        streakFreezes = Array(Set(streakFreezes).union(other.streakFreezes)).sorted()
    }

    /// The cheapest shop item not yet owned, for a "next unlock" progress hint.
    public var nextUnlock: PetItem? {
        PetItem.shopItems.first { !owns($0) }
    }

    /// What older builds charged for items that are free now. A save that
    /// still lists one gets its points back once: the re-encoded save no
    /// longer lists free items.
    static let refundedPrices: [PetItem: Int] = [.accessory(.scarf): 30]

    // Unknown item ids (from a newer build) are skipped instead of failing.
    private enum CodingKeys: String, CodingKey { case earned, spent, purchased, granted, streakFreezes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decodeIfPresent([String].self, forKey: .purchased) ?? []
        let items = Set(ids.compactMap(PetItem.init(id:)))
        let refund = items.filter(\.isFree).reduce(0) { $0 + (Self.refundedPrices[$1] ?? 0) }
        let grantedIDs = try container.decodeIfPresent([String].self, forKey: .granted) ?? []
        self.init(
            earned: try container.decodeIfPresent(Int.self, forKey: .earned) ?? 0,
            spent: (try container.decodeIfPresent(Int.self, forKey: .spent) ?? 0) - refund,
            purchased: items,
            granted: Set(grantedIDs.compactMap(PetItem.init(id:))),
            streakFreezes: (try? container.decodeIfPresent([Date].self, forKey: .streakFreezes)) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(earned, forKey: .earned)
        try container.encode(spent, forKey: .spent)
        try container.encode(purchased.map(\.id).sorted(), forKey: .purchased)
        if !granted.isEmpty {
            try container.encode(granted.map(\.id).sorted(), forKey: .granted)
        }
        if !streakFreezes.isEmpty {
            try container.encode(streakFreezes, forKey: .streakFreezes)
        }
    }
}
