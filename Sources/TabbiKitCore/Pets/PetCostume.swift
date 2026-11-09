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
    /// A navy hoodie with white drawstrings and a gold crest that glints,
    /// earned during exam season (`PetLimitedEdition.examHoodie`). The
    /// shop's cozy hoodie is plain knit.
    case studyHoodie
    // Mastery outfits (`PetLimitedEdition`, source `mastery`): earned by
    // reaching a badge tier (`ProgressBadge`), never sold.
    /// A white space suit with a navy collar ring and belt, a chest panel
    /// with two lights and a crimson mission patch, and a glass bubble
    /// helmet over the head.
    case astronautSuit
    /// A violet cloak closed at the chest with a gold star clasp, its gold
    /// and white stars twinkling. Worn on the body, never streaming behind.
    case starryCloak
    /// A plain brown robe with a white collar and a gold rope belt, the
    /// first of the three robes tiered by finished sessions.
    case apprenticeRobe
    /// A navy robe with a crimson stole edged in gold.
    case scholarsRobe
    /// A white robe with a gold stole that a glint runs down now and then,
    /// and a pointed white hood.
    case sagesRobe
    /// Sky blue pajamas with white piping, buttons and little gold moons.
    case cozyPajamas
    /// A white apron with a crimson trim, holding a tiny strawberry cake.
    case bakersApron

    public var displayName: String {
        switch self {
        case .none: String(localized: "None", bundle: .tabbi)
        case .scrubs: String(localized: "Scrubs", bundle: .tabbi)
        case .whiteCoat: String(localized: "White Coat", bundle: .tabbi)
        case .cozyHoodie: String(localized: "Cozy Hoodie", bundle: .tabbi)
        case .superheroCape: String(localized: "Superhero Cape", bundle: .tabbi)
        case .dinosaurHoodie: String(localized: "Dinosaur Hoodie", bundle: .tabbi)
        case .wizardRobe: String(localized: "Wizard Robe", bundle: .tabbi)
        case .studyHoodie: String(localized: "Study Hoodie", bundle: .tabbi)
        case .astronautSuit: String(localized: "Astronaut Suit", bundle: .tabbi)
        case .starryCloak: String(localized: "Starry Cloak", bundle: .tabbi)
        case .apprenticeRobe: String(localized: "Apprentice Robe", bundle: .tabbi)
        case .scholarsRobe: String(localized: "Scholar's Robe", bundle: .tabbi)
        case .sagesRobe: String(localized: "Sage's Robe", bundle: .tabbi)
        case .cozyPajamas: String(localized: "Cozy Pajamas", bundle: .tabbi)
        case .bakersApron: String(localized: "Baker's Apron", bundle: .tabbi)
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
    // Seasonal event items (`SeasonalEvent`): earned by focusing while the
    // event runs.
    /// A navy witch hat with a pumpkin band and a gold crescent moon, for
    /// Halloween. The shop's witch hat has a red band and a buckle.
    case moonlitWitchHat
    /// A carved jack-o'-lantern worn as a hat, its candle flickering, the
    /// Halloween headline item.
    case pumpkinHat
    /// Brown reindeer antlers on a crimson headband, for the winter holidays.
    case reindeerAntlers
    /// A crimson scarf with a white trim and fringe that snow sparkles on,
    /// the winter holidays headline item. The shop's scarf is pink knit.
    case snowScarf
    /// Pink heart-shaped glasses on a crimson frame, a light glinting on
    /// a lens now and then: the Valentine's headline item.
    case heartGlasses
    /// Navy-rimmed aviators with sunset lenses that the sun glints on: the
    /// summer headline item. The shop's cool sunglasses are plain black.
    case summerShades
    /// A red lion dance head with a gold horn, white brows and a gold
    /// fringe, its forehead mirror catching the light: the Lunar New Year
    /// headline item.
    case lionDanceHat
    /// A cherry blossom sprig pinned over one ear, a petal drifting off
    /// it now and then: the spring headline item. The shop's cherry petals
    /// fall all around the pet instead.
    case sakuraSprig
    /// A small gold pin with two crimson ribbon tails, worn on the chest and
    /// glinting now and then: the Founding Member item, given to everyone
    /// who signs in during Tabbi's first 100 days. Unlike the Team Medal it
    /// hangs from no ribbon around the neck.
    case foundersPin
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
    // Mastery items (`PetLimitedEdition`, source `mastery`): earned by
    // reaching a badge tier (`ProgressBadge`), never sold.
    /// A green seedling with two round leaves growing from the crown.
    case littleSprout
    /// The seedling grown taller, with a pink blossom that lets a petal go
    /// now and then.
    case blossomSprout
    /// A floppy sky blue nightcap with a white band and a white pom at its
    /// drooping tip, to wear with the Cozy Pajamas.
    case nightcap
    /// A green bush hat with a brown band, one side of the brim pinned up
    /// with a gold badge.
    case explorersHat
    /// A gold and navy striped headband with two antennae tipped in gold.
    case beeAntennae
    /// A crimson terry sweatband with a white stripe across the brow.
    case sportySweatband
    /// Big round owlish spectacles in a brown frame with a gold bridge.
    case owlSpectacles
    /// A crimson bandana with white dots, knotted at the neck.
    case friendshipBandana
    /// A tiny lantern floating beside the pet, its flame flickering.
    case tinyLantern

    public var slot: PetAccessorySlot {
        switch self {
        case .stethoscope, .scarf, .bowTie, .teamMedal, .snowScarf, .foundersPin, .friendshipBandana: .neck
        case .roundGlasses, .coolSunglasses, .heartGlasses, .summerShades, .owlSpectacles: .face
        case .surgicalCap, .headMirror, .graduationCap, .beanie, .tinyCrown, .partyHat, .chefHat, .wizardHat,
             .bunnyEars, .witchHat, .cowboyHat, .flowerCrown, .frogHat, .ninjaHeadband, .pirateHat,
             .blindfoldedSorcerer, .astronautHelmet, .chunkyHeadphones, .backwardsCap, .flameHeadband,
             .goldenLaurel, .halo, .moonlitWitchHat, .pumpkinHat, .reindeerAntlers, .lionDanceHat,
             .sakuraSprig, .littleSprout, .blossomSprout, .nightcap, .explorersHat, .beeAntennae,
             .sportySweatband: .head
        case .angelWings, .kingsCape: .back
        case .cherryPetals, .sparkleTrail, .rainCloud, .tinyLantern: .aura
        }
    }

    /// Head items that also cover an eye (an eyepatch, a blindfold). They
    /// take the face slot too, so glasses never pile on top of them.
    public var coversEyes: Bool {
        self == .pirateHat || self == .blindfoldedSorcerer
    }

    public var displayName: String {
        switch self {
        case .stethoscope: String(localized: "Stethoscope", bundle: .tabbi)
        case .scarf: String(localized: "Cozy Scarf", bundle: .tabbi)
        case .roundGlasses: String(localized: "Round Glasses", bundle: .tabbi)
        case .surgicalCap: String(localized: "Surgical Cap", bundle: .tabbi)
        case .headMirror: String(localized: "Head Mirror", bundle: .tabbi)
        case .graduationCap: String(localized: "Graduation Cap", bundle: .tabbi)
        case .beanie: String(localized: "Beanie", bundle: .tabbi)
        case .tinyCrown: String(localized: "Tiny Crown", bundle: .tabbi)
        case .partyHat: String(localized: "Party Hat", bundle: .tabbi)
        case .chefHat: String(localized: "Chef Hat", bundle: .tabbi)
        case .wizardHat: String(localized: "Wizard Hat", bundle: .tabbi)
        case .bunnyEars: String(localized: "Bunny Ears", bundle: .tabbi)
        case .witchHat: String(localized: "Witch Hat", bundle: .tabbi)
        case .cowboyHat: String(localized: "Cowboy Hat", bundle: .tabbi)
        case .flowerCrown: String(localized: "Flower Crown", bundle: .tabbi)
        case .frogHat: String(localized: "Frog Hat", bundle: .tabbi)
        case .ninjaHeadband: String(localized: "Ninja Headband", bundle: .tabbi)
        case .coolSunglasses: String(localized: "Cool Sunglasses", bundle: .tabbi)
        case .pirateHat: String(localized: "Pirate Hat", bundle: .tabbi)
        case .blindfoldedSorcerer: String(localized: "Blindfolded Sorcerer", bundle: .tabbi)
        case .astronautHelmet: String(localized: "Astronaut Helmet", bundle: .tabbi)
        case .chunkyHeadphones: String(localized: "Chunky Headphones", bundle: .tabbi)
        case .bowTie: String(localized: "Bow Tie", bundle: .tabbi)
        case .backwardsCap: String(localized: "Backwards Cap", bundle: .tabbi)
        case .flameHeadband: String(localized: "Flame Headband", bundle: .tabbi)
        case .goldenLaurel: String(localized: "Golden Laurel", bundle: .tabbi)
        case .teamMedal: String(localized: "Team Medal", bundle: .tabbi)
        case .moonlitWitchHat: String(localized: "Moonlit Witch Hat", bundle: .tabbi)
        case .pumpkinHat: String(localized: "Pumpkin Hat", bundle: .tabbi)
        case .reindeerAntlers: String(localized: "Reindeer Antlers", bundle: .tabbi)
        case .snowScarf: String(localized: "Snowy Scarf", bundle: .tabbi)
        case .heartGlasses: String(localized: "Heart Glasses", bundle: .tabbi)
        case .summerShades: String(localized: "Sunset Shades", bundle: .tabbi)
        case .lionDanceHat: String(localized: "Lion Dance Hat", bundle: .tabbi)
        case .sakuraSprig: String(localized: "Sakura Sprig", bundle: .tabbi)
        case .foundersPin: String(localized: "Founder's Pin", bundle: .tabbi)
        case .angelWings: String(localized: "Angel Wings", bundle: .tabbi)
        case .kingsCape: String(localized: "King's Cape", bundle: .tabbi)
        case .halo: String(localized: "Halo", bundle: .tabbi)
        case .cherryPetals: String(localized: "Cherry Petals", bundle: .tabbi)
        case .sparkleTrail: String(localized: "Sparkle Trail", bundle: .tabbi)
        case .rainCloud: String(localized: "Tiny Rain Cloud", bundle: .tabbi)
        case .littleSprout: String(localized: "Little Sprout", bundle: .tabbi)
        case .blossomSprout: String(localized: "Blossom Sprout", bundle: .tabbi)
        case .nightcap: String(localized: "Nightcap", bundle: .tabbi)
        case .explorersHat: String(localized: "Explorer's Hat", bundle: .tabbi)
        case .beeAntennae: String(localized: "Busy Bee Antennae", bundle: .tabbi)
        case .sportySweatband: String(localized: "Sporty Sweatband", bundle: .tabbi)
        case .owlSpectacles: String(localized: "Owl Spectacles", bundle: .tabbi)
        case .friendshipBandana: String(localized: "Friendship Bandana", bundle: .tabbi)
        case .tinyLantern: String(localized: "Tiny Lantern", bundle: .tabbi)
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
