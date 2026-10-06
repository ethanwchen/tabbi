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

    /// Price in study points. Cozy basics come first so a new user unlocks
    /// something after their first real session; the white coat and the
    /// graduation cap are long-term goals.
    public var cost: Int {
        switch self {
        case .outfit(.none): 0
        case .accessory(.scarf): 30
        case .accessory(.beanie): 45
        case .accessory(.roundGlasses): 60
        case .outfit(.scrubs): 90
        case .accessory(.stethoscope): 120
        case .accessory(.surgicalCap): 150
        case .accessory(.headMirror): 200
        case .outfit(.whiteCoat): 300
        case .accessory(.graduationCap): 500
        case .accessory(.partyHat): 110
        case .accessory(.bunnyEars): 140
        case .accessory(.chefHat): 180
        case .accessory(.tinyCrown): 260
        case .accessory(.wizardHat): 350
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

    // Unknown item ids (from a newer build) are skipped instead of failing.
    private enum CodingKeys: String, CodingKey { case earned, spent, purchased }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try container.decodeIfPresent([String].self, forKey: .purchased) ?? []
        self.init(
            earned: try container.decodeIfPresent(Int.self, forKey: .earned) ?? 0,
            spent: try container.decodeIfPresent(Int.self, forKey: .spent) ?? 0,
            purchased: Set(ids.compactMap(PetItem.init(id:)))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(earned, forKey: .earned)
        try container.encode(spent, forKey: .spent)
        try container.encode(purchased.map(\.id).sorted(), forKey: .purchased)
    }
}
