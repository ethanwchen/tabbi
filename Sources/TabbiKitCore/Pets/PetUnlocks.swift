import Foundation

/// Anything the pet can wear, as one unlockable thing. Breeds and colors are
/// always free; only costume items are earned with study points.
///
/// Encoded as a stable string id (`"outfit.scrubs"`, `"accessory.beanie"`)
/// so saved ledgers survive reordering the enums.
public enum PetItem: Hashable, Codable, Sendable, CustomStringConvertible {
    case outfit(PetOutfit)
    case accessory(PetAccessory)

    /// Every item in shop order (cheapest first).
    public static var allCases: [PetItem] {
        let all = PetOutfit.allCases.map(PetItem.outfit) + PetAccessory.allCases.map(PetItem.accessory)
        return all.sorted { ($0.cost, $0.id) < ($1.cost, $1.id) }
    }

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
    public var cost: Int {
        switch self {
        case .outfit(.none), .accessory(.scarf), .accessory(.partyHat), .accessory(.bowTie): 0
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
        }
    }

    public var isFree: Bool { cost == 0 }

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

    /// Points for a Party shared session that ran to its end with the user
    /// in it: a completed solo session's points, plus the team bonus when
    /// at least one friend was there. Too short a stay earns nothing.
    public static func sharedPoints(forMinutes minutes: Int, friends: Int) -> Int {
        let solo = points(forMinutes: minutes, completed: true)
        guard solo > 0 else { return 0 }
        return solo + min(max(friends, 0) * sharedBonusPerFriend, maxSharedBonus)
    }
}

/// Why a purchase was refused.
public enum PetPurchaseError: Error, Equatable, Sendable {
    case alreadyOwned
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

    public init(earned: Int = 0, spent: Int = 0, purchased: Set<PetItem> = []) {
        self.earned = max(0, earned)
        self.purchased = purchased.filter { !$0.isFree }
        self.spent = min(max(0, spent), self.earned)
    }

    public var balance: Int { earned - spent }

    public func owns(_ item: PetItem) -> Bool {
        item.isFree || purchased.contains(item)
    }

    public func canBuy(_ item: PetItem) -> Bool {
        !owns(item) && balance >= item.cost
    }

    /// Credits a finished or abandoned study session and returns the points
    /// it earned.
    @discardableResult
    public mutating func recordStudy(minutes: Int, completed: Bool) -> Int {
        let points = PetPointsRules.points(forMinutes: minutes, completed: completed)
        earned += points
        return points
    }

    /// Credits a finished Party shared session (`PetPointsRules.sharedPoints`)
    /// and returns the points it earned.
    @discardableResult
    public mutating func recordSharedSession(minutes: Int, friends: Int) -> Int {
        let points = PetPointsRules.sharedPoints(forMinutes: minutes, friends: friends)
        earned += points
        return points
    }

    public mutating func buy(_ item: PetItem) throws(PetPurchaseError) {
        guard !owns(item) else { throw .alreadyOwned }
        guard balance >= item.cost else { throw .notEnoughPoints(missing: item.cost - balance) }
        spent += item.cost
        purchased.insert(item)
    }

    /// The cheapest item not yet owned, for a "next unlock" progress hint.
    public var nextUnlock: PetItem? {
        PetItem.allCases.first { !owns($0) }
    }

    /// What older builds charged for items that are free now. A save that
    /// still lists one gets its points back once: the re-encoded save no
    /// longer lists free items.
    static let refundedPrices: [PetItem: Int] = [.accessory(.scarf): 30]

    // Unknown item ids (from a newer build) are skipped instead of failing.
    private enum CodingKeys: String, CodingKey { case earned, spent, purchased }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decodeIfPresent([String].self, forKey: .purchased) ?? []
        let items = Set(ids.compactMap(PetItem.init(id:)))
        let refund = items.filter(\.isFree).reduce(0) { $0 + (Self.refundedPrices[$1] ?? 0) }
        self.init(
            earned: try container.decodeIfPresent(Int.self, forKey: .earned) ?? 0,
            spent: (try container.decodeIfPresent(Int.self, forKey: .spent) ?? 0) - refund,
            purchased: items
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(earned, forKey: .earned)
        try container.encode(spent, forKey: .spent)
        try container.encode(purchased.map(\.id).sorted(), forKey: .purchased)
    }
}
