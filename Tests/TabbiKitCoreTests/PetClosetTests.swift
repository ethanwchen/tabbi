import XCTest
import TabbiKitCore

final class PetClosetTests: XCTestCase {
    private func closet(earned: Int = 0, purchased: Set<PetItem> = [], profile: PetProfile = .starter(.cat)) -> PetCloset {
        PetCloset(save: PetSave(profile: profile, ledger: PetPointsLedger(earned: earned, purchased: purchased)))
    }

    func testWardrobeListsEveryPaidItemCheapestFirst() {
        XCTAssertFalse(PetCloset.wardrobe.contains(.outfit(.none)))
        XCTAssertEqual(PetCloset.wardrobe.count, PetItem.allCases.count - 1)
        XCTAssertEqual(PetCloset.wardrobe.map(\.cost), PetCloset.wardrobe.map(\.cost).sorted())
    }

    func testItemStatesFollowOwnershipWearingAndBalance() {
        var closet = closet(earned: 100, purchased: [.accessory(.scarf)])
        XCTAssertEqual(closet.state(of: .accessory(.scarf)), .owned)
        closet.tap(.accessory(.scarf))
        XCTAssertEqual(closet.state(of: .accessory(.scarf)), .wearing)
        XCTAssertEqual(closet.state(of: .outfit(.scrubs)), .affordable)
        XCTAssertEqual(closet.state(of: .accessory(.stethoscope)), .locked(missing: 20))
    }

    func testTappingToggleBuysAndRefuses() {
        var closet = closet(earned: 100)
        XCTAssertEqual(closet.tap(.accessory(.beanie)), .boughtAndWore)
        XCTAssertEqual(closet.balance, 55)
        XCTAssertEqual(closet.profile.accessories, [.beanie])

        XCTAssertEqual(closet.tap(.accessory(.beanie)), .tookOff)
        XCTAssertEqual(closet.profile.accessories, [])
        XCTAssertEqual(closet.tap(.accessory(.beanie)), .wore)
        XCTAssertEqual(closet.balance, 55, "wearing an owned item is free")

        let before = closet.save
        XCTAssertEqual(closet.tap(.outfit(.whiteCoat)), .needsPoints(missing: 245))
        XCTAssertEqual(closet.save, before, "a refused tap changes nothing")
    }

    func testOutfitsTakeOffToNone() {
        var closet = closet(earned: 0, purchased: [.outfit(.scrubs)])
        closet.tap(.outfit(.scrubs))
        XCTAssertEqual(closet.profile.outfit, .scrubs)
        closet.tap(.outfit(.scrubs))
        XCTAssertEqual(closet.profile.outfit, .none)
    }

    func testANewHatReplacesTheOldOne() {
        var closet = closet(earned: 0, purchased: [.accessory(.beanie), .accessory(.surgicalCap)])
        closet.tap(.accessory(.beanie))
        closet.tap(.accessory(.surgicalCap))
        XCTAssertEqual(closet.profile.accessories, [.surgicalCap])
        XCTAssertEqual(closet.state(of: .accessory(.beanie)), .owned)
    }

    func testTryingOnDoesNotNeedOwnership() {
        let profile = PetCloset.wearing(.outfit(.whiteCoat), on: .starter(.dog))
        XCTAssertEqual(profile.outfit, .whiteCoat)
    }

    func testSwitchingSpeciesPicksABreedAndKeepsChosenNames() {
        var closet = closet()
        closet.setSpecies(.dog)
        XCTAssertEqual(closet.profile.species, .dog)
        XCTAssertEqual(closet.profile.name, PetProfile.starter(.dog).name, "a default name follows the species")

        closet.rename("Nori")
        closet.setSpecies(.cat)
        XCTAssertEqual(closet.profile.species, .cat)
        XCTAssertEqual(closet.profile.name, "Nori")
    }

    func testADefaultNameFollowsTheBreedAndSpeciesButAChosenOneStays() {
        var closet = closet()
        XCTAssertEqual(closet.profile.name, "British Shorthair", "the starter cat waits for the user to name it")
        closet.cycleBreed(by: 1)
        XCTAssertEqual(closet.profile.name, closet.profile.breed.displayName)
        closet.setSpecies(.dog)
        closet.setSpecies(.cat)
        XCTAssertEqual(closet.profile.name, closet.profile.breed.displayName, "back to a cat named by its breed")

        var saved = self.closet(profile: PetProfile(name: "Mochi", breed: .orangeTabby))
        saved.setSpecies(.dog)
        XCTAssertEqual(saved.profile.name, PetProfile.starter(.dog).name, "the old starter name is still a default")

        var named = self.closet()
        named.rename("Earl Grey")
        named.cycleBreed(by: 1)
        XCTAssertEqual(named.profile.name, "Earl Grey")
    }

    func testSwitchingSpeciesKeepsTheOutfit() {
        var closet = closet(purchased: [.outfit(.scrubs), .accessory(.scarf)])
        closet.tap(.outfit(.scrubs))
        closet.tap(.accessory(.scarf))
        closet.setSpecies(.dog)
        XCTAssertEqual(closet.profile.outfit, .scrubs)
        XCTAssertEqual(closet.profile.accessories, [.scarf])
    }

    func testCyclingBreedsWrapsWithinTheSpecies() {
        var closet = closet(profile: PetProfile(name: "Nori", breed: PetBreed.breeds(of: .cat)[0]))
        let cats = PetBreed.breeds(of: .cat)
        closet.cycleBreed(by: -1)
        XCTAssertEqual(closet.profile.breed, cats.last)
        closet.cycleBreed(by: 1)
        XCTAssertEqual(closet.profile.breed, cats.first)
        closet.cycleBreed(by: cats.count + 2)
        XCTAssertEqual(closet.profile.breed, cats[2])
    }

    func testFurTintIsReadBackAndFollowsBreedChanges() throws {
        var closet = closet()
        XCTAssertNil(closet.furTint)
        let pink = try XCTUnwrap(PetCloset.furSwatches.last)
        closet.tintFur(pink)
        XCTAssertEqual(closet.furTint, pink)

        closet.cycleBreed(by: 1)
        XCTAssertEqual(closet.furTint, pink)
        XCTAssertEqual(closet.profile.palette[.furShade],
                       closet.profile.breed.palette.furTint(pink)[.furShade],
                       "shading is re-derived from the new breed")

        closet.tintFur(nil)
        XCTAssertNil(closet.furTint)
        XCTAssertEqual(closet.profile.palette[.furBase], closet.profile.breed.palette[.furBase])
    }

    func testSwatchesAreDistinct() {
        XCTAssertEqual(Set(PetCloset.furSwatches).count, PetCloset.furSwatches.count)
        XCTAssertGreaterThanOrEqual(PetCloset.furSwatches.count, 6)
    }

    func testNextUnlockReportsTheGap() throws {
        var closet = closet(earned: 10)
        let next = try XCTUnwrap(closet.nextUnlock)
        XCTAssertEqual(next.item, .accessory(.scarf))
        XCTAssertEqual(next.missing, 20)
        closet.recordStudy(minutes: 25, completed: true)
        XCTAssertEqual(closet.nextUnlock?.missing, 0)
    }

    func testEditsSurviveASaveRoundTrip() throws {
        var closet = PetCloset.demo
        closet.rename("Dr. Mochi")
        closet.tintFur(PetCloset.furSwatches[3])
        closet.tap(.outfit(.scrubs))
        let restored = try PetSave.decode(closet.save.encoded())
        XCTAssertEqual(restored, closet.save)
    }

    func testDemoHasEveryTileState() {
        let states = PetCloset.wardrobe.map { PetCloset.demo.state(of: $0) }
        XCTAssertTrue(states.contains(.wearing))
        XCTAssertTrue(states.contains(.owned))
        XCTAssertTrue(states.contains(.affordable))
        XCTAssertTrue(states.contains { if case .locked = $0 { true } else { false } })
    }
}
