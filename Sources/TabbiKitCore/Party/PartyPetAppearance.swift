import Foundation

/// Translates between the local `PetProfile` and the server's pet fields.
///
/// The server catalog (`backend/shared/catalog.json`) is wider than the
/// pixel art: it knows 36 breeds and 20 costumes, the app draws 14 breeds,
/// two outfits and seven accessories. So the mapping is lossy by design:
/// - Breeds the app cannot draw fall back to the drawn breed with the
///   closest body, and the sender's colors still make the pet look like theirs.
/// - `colors` carries the sender's effective colors for `colorRoles`, in that
///   order, so a recolored pet looks the same to friends.
/// - The server has no neck/head accessory slots for the stethoscope,
///   surgical cap and graduation cap, but does have them as costumes, so one
///   of them rides in `costume` when no outfit is worn.
///
/// Only appearance goes through here; nothing about cards or decks.
public enum PartyPetAppearance {
    /// The palette roles sent in `colors`, in wire order (at most 6).
    public static let colorRoles: [PetPaletteRole] = [
        .furBase, .furShade, .furAccent, .furSpot, .belly, .costumeBase,
    ]

    /// The pet fields of a profile update for `pet`.
    public static func update(for pet: PetProfile) -> PartyProfileUpdate {
        let palette = pet.palette
        let fallbackCostume = costumeAccessories.first { pet.accessories.contains($0.accessory) }
        let costume = pet.outfit == .none ? fallbackCostume?.wire ?? "none" : wireOutfit(pet.outfit)
        let accessories = pet.accessories.compactMap { accessory in
            wireAccessories.first { $0.accessory == accessory }?.wire
        }
        return PartyProfileUpdate(
            petName: pet.name,
            species: pet.species.rawValue,
            breed: wireBreed(pet.breed),
            colors: colorRoles.map { opaqueHex(palette[$0]) },
            costume: costume,
            accessories: accessories
        )
    }

    /// The pet to draw for someone's server profile. Never fails: unknown
    /// breeds, costumes, accessories and colors fall back or are dropped.
    public static func pet(for profile: PartyProfile) -> PetProfile {
        let breed = localBreed(profile.breed, species: profile.species)
        var accessories = profile.accessories.compactMap { wire in
            wireAccessories.first { $0.wire == wire }?.accessory
        }
        var outfit = PetOutfit.none
        if let local = localOutfit(profile.costume) {
            outfit = local
        } else if let accessory = costumeAccessories.first(where: { $0.wire == profile.costume })?.accessory {
            accessories.append(accessory)
        }
        var pet = PetProfile(name: profile.petName, breed: breed, outfit: outfit, accessories: accessories)
        for (role, hex) in zip(colorRoles, profile.colors) {
            if let color = PetColor(hex: hex) { pet.setColor(color, for: role) }
        }
        return pet
    }

    // MARK: Breeds

    /// The server id for each drawn breed. Server breeds without art map back
    /// through `fallbackBreeds`.
    static func wireBreed(_ breed: PetBreed) -> String {
        switch breed {
        case .orangeTabby, .grayTabby: "tabby"
        case .blackCat: "black-cat"
        case .whiteCat: "domestic-shorthair"
        case .tuxedo: "tuxedo"
        case .calico: "calico"
        case .siamese: "siamese"
        case .britishShorthair: "british-shorthair"
        case .goldenRetriever: "golden-retriever"
        case .labrador: "labrador"
        case .frenchBulldog: "french-bulldog"
        case .corgi: "corgi"
        case .dachshund: "dachshund"
        case .beagle: "beagle"
        }
    }

    /// Server breeds the app has no art for, mapped to the drawn breed with
    /// the most similar body (ears, fluff, length).
    static let fallbackBreeds: [String: PetBreed] = [
        "domestic-longhair": .britishShorthair,
        "tortoiseshell": .calico,
        "persian": .britishShorthair,
        "maine-coon": .britishShorthair,
        "ragdoll": .britishShorthair,
        "bengal": .orangeTabby,
        "sphynx": .siamese,
        "scottish-fold": .britishShorthair,
        "russian-blue": .grayTabby,
        "abyssinian": .orangeTabby,
        "norwegian-forest": .britishShorthair,
        "mixed": .beagle,
        "german-shepherd": .corgi,
        "shiba-inu": .corgi,
        "husky": .corgi,
        "poodle": .goldenRetriever,
        "pug": .frenchBulldog,
        "border-collie": .labrador,
        "samoyed": .goldenRetriever,
        "chihuahua": .frenchBulldog,
        "pomeranian": .goldenRetriever,
        "dalmatian": .labrador,
        "bernese": .goldenRetriever,
    ]

    static func localBreed(_ wire: String, species: String) -> PetBreed {
        if let breed = PetBreed.allCases.first(where: { wireBreed($0) == wire }) { return breed }
        if let breed = fallbackBreeds[wire] { return breed }
        return PetProfile.starter(PetSpecies(rawValue: species) ?? .cat).breed
    }

    // MARK: Costumes and accessories

    private static func wireOutfit(_ outfit: PetOutfit) -> String {
        switch outfit {
        case .none: "none"
        case .scrubs: "scrubs"
        case .whiteCoat: "white-coat"
        }
    }

    private static func localOutfit(_ wire: String) -> PetOutfit? {
        PetOutfit.allCases.first { $0 != .none && wireOutfit($0) == wire }
    }

    /// Accessories the server has as accessories.
    private static let wireAccessories: [(accessory: PetAccessory, wire: String)] = [
        (.roundGlasses, "glasses"), (.scarf, "scarf"), (.beanie, "beanie"),
    ]

    /// Accessories the server only has as costumes, in preference order.
    /// The head mirror has no server id and stays local.
    private static let costumeAccessories: [(accessory: PetAccessory, wire: String)] = [
        (.stethoscope, "stethoscope"), (.surgicalCap, "surgical-cap"), (.graduationCap, "graduation"),
    ]

    /// The server takes `#RRGGBB` only.
    private static func opaqueHex(_ color: PetColor) -> String {
        String(color.hex.prefix(7))
    }
}
