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

    func testCostumeOnlyAccessoryRidesInTheCostumeSlotWhenNoOutfitIsWorn() {
        let pet = PetProfile(name: "Doc", breed: .corgi, accessories: [.stethoscope, .beanie])
        let update = PartyPetAppearance.update(for: pet)
        XCTAssertEqual(update.costume, "stethoscope")
        XCTAssertEqual(update.accessories, ["beanie"])

        let seen = PartyPetAppearance.pet(for: profile(from: update))
        XCTAssertEqual(seen.outfit, PetOutfit.none)
        XCTAssertEqual(Set(seen.accessories), [.stethoscope, .beanie])

        let scrubbed = PetProfile(name: "Doc", breed: .corgi, outfit: .scrubs, accessories: [.stethoscope])
        XCTAssertEqual(PartyPetAppearance.update(for: scrubbed).costume, "scrubs")
    }

    func testUnknownServerValuesFallBackInsteadOfFailing() {
        let pet = PartyPetAppearance.pet(for: PartyProfile(
            code: "K7QW2MZD", name: "Ana", petName: "", species: "dragon", breed: "wyvern",
            colors: ["nope", "#123456"], costume: "pirate", accessories: ["halo", "glasses"]
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
