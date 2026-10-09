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

    public var species: PetSpecies {
        switch self {
        case .cat, .roundCat, .sphynxCat, .foldCat: .cat
        case .floppyDog, .fluffyDog, .batEaredDog, .pointyEaredDog, .longDog, .poodleDog, .shihTzuDog: .dog
        }
    }
}

/// A selectable breed: which art it uses, its default colors, and how it
/// fills the pattern zones of that art.
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

    public var bodyShape: PetBodyShape {
        switch self {
        case .orangeTabby, .grayTabby, .blackCat, .whiteCat, .tuxedo, .calico, .siamese: .cat
        case .britishShorthair: .roundCat
        case .sphynx: .sphynxCat
        case .scottishFold: .foldCat
        case .goldenRetriever: .fluffyDog
        case .labrador, .beagle: .floppyDog
        case .frenchBulldog: .batEaredDog
        case .corgi: .pointyEaredDog
        case .dachshund: .longDog
        case .poodle: .poodleDog
        case .shihTzu: .shihTzuDog
        }
    }

    /// Whether the breed shows a tail when sitting. Corgis and French
    /// Bulldogs are drawn stubby-tailed, which also sets their silhouettes apart.
    public var hasTail: Bool {
        switch self {
        case .corgi, .frenchBulldog: false
        default: true
        }
    }

    public var displayName: String {
        switch self {
        case .orangeTabby: "Orange Tabby"
        case .grayTabby: "Gray Tabby"
        case .blackCat: "Black"
        case .whiteCat: "White"
        case .tuxedo: "Tuxedo"
        case .calico: "Calico"
        case .siamese: "Siamese"
        case .britishShorthair: "British Shorthair"
        case .sphynx: "Sphynx"
        case .scottishFold: "Scottish Fold"
        case .goldenRetriever: "Golden Retriever"
        case .labrador: "Labrador"
        case .frenchBulldog: "French Bulldog"
        case .corgi: "Corgi"
        case .dachshund: "Dachshund"
        case .beagle: "Beagle"
        case .poodle: "Poodle"
        case .shihTzu: "Shih Tzu"
        }
    }

    public static func breeds(of species: PetSpecies) -> [PetBreed] {
        allCases.filter { $0.species == species }
    }

    /// The breed's default colors before any user recoloring.
    public var palette: PetPalette {
        func c(_ hex: String) -> PetColor { PetColor(hex: hex)! }
        switch self {
        case .orangeTabby:
            return PetPalette([.furBase: c("#F2A65A"), .furShade: c("#D9823E"), .furAccent: c("#C0652B"),
                               .belly: c("#FFE9CF")])
        case .grayTabby:
            return PetPalette([.furBase: c("#A9AFBA"), .furShade: c("#8A909C"), .furAccent: c("#5F6573"),
                               .belly: c("#ECEEF2"), .outline: c("#23252B")])
        case .blackCat:
            return PetPalette([.furBase: c("#2B2830"), .furShade: c("#1E1B22"), .furAccent: c("#3A3540"),
                               .belly: c("#3A3540"), .eye: c("#5CC27A"), .pupil: c("#1F6B3A"),
                               .eyeLight: c("#FFFFFF")])
        case .whiteCat:
            return PetPalette([.furBase: c("#FAF7F2"), .furShade: c("#DCD6CF"), .furAccent: c("#EFE9E2"),
                               .belly: c("#FFFFFF"), .eye: c("#3B6FB6"), .outline: c("#3A3038")])
        case .tuxedo:
            return PetPalette([.furBase: c("#2B2830"), .furShade: c("#1E1B22"), .furAccent: c("#3A3540"),
                               .belly: c("#F7F4EF"), .eye: c("#E8B838"), .pupil: c("#8A5A12"),
                               .eyeLight: c("#FFFFFF")])
        case .calico:
            return PetPalette([.furBase: c("#FBF6EE"), .furShade: c("#E2DACF"), .furAccent: c("#EE9A4D"), .furSpot: c("#3B3238"),
                               .belly: c("#FFFFFF"), .outline: c("#3A2A22")])
        case .siamese:
            return PetPalette([.furBase: c("#F3E6D2"), .furShade: c("#DCCAB0"), .furAccent: c("#5A4034"),
                               .furSpot: c("#8A6450"), .belly: c("#FBF4E8"), .eye: c("#3E8FD8"),
                               .outline: c("#3A2A22")])
        case .britishShorthair:
            // Shaded silver: a soft white-silver coat with a faintly ticked
            // back and subtly ringed tail, white chin and chest, clear blue
            // eyes, a pink-tan nose, and rosy cheeks.
            return PetPalette([.furBase: c("#EEEBE7"), .furShade: c("#D8D2CB"), .furAccent: c("#A8A098"),
                               .belly: c("#FFFFFF"), .eye: c("#3F86D6"), .eyeLight: c("#FFFFFF"),
                               .nose: c("#D9998B"), .blush: c("#FB9FAA"), .outline: c("#3A3330")])
        case .sphynx:
            // Hairless pink-beige skin with a gentle shade for wrinkles, a
            // rosy blush, and big green-gold eyes.
            return PetPalette([.furBase: c("#F1CDB8"), .furShade: c("#E0B29C"), .furAccent: c("#E6B8A2"),
                               .belly: c("#F8DCCB"), .eye: c("#7DB83A"), .eyeLight: c("#FFFFFF"),
                               .nose: c("#D9868A"), .blush: c("#F29A9C"), .outline: c("#4A2C2A")])
        case .scottishFold:
            // Blue-gray: a soft gray coat with a paler muzzle and chest,
            // big copper-gold eyes, a rosy nose, and pink cheeks.
            return PetPalette([.furBase: c("#A3A8B3"), .furShade: c("#888D99"), .furAccent: c("#BCC0C9"),
                               .belly: c("#E6E8EC"), .eye: c("#C67818"), .eyeLight: c("#FFF6DC"),
                               .nose: c("#D58C90"), .blush: c("#F59AA8"), .outline: c("#2A2B31")])
        case .goldenRetriever:
            return PetPalette([.furBase: c("#E6AE52"), .furShade: c("#C98C36"), .furAccent: c("#F3CB82"),
                               .belly: c("#F7DCA8"), .nose: c("#3A2622"), .outline: c("#3A2214")])
        case .labrador:
            return PetPalette([.furBase: c("#7C4D31"), .furShade: c("#623B25"), .furAccent: c("#8F5C3C"),
                               .belly: c("#8F5C3C"), .eye: c("#2A1810"), .eyeLight: c("#FFFFFF"),
                               .nose: c("#3A231C"), .outline: c("#26160E")])
        case .frenchBulldog:
            return PetPalette([.furBase: c("#F6F1EA"), .furShade: c("#D8CFC4"), .furSpot: c("#342E33"),
                               .belly: c("#FFFFFF"), .nose: c("#2E2428"), .outline: c("#3A2A22")])
        case .corgi:
            return PetPalette([.furBase: c("#E88D3C"), .furShade: c("#C76F28"), .furAccent: c("#F2A65A"),
                               .belly: c("#FFF6EA"), .nose: c("#2E2224"), .outline: c("#3A1E10")])
        case .dachshund:
            // Black and tan: tan brow dots, muzzle, chest and paws, and the
            // breed's warm dark brown eyes. An amber iris merged with the tan
            // brow above it into one glowing orange block.
            return PetPalette([.furBase: c("#302729"), .furShade: c("#221B1D"), .furAccent: c("#3E3337"),
                               .belly: c("#C9803F"), .eye: c("#8A5632"), .pupil: c("#4A2A1A"),
                               .eyeLight: c("#FFFFFF"),
                               .nose: c("#1E1618")])
        case .beagle:
            return PetPalette([.furBase: c("#D58F48"), .furShade: c("#B57234"), .furAccent: c("#A9652C"),
                               .furSpot: c("#332D31"), .belly: c("#FFF8EE"), .nose: c("#2E2224"),
                               .outline: c("#3A1E10")])
        case .poodle:
            // Apricot curls with lighter tips, a cream muzzle, and a dark
            // nose and eyes.
            return PetPalette([.furBase: c("#EDB27A"), .furShade: c("#CC8A52"), .furAccent: c("#F8D2A6"),
                               .belly: c("#FBE3C6"), .nose: c("#3A2622"), .outline: c("#3A2214")])
        case .shihTzu:
            // Gold and white: a white coat and beard, a gold topknot, mask,
            // and ears, and big dark eyes with a bright catchlight over a
            // warm brown iris, so they read as eyes, not dark glasses.
            return PetPalette([.furBase: c("#F8F2EA"), .furShade: c("#DCCDBC"), .furAccent: c("#D9A35C"),
                               .belly: c("#FFFFFF"), .eye: c("#7A4A2E"), .pupil: c("#2A1A14"),
                               .eyeLight: c("#FFFFFF"),
                               .nose: c("#2E2224"), .outline: c("#3A2A22")])
        }
    }

    /// Which zones of the shared art become which palette role.
    public var pattern: PetPattern {
        switch self {
        case .orangeTabby, .grayTabby:
            return PetPattern([.stripes: .furAccent])
        case .blackCat:
            // A faint lighter chest gives the solid coat a soft sheen instead of a flat blob.
            return PetPattern([.muzzle: .furBase, .chest: .furAccent])
        case .whiteCat:
            return PetPattern([.muzzle: .belly, .chest: .belly])
        case .tuxedo:
            return PetPattern([.paws: .belly, .muzzle: .belly, .chest: .belly, .mask: .belly])
        case .calico:
            return PetPattern([.patchA: .furAccent, .patchB: .furSpot, .paws: .belly])
        case .siamese:
            return PetPattern([.ears: .furAccent, .mask: .furSpot, .paws: .furAccent, .tailTip: .furAccent,
                               .muzzle: .furSpot])
        case .britishShorthair:
            return PetPattern([.muzzle: .belly, .chest: .belly, .paws: .belly, .ears: .furShade,
                               .mask: .furShade, .stripes: .furShade, .tailTip: .furAccent])
        case .sphynx:
            return PetPattern([.chest: .belly, .muzzle: .belly])
        case .scottishFold:
            return PetPattern([.muzzle: .belly, .chest: .belly, .paws: .belly, .ears: .furAccent, .tailTip: .furShade,
                               .stripes: .furBase, .patchA: .furBase, .patchB: .furBase])
        case .goldenRetriever:
            return PetPattern([.chest: .furAccent, .muzzle: .furAccent])
        case .labrador:
            return PetPattern([.muzzle: .furBase, .chest: .furBase])
        case .frenchBulldog:
            return PetPattern([.ears: .furSpot, .patchB: .furSpot])
        case .corgi:
            return PetPattern([.mask: .belly, .paws: .belly])
        case .dachshund:
            return PetPattern([.patchA: .belly, .paws: .belly])
        case .beagle:
            return PetPattern([.ears: .furAccent, .mask: .belly, .patchA: .furSpot, .paws: .belly, .tailTip: .belly])
        case .poodle:
            return PetPattern([.chest: .furAccent, .muzzle: .belly])
        case .shihTzu:
            return PetPattern([.ears: .furAccent, .mask: .furAccent, .tailTip: .furAccent])
        }
    }
}
