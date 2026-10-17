import Foundation

/// Translates between the local `PetProfile` and the server's pet fields.
///
/// Friends see a pet exactly as its owner dressed it in the Closet: the
/// server catalog (`backend/shared/catalog.json`, version 3) has an id for
/// every outfit and every accessory the app draws, so the outfit rides in
/// `costume`, every worn accessory (hats, wings, auras and all) in
/// `accessories`, and the effective colors of every recolorable role in
/// `colors`. Breeds are the one lossy part: the server knows 37 and the app
/// draws 19, so a breed without art falls back to the drawn breed with the
/// closest body, and the sender's colors still make it look like theirs.
///
/// Apps from before catalog version 2 only knew a few accessory ids and
/// carried the medical and costume hats in `costume` when no outfit was
/// worn. That fallback is still sent, so their friends' older apps keep
/// showing it, and still read, so a profile an older app wrote looks the
/// same as before. Ids an app does not know are dropped, never an error.
///
/// Only appearance goes through here; nothing about cards or decks.
public enum PartyPetAppearance {
    /// The palette roles sent in `colors`, in wire order: every role the
    /// Closet can recolor. Catalog version 1 took six, so older apps read
    /// the first six and ignore the rest.
    public static let colorRoles: [PetPaletteRole] = [
        .furBase, .furShade, .furAccent, .furSpot, .belly, .costumeBase,
        .costumeShade, .costumeTrim, .accessoryBase, .accessoryShade,
    ]

    /// The pet fields of a profile update for `pet`.
    public static func update(for pet: PetProfile) -> PartyProfileUpdate {
        let palette = pet.palette
        return PartyProfileUpdate(
            petName: pet.name,
            species: pet.species.rawValue,
            breed: wireBreed(pet.breed),
            colors: colorRoles.map { opaqueHex(palette[$0]) },
            costume: pet.outfit == .none ? legacyCostume(for: pet.accessories) : wireOutfit(pet.outfit),
            accessories: pet.accessories.map(wireAccessory)
        )
    }

    /// The pet to draw for someone's server profile. Never fails: unknown
    /// breeds, costumes, accessories and colors fall back or are dropped.
    public static func pet(for profile: PartyProfile) -> PetProfile {
        let breed = localBreed(profile.breed, species: profile.species)
        var accessories = profile.accessories.compactMap { localAccessories[$0] }
        var outfit = PetOutfit.none
        if let local = localOutfit(profile.costume) {
            outfit = local
        } else if let hat = legacyCostumeAccessories.first(where: { $0.wire == profile.costume })?.accessory {
            // An older app's hat in the costume slot. Listed first, so an
            // item the accessories name for the same slot wins.
            accessories.insert(hat, at: 0)
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
        case .sphynx: "sphynx"
        case .scottishFold: "scottish-fold"
        case .britishLonghair: "british-longhair"
        case .goldenRetriever: "golden-retriever"
        case .labrador: "labrador"
        case .frenchBulldog: "french-bulldog"
        case .corgi: "corgi"
        case .dachshund: "dachshund"
        case .beagle: "beagle"
        case .poodle: "poodle"
        // The server catalog has no Shih Tzu; its nearest small long-coated
        // toy breed is the Pomeranian, which friends' apps draw back as a Shih Tzu.
        case .shihTzu: "pomeranian"
        }
    }

    /// Server breeds the app has no art for, mapped to the drawn breed with
    /// the most similar body (ears, fluff, length).
    static let fallbackBreeds: [String: PetBreed] = [
        "domestic-longhair": .britishLonghair,
        "tortoiseshell": .calico,
        "persian": .britishLonghair,
        "maine-coon": .britishLonghair,
        "ragdoll": .britishLonghair,
        "bengal": .orangeTabby,
        "russian-blue": .grayTabby,
        "abyssinian": .orangeTabby,
        "norwegian-forest": .britishLonghair,
        "mixed": .beagle,
        "german-shepherd": .corgi,
        "shiba-inu": .corgi,
        "husky": .corgi,
        "pug": .frenchBulldog,
        "border-collie": .labrador,
        "samoyed": .goldenRetriever,
        "chihuahua": .frenchBulldog,
        "dalmatian": .labrador,
        "bernese": .goldenRetriever,
    ]

    static func localBreed(_ wire: String, species: String) -> PetBreed {
        if let breed = PetBreed.allCases.first(where: { wireBreed($0) == wire }) { return breed }
        if let breed = fallbackBreeds[wire] { return breed }
        return PetProfile.starter(PetSpecies(rawValue: species) ?? .cat).breed
    }

    // MARK: Outfits and accessories

    /// The server's costume id for each outfit. The cozy hoodie keeps the
    /// plain `hoodie` of catalog version 1.
    static func wireOutfit(_ outfit: PetOutfit) -> String {
        switch outfit {
        case .none: "none"
        case .scrubs: "scrubs"
        case .whiteCoat: "white-coat"
        case .cozyHoodie: "hoodie"
        case .superheroCape: "superhero"
        case .dinosaurHoodie: "dinosaur-hoodie"
        case .wizardRobe: "wizard"
        case .studyHoodie: "study-hoodie"
        }
    }

    private static func localOutfit(_ wire: String) -> PetOutfit? {
        PetOutfit.allCases.first { $0 != .none && wireOutfit($0) == wire }
    }

    /// The server's accessory id for each accessory. A switch, so a new
    /// accessory cannot ship without one (`PartyPetAppearanceTests` checks
    /// that the catalog lists it).
    static func wireAccessory(_ accessory: PetAccessory) -> String {
        switch accessory {
        // The ids catalog version 1 already had.
        case .roundGlasses: "glasses"
        case .coolSunglasses: "sunglasses"
        case .chunkyHeadphones: "headphones"
        case .bowTie: "bow"
        case .scarf: "scarf"
        case .tinyCrown: "crown"
        case .flowerCrown: "flower"
        case .partyHat: "party-hat"
        case .beanie: "beanie"
        case .halo: "halo"
        // Added in catalog version 2.
        case .stethoscope: "stethoscope"
        case .surgicalCap: "surgical-cap"
        case .headMirror: "head-mirror"
        case .graduationCap: "graduation-cap"
        case .chefHat: "chef-hat"
        case .wizardHat: "wizard-hat"
        case .bunnyEars: "bunny-ears"
        case .witchHat: "witch-hat"
        case .cowboyHat: "cowboy-hat"
        case .frogHat: "frog-hat"
        case .ninjaHeadband: "ninja-headband"
        case .pirateHat: "pirate-hat"
        case .blindfoldedSorcerer: "blindfolded-sorcerer"
        case .astronautHelmet: "astronaut-helmet"
        case .backwardsCap: "backwards-cap"
        case .flameHeadband: "flame-headband"
        case .goldenLaurel: "golden-laurel"
        case .teamMedal: "team-medal"
        case .moonlitWitchHat: "moonlit-witch-hat"
        case .pumpkinHat: "pumpkin-hat"
        case .reindeerAntlers: "reindeer-antlers"
        case .snowScarf: "snow-scarf"
        case .heartGlasses: "heart-glasses"
        case .summerShades: "summer-shades"
        case .lionDanceHat: "lion-dance-hat"
        case .sakuraSprig: "sakura-sprig"
        case .foundersPin: "founders-pin"
        case .angelWings: "angel-wings"
        case .kingsCape: "kings-cape"
        case .cherryPetals: "cherry-petals"
        case .sparkleTrail: "sparkle-trail"
        case .rainCloud: "rain-cloud"
        }
    }

    private static let localAccessories: [String: PetAccessory] = Dictionary(
        uniqueKeysWithValues: PetAccessory.allCases.map { (wireAccessory($0), $0) }
    )

    /// Hats catalog version 1 only had as costumes, in preference order.
    /// Apps from then sent one of them in `costume` when no outfit was worn
    /// and read nothing else, so it is still sent for them.
    private static let legacyCostumeAccessories: [(accessory: PetAccessory, wire: String)] = [
        (.stethoscope, "stethoscope"), (.surgicalCap, "surgical-cap"), (.graduationCap, "graduation"),
        (.chefHat, "chef"), (.pirateHat, "pirate"), (.witchHat, "witch"),
        (.astronautHelmet, "astronaut"), (.bunnyEars, "bunny"),
    ]

    private static func legacyCostume(for accessories: [PetAccessory]) -> String {
        legacyCostumeAccessories.first { accessories.contains($0.accessory) }?.wire ?? "none"
    }

    // MARK: Older servers

    /// The ids, limits and colors a catalog version 1 server takes. A
    /// self-hosted friends server that was not updated refuses anything
    /// else, so `PartyAccount` retries a refused profile with
    /// `PartyProfileUpdate.forCatalogVersion1()`.
    static let version1Accessories: Set<String> = [
        "glasses", "sunglasses", "headphones", "bow", "scarf", "crown", "flower", "party-hat", "beanie", "halo",
    ]
    static let version1Costumes: Set<String> = [
        "none", "scrubs", "white-coat", "hoodie", "superhero", "wizard",
        "stethoscope", "surgical-cap", "graduation", "chef", "pirate", "witch", "astronaut", "bunny",
    ]
    static let version1MaxColors = 6
    /// Breeds added after catalog version 2, sent to an older server as the
    /// breed it has with the closest body (which older apps draw as a
    /// British Shorthair).
    static let olderCatalogBreeds: [String: String] = ["british-longhair": "domestic-longhair"]
    static let version1MaxAccessories = 4

    /// The server takes `#RRGGBB` only.
    private static func opaqueHex(_ color: PetColor) -> String {
        String(color.hex.prefix(7))
    }
}

extension PartyProfileUpdate {
    /// This update as a server on catalog version 1 or 2 takes it:
    /// accessories it has no id for left out, the newer hoodies sent as the
    /// plain hoodie, newer breeds as their closest older one, and only the
    /// first six colors.
    public func forCatalogVersion1() -> PartyProfileUpdate {
        var update = self
        update.breed = breed.map { PartyPetAppearance.olderCatalogBreeds[$0] ?? $0 }
        update.colors = colors.map { Array($0.prefix(PartyPetAppearance.version1MaxColors)) }
        update.accessories = accessories.map { ids in
            Array(ids.filter(PartyPetAppearance.version1Accessories.contains).prefix(PartyPetAppearance.version1MaxAccessories))
        }
        update.costume = costume.map { id in
            if PartyPetAppearance.version1Costumes.contains(id) { return id }
            return id.hasSuffix("hoodie") ? "hoodie" : "none"
        }
        return update
    }
}
