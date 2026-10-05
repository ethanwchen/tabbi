import XCTest
@testable import TabbiKitCore

final class PetKitDefaultsTests: XCTestCase {
    private func starter(_ pet: KitValue?) -> PetProfile {
        PetProfile.starter(kit: KitDefaults(moduleSettings: pet.map { ["closet": ["pet": $0]] } ?? [:]))
    }

    func testAKitWithoutAPetStartsOnTheStarterCat() {
        XCTAssertEqual(PetProfile.starter(kit: nil), .starter(.cat))
        XCTAssertEqual(starter(nil), .starter(.cat))
    }

    func testTheKitsBreedGetsItsSpeciesStarterName() {
        let corgi = starter(["breed": "corgi"])
        XCTAssertEqual(corgi.breed, .corgi)
        XCTAssertEqual(corgi.name, PetProfile.starter(.dog).name)
    }

    func testTheKitsNameIsCleanedAndAnUnknownBreedIsSkipped() {
        let pet = starter(["breed": "dragon", "name": "  Sir   Whiskers the Magnificent  "])
        XCTAssertEqual(pet.breed, PetProfile.starter(.cat).breed)
        XCTAssertEqual(pet.name, "Sir Whiskers the")
    }

    func testMedSchoolStartsOnItsOwnPetAndEssentialsOnTheDefault() throws {
        XCTAssertEqual(PetProfile.starter(kit: try XCTUnwrap(KitLibrary.bundled["medicine"]).defaults).breed, .orangeTabby)
        XCTAssertEqual(PetProfile.starter(kit: try XCTUnwrap(KitLibrary.bundled["essentials"]).defaults).breed,
                       PetProfile.starter(kit: KitDefaults()).breed)
    }
}
