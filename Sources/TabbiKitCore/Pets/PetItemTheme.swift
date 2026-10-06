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

    /// The theme's items, cheapest first.
    public var items: [PetItem] {
        PetItem.allCases.filter { $0 != .outfit(.none) && $0.theme == self }
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
            case .stethoscope, .roundGlasses, .surgicalCap, .headMirror, .graduationCap, .chunkyHeadphones: .study
            case .scarf, .beanie, .chefHat: .cozy
            case .tinyCrown, .wizardHat, .pirateHat, .blindfoldedSorcerer, .astronautHelmet, .ninjaHeadband: .fantasy
            case .partyHat, .bunnyEars, .witchHat, .flowerCrown, .coolSunglasses: .seasonal
            case .frogHat, .cowboyHat, .bowTie: .silly
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
            }
        }
    }

    public static let latestRelease = 2

    public var isNew: Bool { release == PetItem.latestRelease }
}
