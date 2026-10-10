import Foundation

/// The shelves of the Closet wardrobe. Every costume item sits on exactly
/// one, so the grid can group a growing catalog into a few clear rows.
public enum PetItemTheme: String, CaseIterable, Codable, Sendable {
    /// Med school and desk gear.
    case study
    /// Knits and soft layers.
    case cozy
    /// Magic, heroes and adventurers.
    case fantasy
    /// Holidays and the seasons.
    case seasonal
    /// Dress-up for laughs.
    case silly

    public var displayName: String {
        switch self {
        case .study: "Study"
        case .cozy: "Cozy"
        case .fantasy: "Fantasy"
        case .seasonal: "Seasonal"
        case .silly: "Silly"
        }
    }

    /// The theme's shop items, cheapest first. Limited edition items have
    /// their own shelf (`PetCloset.limitedShelf`).
    public var items: [PetItem] {
        PetItem.shopItems.filter { $0 != .outfit(.none) && $0.theme == self }
    }
}

extension PetItem {
    public var theme: PetItemTheme {
        switch self {
        case .outfit(let outfit):
            switch outfit {
            case .none, .scrubs, .whiteCoat: .study
            case .cozyHoodie: .cozy
            case .superheroCape, .wizardRobe: .fantasy
            case .dinosaurHoodie: .silly
            }
        case .accessory(let accessory):
            switch accessory {
            case .stethoscope, .roundGlasses, .surgicalCap, .headMirror, .graduationCap, .chunkyHeadphones,
                 .goldenLaurel: .study
            case .scarf, .beanie, .chefHat, .backwardsCap: .cozy
            case .tinyCrown, .wizardHat, .pirateHat, .blindfoldedSorcerer, .astronautHelmet, .ninjaHeadband,
                 .angelWings, .kingsCape, .halo, .sparkleTrail: .fantasy
            case .partyHat, .bunnyEars, .witchHat, .flowerCrown, .coolSunglasses, .cherryPetals, .moonlitWitchHat,
                 .pumpkinHat, .reindeerAntlers, .snowScarf, .heartGlasses, .summerShades, .lionDanceHat: .seasonal
            case .frogHat, .cowboyHat, .bowTie, .flameHeadband, .teamMedal, .rainCloud: .silly
            }
        }
    }

    /// The catalog release that added the item. Items from the latest
    /// release wear a "New" badge in the Closet until the user owns them;
    /// bump `latestRelease` and tag the next batch to move the badge on.
    public var release: Int {
        switch self {
        case .outfit(let outfit):
            switch outfit {
            case .none, .scrubs, .whiteCoat: 1
            case .cozyHoodie, .superheroCape, .dinosaurHoodie, .wizardRobe: 2
            }
        case .accessory(let accessory):
            switch accessory {
            case .stethoscope, .scarf, .roundGlasses, .surgicalCap, .headMirror, .graduationCap, .beanie: 1
            case .tinyCrown, .partyHat, .chefHat, .wizardHat, .bunnyEars, .witchHat, .cowboyHat, .flowerCrown,
                 .frogHat, .ninjaHeadband, .coolSunglasses, .pirateHat, .blindfoldedSorcerer, .astronautHelmet,
                 .chunkyHeadphones, .bowTie: 2
            case .backwardsCap, .flameHeadband, .goldenLaurel, .teamMedal, .angelWings, .kingsCape, .halo,
                 .cherryPetals, .sparkleTrail, .rainCloud: 3
            case .moonlitWitchHat, .pumpkinHat, .reindeerAntlers, .snowScarf, .heartGlasses, .summerShades, .lionDanceHat: 4
            }
        }
    }

    public static let latestRelease = 3

    /// Limited edition items never wear it: their shelf has its own badge.
    public var isNew: Bool { release == PetItem.latestRelease && !isLimited }
}
