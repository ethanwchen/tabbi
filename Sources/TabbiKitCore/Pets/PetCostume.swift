import Foundation

/// What the pet wears on its body. One outfit at a time; `.none` is the
/// default for a fresh pet.
public enum PetOutfit: String, CaseIterable, Codable, Sendable {
    case none
    /// Scrub top in the recolorable `costumeBase` color.
    case scrubs
    case whiteCoat

    public var displayName: String {
        switch self {
        case .none: "None"
        case .scrubs: "Scrubs"
        case .whiteCoat: "White Coat"
        }
    }
}

/// Where an accessory sits. A pet wears at most one accessory per slot, and
/// slots are drawn in declaration order so hats always land on top.
public enum PetAccessorySlot: Int, CaseIterable, Comparable, Codable, Sendable {
    case neck
    case face
    case head

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Small items layered over the outfit.
public enum PetAccessory: String, CaseIterable, Codable, Sendable {
    case stethoscope
    case scarf
    case roundGlasses
    case surgicalCap
    case headMirror
    case graduationCap
    case beanie
    case tinyCrown
    case partyHat
    case chefHat
    case wizardHat
    case bunnyEars
    case witchHat
    case cowboyHat
    case flowerCrown
    case frogHat
    case ninjaHeadband
    case coolSunglasses
    /// A tricorn hat with an eyepatch over one eye.
    case pirateHat
    /// Spiky white hair and a dark blindfold over both eyes.
    case blindfoldedSorcerer
    case astronautHelmet
    case chunkyHeadphones
    case bowTie

    public var slot: PetAccessorySlot {
        switch self {
        case .stethoscope, .scarf, .bowTie: .neck
        case .roundGlasses, .coolSunglasses: .face
        case .surgicalCap, .headMirror, .graduationCap, .beanie, .tinyCrown, .partyHat, .chefHat, .wizardHat,
             .bunnyEars, .witchHat, .cowboyHat, .flowerCrown, .frogHat, .ninjaHeadband, .pirateHat,
             .blindfoldedSorcerer, .astronautHelmet, .chunkyHeadphones: .head
        }
    }

    /// Head items that also cover an eye (an eyepatch, a blindfold). They
    /// take the face slot too, so glasses never pile on top of them.
    public var coversEyes: Bool {
        self == .pirateHat || self == .blindfoldedSorcerer
    }

    public var displayName: String {
        switch self {
        case .stethoscope: "Stethoscope"
        case .scarf: "Cozy Scarf"
        case .roundGlasses: "Round Glasses"
        case .surgicalCap: "Surgical Cap"
        case .headMirror: "Head Mirror"
        case .graduationCap: "Graduation Cap"
        case .beanie: "Beanie"
        case .tinyCrown: "Tiny Crown"
        case .partyHat: "Party Hat"
        case .chefHat: "Chef Hat"
        case .wizardHat: "Wizard Hat"
        case .bunnyEars: "Bunny Ears"
        case .witchHat: "Witch Hat"
        case .cowboyHat: "Cowboy Hat"
        case .flowerCrown: "Flower Crown"
        case .frogHat: "Frog Hat"
        case .ninjaHeadband: "Ninja Headband"
        case .coolSunglasses: "Cool Sunglasses"
        case .pirateHat: "Pirate Hat"
        case .blindfoldedSorcerer: "Blindfolded Sorcerer"
        case .astronautHelmet: "Astronaut Helmet"
        case .chunkyHeadphones: "Chunky Headphones"
        case .bowTie: "Bow Tie"
        }
    }

    /// `accessories` reduced to what can actually be worn together: one per
    /// slot, and no face item under one that covers the eyes (the last one
    /// listed wins, like putting on a new hat), sorted in drawing order.
    /// Keeps stored profiles valid even if edited by hand.
    public static func wearable(_ accessories: [PetAccessory]) -> [PetAccessory] {
        var worn: [PetAccessory] = []
        for accessory in accessories {
            worn.removeAll { $0.clashes(with: accessory) }
            worn.append(accessory)
        }
        return worn.sorted { $0.slot < $1.slot }
    }

    private func clashes(with other: PetAccessory) -> Bool {
        slot == other.slot || (coversEyes && other.slot == .face) || (other.coversEyes && slot == .face)
    }
}
