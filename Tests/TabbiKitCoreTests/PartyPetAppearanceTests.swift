import XCTest
import TabbiKitCore

final class PartyPetAppearanceTests: XCTestCase {
    /// The server's catalog, read from the worker's source so a catalog
    /// change that the app cannot send shows up here.
    private struct Catalog: Decodable {
        var species: [String]
        var breeds: [String: [String]]
        var costumes: [String]
        var accessories: [String]
        var limits: [String: Int]
    }

    private func catalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/shared/catalog.json")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func profile(from update: PartyProfileUpdate, code: String = "K7QW2MZD") -> PartyProfile {
        PartyProfile(
            code: code,
            name: "Ana",
            petName: update.petName ?? "",
            species: update.species ?? "cat",
            breed: update.breed ?? "",
            colors: update.colors ?? [],
            costume: update.costume ?? "none",
            accessories: update.accessories ?? []
        )
    }

    func testEveryDrawnPetSendsOnlyCatalogValues() throws {
        let catalog = try catalog()
        for breed in PetBreed.allCases {
            let pet = PetProfile(
                name: "Mochi", breed: breed, outfit: .scrubs,
                accessories: PetAccessory.allCases
            )
            let update = PartyPetAppearance.update(for: pet)
            XCTAssertTrue(catalog.species.contains(update.species ?? ""), "\(breed)")
            XCTAssertTrue(catalog.breeds[update.species ?? ""]?.contains(update.breed ?? "") == true, "\(breed)")
            XCTAssertTrue(catalog.costumes.contains(update.costume ?? ""), "\(breed)")
            for accessory in update.accessories ?? [] {
                XCTAssertTrue(catalog.accessories.contains(accessory), accessory)
            }
            XCTAssertLessThanOrEqual(update.accessories?.count ?? 0, catalog.limits["maxAccessories"] ?? 0)
            XCTAssertLessThanOrEqual(update.colors?.count ?? 0, catalog.limits["maxColors"] ?? 0)
            for color in update.colors ?? [] {
                XCTAssertNotNil(color.range(of: "^#[0-9A-F]{6}$", options: .regularExpression), color)
            }
        }
        for outfit in PetOutfit.allCases {
            let update = PartyPetAppearance.update(for: PetProfile(name: "Mochi", breed: .calico, outfit: outfit))
            XCTAssertTrue(catalog.costumes.contains(update.costume ?? ""), "\(outfit)")
        }
    }

    func testEveryCatalogBreedDrawsAPetOfTheSameSpecies() throws {
        let catalog = try catalog()
        for (species, breeds) in catalog.breeds {
            for breed in breeds {
                let pet = PartyPetAppearance.pet(for: PartyProfile(
                    code: "K7QW2MZD", name: "Ana", petName: "Mochi", species: species, breed: breed
                ))
                XCTAssertEqual(pet.species.rawValue, species, breed)
            }
        }
    }

    func testRecoloredDressedPetLooksTheSameToFriends() {
        var pet = PetProfile(name: "Pixel", breed: .grayTabby, outfit: .whiteCoat, accessories: [.roundGlasses, .scarf])
        pet.tintFur(PetColor(hex: "#8E6FD1"))
        pet.setColor(PetColor(hex: "#3366CC"), for: .costumeBase)

        let seen = PartyPetAppearance.pet(for: profile(from: PartyPetAppearance.update(for: pet)))

        XCTAssertEqual(seen.name, "Pixel")
        XCTAssertEqual(seen.species, .cat)
        XCTAssertEqual(seen.outfit, .whiteCoat)
        XCTAssertEqual(Set(seen.accessories), [.roundGlasses, .scarf])
        for role in PartyPetAppearance.colorRoles {
            XCTAssertEqual(seen.palette[role], pet.palette[role], "\(role)")
        }
        XCTAssertEqual(seen.sittingCanvas(), pet.sittingCanvas())
    }

    func testDrawnBreedsRoundTripExceptTheTwoTabbies() {
        for breed in PetBreed.allCases {
            let seen = PartyPetAppearance.pet(for: profile(from: PartyPetAppearance.update(for: PetProfile(name: "A", breed: breed))))
            // Gray and orange tabbies share the server's `tabby`; the colors
            // keep the gray one gray.
            XCTAssertEqual(seen.breed, breed == .grayTabby ? .orangeTabby : breed)
            XCTAssertEqual(seen.palette[.furBase], PetProfile(name: "A", breed: breed).palette[.furBase], "\(breed)")
        }
    }

    /// The bug users saw: friends' Party showed pets without their hats.
    /// A hat the server had no id for (the wizard or cowboy hat) never left
    /// the Mac, and a medical or costume hat only rode in `costume`, so it
    /// was dropped as soon as an outfit was worn.
    func testHatsReachFriendsWithAndWithoutAnOutfit() {
        let looks: [PetProfile] = [
            PetProfile(name: "Luna", breed: .siamese, outfit: .scrubs, accessories: [.surgicalCap]),
            PetProfile(name: "Mochi", breed: .orangeTabby, outfit: .whiteCoat, accessories: [.graduationCap, .stethoscope]),
            PetProfile(name: "Biscuit", breed: .goldenRetriever, accessories: [.roundGlasses, .cowboyHat]),
            PetProfile(name: "Pepper", breed: .blackCat, outfit: .wizardRobe, accessories: [.wizardHat]),
            PetProfile(name: "Kit", breed: .beagle, outfit: .cozyHoodie, accessories: [.pirateHat, .scarf]),
        ]
        for pet in looks {
            let seen = PartyPetAppearance.pet(for: profile(from: PartyPetAppearance.update(for: pet)))
            XCTAssertEqual(seen.outfit, pet.outfit, pet.name)
            XCTAssertEqual(seen.accessories, pet.accessories, pet.name)
            XCTAssertEqual(seen.sittingCanvas(), pet.sittingCanvas(), pet.name)
        }
    }

    /// Every outfit with every accessory, and every slot at once, looks the
    /// same to friends as in the owner's Closet, recolored roles included.
    func testEveryOutfitAndAccessoryLooksTheSameToFriends() {
        for outfit in PetOutfit.allCases {
            for accessory in PetAccessory.allCases {
                let pet = PetProfile(name: "Mochi", breed: .calico, outfit: outfit, accessories: [accessory])
                let seen = PartyPetAppearance.pet(for: profile(from: PartyPetAppearance.update(for: pet)))
                XCTAssertEqual(seen.outfit, outfit, "\(outfit) + \(accessory)")
                XCTAssertEqual(seen.accessories, [accessory], "\(outfit) + \(accessory)")
            }
        }
        var full = PetProfile(name: "Nova", breed: .corgi, outfit: .studyHoodie,
                              accessories: [.snowScarf, .heartGlasses, .lionDanceHat, .kingsCape, .cherryPetals])
        for (index, role) in PetPaletteRole.userEditable.enumerated() {
            full.setColor(PetColor(hex: String(format: "#%02X%02X%02X", 40 + index * 20, 200 - index * 15, 90 + index * 9)), for: role)
        }
        let update = PartyPetAppearance.update(for: full)
        XCTAssertEqual(update.accessories?.count, 5)
        let seen = PartyPetAppearance.pet(for: profile(from: update))
        XCTAssertEqual(seen.accessories, full.accessories)
        for role in PetPaletteRole.userEditable {
            XCTAssertEqual(seen.palette[role], full.palette[role], "\(role)")
        }
        XCTAssertEqual(seen.sittingCanvas(), full.sittingCanvas())
    }

    /// Apps before catalog version 2 only read a hat from `costume`, so it
    /// is still sent there when no outfit is worn, and a profile such an
    /// app wrote still reads the same.
    func testOlderAppsStillGetAndSendTheHatInTheCostumeSlot() {
        let pet = PetProfile(name: "Doc", breed: .corgi, accessories: [.stethoscope, .beanie])
        let update = PartyPetAppearance.update(for: pet)
        XCTAssertEqual(update.costume, "stethoscope")
        XCTAssertEqual(update.accessories, ["stethoscope", "beanie"])
        XCTAssertEqual(PartyPetAppearance.pet(for: profile(from: update)).accessories, [.stethoscope, .beanie])

        let scrubbed = PetProfile(name: "Doc", breed: .corgi, outfit: .scrubs, accessories: [.stethoscope])
        XCTAssertEqual(PartyPetAppearance.update(for: scrubbed).costume, "scrubs")

        // What a 1.0 app sent for a graduation cap and glasses.
        var old = profile(from: PartyProfileUpdate(petName: "Mochi", species: "cat", breed: "tabby"))
        old.costume = "graduation"
        old.accessories = ["glasses"]
        XCTAssertEqual(PartyPetAppearance.pet(for: old).accessories, [.roundGlasses, .graduationCap])
        // A head item the accessories name wins over the costume slot's.
        old.accessories = ["glasses", "beanie"]
        XCTAssertEqual(PartyPetAppearance.pet(for: old).accessories, [.roundGlasses, .beanie])
    }

    func testPlayfulItemsReachFriends() {
        let crowned = PetProfile(name: "Kit", breed: .tuxedo, accessories: [.bowTie, .coolSunglasses, .tinyCrown])
        let update = PartyPetAppearance.update(for: crowned)
        XCTAssertEqual(update.costume, "none")
        XCTAssertEqual(update.accessories, ["bow", "sunglasses", "crown"])
        XCTAssertEqual(PartyPetAppearance.pet(for: profile(from: update)).accessories, [.bowTie, .coolSunglasses, .tinyCrown])

        let pirate = PetProfile(name: "Kit", breed: .beagle, accessories: [.partyHat, .pirateHat])
        let pirateUpdate = PartyPetAppearance.update(for: pirate)
        XCTAssertEqual(pirateUpdate.costume, "pirate")
        XCTAssertEqual(pirateUpdate.accessories, ["pirate-hat"])
        XCTAssertEqual(PartyPetAppearance.pet(for: profile(from: pirateUpdate)).accessories, [.pirateHat])
    }

    /// A self-hosted server still on catalog version 1 gets what it takes.
    func testAnUpdateForCatalogVersion1KeepsOnlyWhatItKnows() {
        let pet = PetProfile(name: "Nova", breed: .corgi, outfit: .dinosaurHoodie,
                             accessories: [.scarf, .heartGlasses, .wizardHat, .angelWings])
        let update = PartyPetAppearance.update(for: pet).forCatalogVersion1()
        XCTAssertEqual(update.costume, "hoodie")
        XCTAssertEqual(update.accessories, ["scarf"])
        XCTAssertEqual(update.colors?.count, 6)
        let surgeon = PartyPetAppearance.update(for: PetProfile(name: "Doc", breed: .corgi, accessories: [.surgicalCap]))
        XCTAssertEqual(surgeon.forCatalogVersion1().costume, "surgical-cap")
        XCTAssertEqual(surgeon.forCatalogVersion1().accessories, [])
    }

    /// A server that predates the British Longhair gets the breed it has
    /// with the closest body, and a longhair from a breed without art comes
    /// back as a British Longhair.
    func testTheBritishLonghairReachesOlderServersAsALonghair() {
        let update = PartyPetAppearance.update(for: PetProfile(name: "Mocha", breed: .britishLonghair))
        XCTAssertEqual(update.breed, "british-longhair")
        XCTAssertEqual(update.forCatalogVersion1().breed, "domestic-longhair")
        XCTAssertEqual(PartyPetAppearance.update(for: PetProfile(name: "Nova", breed: .corgi)).forCatalogVersion1().breed, "corgi")
        for wire in ["british-longhair", "persian"] {
            let profile = PartyProfile(code: "K7QW2MZD", name: "Ana", petName: "Mocha", species: "cat", breed: wire)
            XCTAssertEqual(PartyPetAppearance.pet(for: profile).breed, .britishLonghair, wire)
        }
    }

    /// The mastery outfits ride in catalog version 4: friends on this
    /// version see them, a version 3 server gets the pet without them, and
    /// the two that reuse older ids (pajamas, bandana) reach it anyway.
    func testMasteryOutfitsReachFriendsAndOlderServersDropThem() throws {
        let catalog = try catalog()
        let pet = PetProfile(name: "Nova", breed: .corgi, outfit: .astronautSuit,
                             accessories: [.friendshipBandana, .nightcap, .roundGlasses, .tinyLantern])
        let update = PartyPetAppearance.update(for: pet)
        XCTAssertEqual(update.costume, "astronaut-suit")
        XCTAssertEqual(update.accessories, ["bandana", "glasses", "nightcap", "tiny-lantern"])
        XCTAssertEqual(PartyPetAppearance.pet(for: profile(from: update)).outfit, .astronautSuit)
        XCTAssertEqual(Set(PartyPetAppearance.pet(for: profile(from: update)).accessories), Set(pet.accessories))

        let older = update.forCatalogVersion3()
        XCTAssertEqual(older.costume, "none")
        XCTAssertEqual(older.accessories, ["bandana", "glasses"])
        XCTAssertEqual(update.olderCatalogFallback, older)
        XCTAssertEqual(older.olderCatalogFallback, older.forCatalogVersion1())
        XCTAssertNil(older.forCatalogVersion1().olderCatalogFallback)

        let pajamas = PartyPetAppearance.update(for: PetProfile(name: "Bo", breed: .corgi, outfit: .cozyPajamas))
        XCTAssertEqual(pajamas.costume, "pajamas")
        XCTAssertEqual(pajamas.forCatalogVersion3(), pajamas, "a version 3 server already takes pajamas")

        for outfit in PetOutfit.allCases where outfit != .none && PetItem.outfit(outfit).limitedEdition?.isMastery == true {
            let wire = PartyPetAppearance.update(for: PetProfile(name: "Bo", breed: .corgi, outfit: outfit)).costume ?? ""
            XCTAssertTrue(catalog.costumes.contains(wire), wire)
        }
    }

    func testTheCatalogIsVersion4AndOnlyEverAdds() throws {
        struct Versioned: Decodable { var version: Int; var costumes: [String]; var accessories: [String] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/shared/catalog.json")
        let catalog = try JSONDecoder().decode(Versioned.self, from: Data(contentsOf: url))
        XCTAssertEqual(catalog.version, 4)
        for id in ["astronaut-suit", "starry-cloak", "apprentice-robe", "scholars-robe", "sages-robe", "bakers-apron"] {
            XCTAssertTrue(catalog.costumes.contains(id), id)
        }
        for id in ["little-sprout", "blossom-sprout", "nightcap", "explorers-hat", "bee-antennae", "sporty-sweatband",
                   "owl-spectacles", "tiny-lantern", "bandana"] {
            XCTAssertTrue(catalog.accessories.contains(id), id)
        }
        // What came before stays, in the same order, at the front.
        XCTAssertEqual(Array(catalog.costumes.prefix(22)).last, "study-hoodie")
        XCTAssertEqual(Array(catalog.accessories.prefix(50)).last, "rain-cloud")
    }

    func testUnknownServerValuesFallBackInsteadOfFailing() {
        let pet = PartyPetAppearance.pet(for: PartyProfile(
            code: "K7QW2MZD", name: "Ana", petName: "", species: "dragon", breed: "wyvern",
            colors: ["nope", "#123456"], costume: "santa", accessories: ["jetpack", "glasses"]
        ))
        XCTAssertEqual(pet.breed, PetProfile.starter(.cat).breed)
        XCTAssertEqual(pet.name, pet.breed.displayName)
        XCTAssertEqual(pet.outfit, PetOutfit.none)
        XCTAssertEqual(pet.accessories, [.roundGlasses])
        XCTAssertEqual(pet.palette[.furBase], PetProfile.starter(.cat).palette[.furBase])
        XCTAssertEqual(pet.palette[.furShade], PetColor(hex: "#123456"))

        let dog = PartyPetAppearance.pet(for: PartyProfile(code: "K7QW2MZD", name: "B", petName: "Rex", species: "dog", breed: "unknown"))
        XCTAssertEqual(dog.species, .dog)
    }
}
