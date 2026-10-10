import Foundation

/// What the pet wears on its body. One outfit at a time; `.none` is the
/// default for a fresh pet.
public enum PetOutfit: String, CaseIterable, Codable, Sendable {
    case none
    /// Scrub top in the recolorable `costumeBase` color.
    case scrubs
    case whiteCoat
    /// A hoodie in the recolorable knit color, like the scarf and beanie.
    case cozyHoodie
    case superheroCape
    /// A green hoodie with a spiky hood, the one outfit with a head part.
    case dinosaurHoodie
    case wizardRobe

    public var displayName: String {
        switch self {
        case .none: "None"
        case .scrubs: "Scrubs"
        case .whiteCoat: "White Coat"
        case .cozyHoodie: "Cozy Hoodie"
        case .superheroCape: "Superhero Cape"
        case .dinosaurHoodie: "Dinosaur Hoodie"
        case .wizardRobe: "Wizard Robe"
        }
    }
}

/// Where an accessory sits. A pet wears at most one accessory per slot, and
/// slots are drawn in declaration order so hats always land on top. The
/// back slot is the exception: it goes on a layer under the whole pet, and
/// the aura slot floats in the air around it.
public enum PetAccessorySlot: Int, CaseIterable, Comparable, Codable, Sendable {
    case neck
    case face
    case head
    /// Worn behind the pet (wings), so it is drawn first and never covers it.
    case back
    /// Floats in the air around the pet (falling petals), in front of it
    /// but never over it.
    case aura

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
    // Limited edition items (`PetLimitedEdition`): earned or granted, never sold.
    /// A red baseball cap worn backwards, its snapback strap showing.
    case backwardsCap
    /// A red headband with a small flame, for a week-long study streak.
    case flameHeadband
    /// A wreath of gold leaves, for 50 hours focused.
    case goldenLaurel
    /// A gold medal on a red ribbon, for finishing a Party session.
    case teamMedal
    // Animated shop items, each looping a few frames on the item clock.
    /// White feathered wings that flap behind the pet.
    case angelWings
    /// A crimson royal cape with an ermine collar and a gold hem that glimmers.
    case kingsCape
    /// A gold halo that floats above the head and gently bobs.
    case halo
    /// Cherry blossom petals that drift down around the pet.
    case cherryPetals
    /// Gold sparkles that twinkle around the pet and trail behind it on a walk.
    case sparkleTrail
    /// A tiny grey rain cloud that drizzles beside the pet.
    case rainCloud

    public var slot: PetAccessorySlot {
        switch self {
        case .stethoscope, .scarf, .bowTie, .teamMedal: .neck
        case .roundGlasses, .coolSunglasses: .face
        case .surgicalCap, .headMirror, .graduationCap, .beanie, .tinyCrown, .partyHat, .chefHat, .wizardHat,
             .bunnyEars, .witchHat, .cowboyHat, .flowerCrown, .frogHat, .ninjaHeadband, .pirateHat,
             .blindfoldedSorcerer, .astronautHelmet, .chunkyHeadphones, .backwardsCap, .flameHeadband,
             .goldenLaurel, .halo: .head
        case .angelWings, .kingsCape: .back
        case .cherryPetals, .sparkleTrail, .rainCloud: .aura
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
        case .backwardsCap: "Backwards Cap"
        case .flameHeadband: "Flame Headband"
        case .goldenLaurel: "Golden Laurel"
        case .teamMedal: "Team Medal"
        case .angelWings: "Angel Wings"
        case .kingsCape: "King's Cape"
        case .halo: "Halo"
        case .cherryPetals: "Cherry Petals"
        case .sparkleTrail: "Sparkle Trail"
        case .rainCloud: "Tiny Rain Cloud"
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
