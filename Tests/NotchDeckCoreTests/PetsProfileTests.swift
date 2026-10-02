import XCTest
import NotchDeckCore

final class PetProfileTests: XCTestCase {
    private let pink = PetColor(hex: "#FF77AA")!

    func testNamesAreCleanedCappedAndNeverEmpty() {
        XCTAssertEqual(PetProfile(name: "  Dr.   Whiskers \n", breed: .tuxedo).name, "Dr. Whiskers")
        XCTAssertEqual(PetProfile(name: "Professor Fluffington", breed: .calico).name.count, PetProfile.maxNameLength)
        XCTAssertEqual(PetProfile(name: "   ", breed: .corgi).name, "Corgi")

        var profile = PetProfile.starter(.cat)
        profile.rename("Nori")
        XCTAssertEqual(profile.name, "Nori")
    }

    func testStarterMatchesTheChosenSpecies() {
        for species in PetSpecies.allCases {
            let starter = PetProfile.starter(species)
            XCTAssertEqual(starter.species, species)
            XCTAssertEqual(starter.outfit, .none)
            XCTAssertEqual(starter.accessories, [])
        }
    }

    func testOnlyUserEditableRolesCanBeRecolored() {
        var profile = PetProfile(name: "Pip", breed: .orangeTabby, paletteOverrides: [.eye: pink, .furBase: pink])
        XCTAssertEqual(profile.paletteOverrides, [.furBase: pink])

        profile.setColor(pink, for: .outline)
        profile.setColor(pink, for: .costumeBase)
        XCTAssertEqual(profile.palette[.costumeBase], pink)
        XCTAssertEqual(profile.palette[.outline], PetBreed.orangeTabby.palette[.outline])

        profile.setColor(nil, for: .furBase)
        XCTAssertEqual(profile.palette[.furBase], PetBreed.orangeTabby.palette[.furBase])
        profile.resetColors()
        XCTAssertEqual(profile.palette, PetBreed.orangeTabby.palette)
    }

    func testRecoloringFurDarkAddsTheWarmRim() {
        var profile = PetProfile(name: "Pip", breed: .whiteCat)
        profile.setColor(PetColor(hex: "#151217")!, for: .furBase)
        XCTAssertEqual(profile.palette[.outline], PetPalette.warmRim)
    }

    func testWearingReplacesTheItemInTheSameSlot() {
        var profile = PetProfile(name: "Pip", breed: .beagle, accessories: [.beanie, .graduationCap])
        XCTAssertEqual(profile.accessories, [.graduationCap])

        profile.wear(.stethoscope)
        profile.wear(.surgicalCap)
        XCTAssertEqual(profile.accessories, [.stethoscope, .surgicalCap])
        XCTAssertTrue(profile.isWearing(.accessory(.surgicalCap)))

        profile.takeOff(.stethoscope)
        XCTAssertEqual(profile.accessories, [.surgicalCap])
        XCTAssertTrue(profile.isWearing(.outfit(.none)))
    }

    func testSittingCanvasShowsTheChosenLook() {
        let profile = PetProfile(name: "Pip", breed: .corgi, outfit: .scrubs, accessories: [.stethoscope])
        XCTAssertEqual(profile.sittingCanvas(), PetComposer.sitting(.corgi, outfit: .scrubs, accessories: [.stethoscope]))
    }

    func testProfileRoundTripsThroughJSON() throws {
        let profile = PetProfile(
            name: "Biscuit", breed: .goldenRetriever, paletteOverrides: [.costumeBase: pink],
            outfit: .whiteCoat, accessories: [.roundGlasses, .headMirror]
        )
        let decoded = try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testDecodingDropsUnknownValuesInsteadOfFailing() throws {
        let json = """
        {"name": "Mochi", "breed": "calico", "outfit": "spaceSuit",
         "accessories": ["jetpack", "beanie"],
         "paletteOverrides": {"furBase": "#112233", "sparkle": "#FFFFFF", "eye": "#00FF00"}}
        """
        let profile = try JSONDecoder().decode(PetProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.breed, .calico)
        XCTAssertEqual(profile.outfit, .none)
        XCTAssertEqual(profile.accessories, [.beanie])
        XCTAssertEqual(profile.paletteOverrides, [.furBase: PetColor(hex: "#112233")!])
    }

    func testDecodingWithoutABreedFails() {
        XCTAssertThrowsError(try JSONDecoder().decode(PetProfile.self, from: Data(#"{"name": "Mochi"}"#.utf8)))
    }
}

final class PetUnlockTests: XCTestCase {
    func testCatalogCoversEveryItemCheapestFirst() {
        let items = PetItem.allCases
        XCTAssertEqual(items.count, PetOutfit.allCases.count + PetAccessory.allCases.count)
        XCTAssertEqual(items.first, .outfit(.none))
        XCTAssertEqual(items.map(\.cost), items.map(\.cost).sorted())
        XCTAssertEqual(items.filter(\.isFree), [.outfit(.none)], "only 'no outfit' is free")
        XCTAssertEqual(items.last, .accessory(.graduationCap), "graduation is the long-term goal")
    }

    func testItemIdsAreStableAndRoundTrip() {
        XCTAssertEqual(PetItem.outfit(.whiteCoat).id, "outfit.whiteCoat")
        XCTAssertEqual(PetItem.accessory(.headMirror).id, "accessory.headMirror")
        for item in PetItem.allCases {
            XCTAssertEqual(PetItem(id: item.id), item)
        }
        XCTAssertNil(PetItem(id: "accessory.jetpack"))
        XCTAssertNil(PetItem(id: "beanie"))
        XCTAssertNil(PetItem(id: "hat.beanie"))
    }

    func testStudyMinutesBecomePoints() {
        XCTAssertEqual(PetPointsRules.points(forMinutes: 4, completed: true), 0, "too short to count")
        XCTAssertEqual(PetPointsRules.points(forMinutes: 5, completed: false), 5)
        XCTAssertEqual(PetPointsRules.points(forMinutes: 24, completed: true), 24, "no bonus under 25 min")
        XCTAssertEqual(PetPointsRules.points(forMinutes: 25, completed: false), 25, "no bonus when abandoned")
        XCTAssertEqual(PetPointsRules.points(forMinutes: 25, completed: true), 35)
        XCTAssertEqual(PetPointsRules.points(forMinutes: -10, completed: true), 0)
    }

    func testFirstFocusBlockUnlocksTheFirstItem() throws {
        var ledger = PetPointsLedger()
        XCTAssertEqual(ledger.nextUnlock, .accessory(.scarf))
        XCTAssertEqual(ledger.recordStudy(minutes: 25, completed: true), 35)
        XCTAssertTrue(ledger.canBuy(.accessory(.scarf)))
        try ledger.buy(.accessory(.scarf))
        XCTAssertEqual(ledger.balance, 5)
        XCTAssertEqual(ledger.earned, 35)
        XCTAssertEqual(ledger.nextUnlock, .accessory(.beanie))
    }

    func testPurchasesAreRefusedWithAReason() throws {
        var ledger = PetPointsLedger()
        ledger.recordStudy(minutes: 50, completed: true)

        XCTAssertThrowsError(try ledger.buy(.outfit(.scrubs))) { error in
            XCTAssertEqual(error as? PetPurchaseError, .notEnoughPoints(missing: 30))
        }
        XCTAssertEqual(ledger.balance, 60, "a refused purchase costs nothing")

        try ledger.buy(.accessory(.roundGlasses))
        XCTAssertThrowsError(try ledger.buy(.accessory(.roundGlasses))) { error in
            XCTAssertEqual(error as? PetPurchaseError, .alreadyOwned)
        }
        XCTAssertThrowsError(try ledger.buy(.outfit(.none))) { error in
            XCTAssertEqual(error as? PetPurchaseError, .alreadyOwned, "free items are always owned")
        }
        XCTAssertEqual(ledger.balance, 0)
    }

    func testLedgerNeverSpendsMoreThanEarned() {
        let ledger = PetPointsLedger(earned: 10, spent: 99, purchased: [.outfit(.none), .accessory(.beanie)])
        XCTAssertEqual(ledger.balance, 0)
        XCTAssertEqual(ledger.purchased, [.accessory(.beanie)], "free items are never stored")
        XCTAssertEqual(PetPointsLedger(earned: -5).balance, 0)
    }

    func testProfileIsRestrictedToOwnedItems() throws {
        var ledger = PetPointsLedger()
        ledger.recordStudy(minutes: 200, completed: true)
        try ledger.buy(.accessory(.stethoscope))

        let profile = PetProfile(name: "Pip", breed: .labrador, outfit: .whiteCoat, accessories: [.stethoscope, .beanie])
        let restricted = profile.restricted(to: ledger)
        XCTAssertEqual(restricted.outfit, .none)
        XCTAssertEqual(restricted.accessories, [.stethoscope])
        XCTAssertEqual(restricted.name, "Pip")
    }
}

final class PetSaveTests: XCTestCase {
    func testSaveRoundTripsThroughAFile() throws {
        var ledger = PetPointsLedger()
        ledger.recordStudy(minutes: 120, completed: true)
        try ledger.buy(.outfit(.scrubs))
        let profile = PetProfile(
            name: "Nori", breed: .siamese, paletteOverrides: [.costumeBase: PetColor(hex: "#7A5CFF")!],
            outfit: .scrubs
        )
        let save = PetSave(profile: profile, ledger: ledger)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("pet.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertNil(try PetSave.load(from: url), "no save yet")
        try save.write(to: url)
        XCTAssertEqual(try PetSave.load(from: url), save)
    }

    func testDecodedSaveCannotWearUnboughtItems() throws {
        let json = """
        {"version": 1,
         "profile": {"name": "Rex", "breed": "beagle", "outfit": "whiteCoat", "accessories": ["graduationCap"]},
         "ledger": {"earned": 40, "spent": 30, "purchased": ["accessory.scarf", "accessory.fromTheFuture"]}}
        """
        let save = try PetSave.decode(Data(json.utf8))
        XCTAssertEqual(save.profile.outfit, .none)
        XCTAssertEqual(save.profile.accessories, [])
        XCTAssertEqual(save.ledger.purchased, [.accessory(.scarf)])
        XCTAssertEqual(save.ledger.balance, 10)
    }

    func testCorruptSaveThrows() {
        XCTAssertThrowsError(try PetSave.decode(Data("not json".utf8)))
    }
}
