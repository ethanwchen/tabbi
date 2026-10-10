import Foundation

public enum PetSpecies: String, CaseIterable, Codable, Sendable {
    case cat
    case dog

    public var displayName: String {
        switch self {
        case .cat: "Cat"
        case .dog: "Dog"
        }
    }
}

/// The shared art a breed is drawn on. Breeds with the same body shape share
/// every pose; they differ only in palette and pattern.
public enum PetBodyShape: String, CaseIterable, Codable, Sendable {
    case cat
    /// Cat body with the round-cheeked, small-eared head.
    case roundCat
    /// Hairless cat with big flared ears and a wrinkled brow (Sphynx).
    case sphynxCat
    /// Small ears folded forward and down on a round owl-like head (Scottish Fold).
    case foldCat
    /// Hanging ears on a rounded skull (Labrador, Beagle).
    case floppyDog
    /// Long feathered ears (Golden Retriever).
    case fluffyDog
    /// Big rounded bat ears on a broad flat face (French Bulldog).
    case batEaredDog
    /// Tall pointed ears and a fox-like face (Corgi).
    case pointyEaredDog
    /// Long snout and a long low body (Dachshund).
    case longDog
    /// Curly coat, a round topknot, and long pom-tipped ears (Poodle).
    case poodleDog
    /// Long flowing coat, a tied topknot, and a flat face with big round
    /// eyes (Shih Tzu).
    case shihTzuDog

    public var species: PetSpecies { PetArt.breeds.species(of: self) }
}

/// A selectable breed: which art it uses, its default colors, and how it
/// fills the pattern zones of that art. The cases name the breeds (and are
/// what pet saves store); everything else about a breed is data in
/// `Pets/PetArt/breeds.json`, which the Windows port draws from too.
public enum PetBreed: String, CaseIterable, Codable, Sendable {
    case orangeTabby
    case grayTabby
    case blackCat
    case whiteCat
    case tuxedo
    case calico
    case siamese
    case britishShorthair
    case sphynx
    case scottishFold
    case goldenRetriever
    case labrador
    case frenchBulldog
    case corgi
    case dachshund
    case beagle
    case poodle
    case shihTzu

    public var species: PetSpecies { bodyShape.species }

    public var bodyShape: PetBodyShape { definition.bodyShape }

    /// Whether the breed shows a tail when sitting. Corgis and French
    /// Bulldogs are drawn stubby-tailed, which also sets their silhouettes apart.
    public var hasTail: Bool { definition.hasTail }

    public var displayName: String { definition.name }

    public static func breeds(of species: PetSpecies) -> [PetBreed] {
        allCases.filter { $0.species == species }
    }

    /// The breed's default colors before any user recoloring.
    public var palette: PetPalette { PetPalette(definition.palette) }

    /// How each fur role follows a picked fur color. Roles left out keep
    /// the breed's own color, so white bibs, muzzles, and paws stay white.
    ///
    /// The pick becomes what the breed is known for: the coat of a solid
    /// cat or dog (a black Shih Tzu keeps its brown mouth stain), the
    /// patches of a white calico or pied French Bulldog, and the points of a
    /// Siamese, whose body turns a pale version of the pick (a flame, blue,
    /// or lilac point).
    public var furTones: [PetPaletteRole: PetFurTone] {
        switch self {
        case .orangeTabby, .grayTabby:
            [.furBase: .pick, .furShade: .darker(0.18), .furAccent: .darker(0.34),
             .belly: .lighter(0.7, chroma: 0.45)]
        case .blackCat:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.12), .belly: .lighter(0.12)]
        case .whiteCat:
            [.furBase: .pick, .furShade: .darker(0.14), .furAccent: .darker(0.06),
             .belly: .lighter(0.6, chroma: 0.4)]
        case .tuxedo:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.12)]
        case .calico:
            [.furAccent: .marking, .furSpot: .darker(0.5, chroma: 0.8)]
        case .siamese:
            [.furBase: .lighter(0.65, chroma: 0.35), .furShade: .lighter(0.45, chroma: 0.45),
             .belly: .lighter(0.8, chroma: 0.25), .furAccent: .darker(0.3, chroma: 0.8),
             .furSpot: .darker(0.1, chroma: 0.75)]
        case .britishShorthair:
            [.furBase: .pick, .furShade: .darker(0.12), .furAccent: .darker(0.35)]
        case .sphynx:
            [.furBase: .pick, .furShade: .darker(0.14), .furAccent: .darker(0.1),
             .belly: .lighter(0.35, chroma: 0.7)]
        case .scottishFold:
            [.furBase: .pick, .furShade: .darker(0.16), .furAccent: .lighter(0.2),
             .belly: .lighter(0.65, chroma: 0.4)]
        case .goldenRetriever:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.35, chroma: 0.8),
             .belly: .lighter(0.55, chroma: 0.6)]
        case .labrador:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.1), .belly: .lighter(0.1)]
        case .frenchBulldog:
            [.furSpot: .marking]
        case .corgi:
            [.furBase: .pick, .furShade: .darker(0.18), .furAccent: .lighter(0.2)]
        case .dachshund:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.1),
             .belly: .lighter(0.45, chroma: 0.8)]
        case .beagle:
            [.furBase: .pick, .furShade: .darker(0.16), .furAccent: .darker(0.22),
             .furSpot: .darker(0.55, chroma: 0.6)]
        case .poodle:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.35),
             .belly: .lighter(0.55, chroma: 0.6)]
        case .shihTzu:
            [.furBase: .pick, .furShade: .darker(0.2), .furAccent: .lighter(0.12), .belly: .lighter(0.08)]
        }
    }

    /// Fur overrides for one picked color (see `furTones`).
    public func furTint(_ pick: PetColor) -> [PetPaletteRole: PetColor] {
        palette.furTint(pick, tones: furTones)
    }

    /// Which zones of the shared art become which palette role.
    public var pattern: PetPattern { PetPattern(definition.pattern) }

    private var definition: PetArtFile.BreedDefinition { PetArt.breeds.breed(self) }
}
