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

    public var slot: PetAccessorySlot {
        switch self {
        case .stethoscope, .scarf: .neck
        case .roundGlasses: .face
        case .surgicalCap, .headMirror, .graduationCap, .beanie: .head
        }
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
        }
    }

    /// `accessories` reduced to what can actually be worn together: one per
    /// slot (the last one listed wins, like putting on a new hat), sorted in
    /// drawing order. Keeps stored profiles valid even if edited by hand.
    public static func wearable(_ accessories: [PetAccessory]) -> [PetAccessory] {
        var bySlot: [PetAccessorySlot: PetAccessory] = [:]
        for accessory in accessories { bySlot[accessory.slot] = accessory }
        return bySlot.sorted { $0.key < $1.key }.map(\.value)
    }
}
