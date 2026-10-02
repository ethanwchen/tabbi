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

    public var species: PetSpecies { .cat }

    public var bodyShape: PetBodyShape {
        self == .britishShorthair ? .roundCat : .cat
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
                               .belly: c("#3A3540"), .eye: c("#2F8F4E"), .eyeLight: c("#E9FFE0")])
        case .whiteCat:
            return PetPalette([.furBase: c("#FAF7F2"), .furShade: c("#DCD6CF"), .furAccent: c("#EFE9E2"),
                               .belly: c("#FFFFFF"), .eye: c("#3B6FB6"), .outline: c("#3A3038")])
        case .tuxedo:
            return PetPalette([.furBase: c("#2B2830"), .furShade: c("#1E1B22"), .furAccent: c("#3A3540"),
                               .belly: c("#F7F4EF"), .eye: c("#D9A92B"), .eyeLight: c("#FFF6D6")])
        case .calico:
            return PetPalette([.furBase: c("#FBF6EE"), .furShade: c("#E2DACF"), .furAccent: c("#EE9A4D"), .furSpot: c("#3B3238"),
                               .belly: c("#FFFFFF"), .outline: c("#3A2A22")])
        case .siamese:
            return PetPalette([.furBase: c("#F3E6D2"), .furShade: c("#DCCAB0"), .furAccent: c("#5A4034"),
                               .belly: c("#FBF4E8"), .eye: c("#3E8FD8"), .outline: c("#3A2A22")])
        case .britishShorthair:
            return PetPalette([.furBase: c("#8E9AAD"), .furShade: c("#76839A"), .furAccent: c("#6A7790"),
                               .belly: c("#A5B0C0"), .eye: c("#E3A12C"), .eyeLight: c("#FFF4D2"),
                               .outline: c("#1F232B")])
        }
    }

    /// Which zones of the shared art become which palette role.
    public var pattern: PetPattern {
        switch self {
        case .orangeTabby, .grayTabby:
            return PetPattern([.stripes: .furAccent])
        case .blackCat:
            return PetPattern([.muzzle: .furBase, .chest: .furBase])
        case .whiteCat:
            return PetPattern([.muzzle: .belly, .chest: .belly])
        case .tuxedo:
            return PetPattern([.paws: .belly, .muzzle: .belly, .chest: .belly, .mask: .belly])
        case .calico:
            return PetPattern([.patchA: .furAccent, .patchB: .furSpot, .paws: .belly])
        case .siamese:
            return PetPattern([.ears: .furAccent, .mask: .furAccent, .paws: .furAccent, .tailTip: .furAccent,
                               .muzzle: .furAccent])
        case .britishShorthair:
            return PetPattern([.muzzle: .belly, .chest: .furBase])
        }
    }
}
