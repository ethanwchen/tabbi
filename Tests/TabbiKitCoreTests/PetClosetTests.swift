import XCTest
import TabbiKitCore

final class PetClosetTests: XCTestCase {
    private func closet(earned: Int = 0, purchased: Set<PetItem> = [], profile: PetProfile = .starter(.cat)) -> PetCloset {
        PetCloset(save: PetSave(profile: profile, ledger: PetPointsLedger(earned: earned, purchased: purchased)))
    }

    func testWardrobeListsEveryItemCheapestFirst() {
        XCTAssertFalse(PetCloset.wardrobe.contains(.outfit(.none)))
        XCTAssertEqual(PetCloset.wardrobe.count, PetItem.shopItems.count - 1)
        XCTAssertEqual(PetCloset.wardrobe.map(\.cost), PetCloset.wardrobe.map(\.cost).sorted())
    }

    func testItemStatesFollowOwnershipWearingAndBalance() {
        var closet = closet(earned: 250, purchased: [.accessory(.beanie)])
        XCTAssertEqual(closet.state(of: .accessory(.beanie)), .owned)
        closet.tap(.accessory(.beanie))
        XCTAssertEqual(closet.state(of: .accessory(.beanie)), .wearing)
        XCTAssertEqual(closet.state(of: .outfit(.scrubs)), .affordable)
        XCTAssertEqual(closet.state(of: .accessory(.stethoscope)), .locked(missing: 20))
    }

    func testTappingToggleBuysAndRefuses() {
        var closet = closet(earned: 100)
        XCTAssertEqual(closet.tap(.accessory(.beanie)), .boughtAndWore)
        XCTAssertEqual(closet.balance, 65)
        XCTAssertEqual(closet.profile.accessories, [.beanie])

        XCTAssertEqual(closet.tap(.accessory(.beanie)), .tookOff)
        XCTAssertEqual(closet.profile.accessories, [])
        XCTAssertEqual(closet.tap(.accessory(.beanie)), .wore)
        XCTAssertEqual(closet.balance, 65, "wearing an owned item is free")

        let before = closet.save
        XCTAssertEqual(closet.tap(.outfit(.whiteCoat)), .needsPoints(missing: 1185))
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
                       closet.profile.breed.furTint(pink)[.furShade],
                       "shading follows the new breed's tones")

        closet.tintFur(nil)
        XCTAssertNil(closet.furTint)
        XCTAssertEqual(closet.profile.palette[.furBase], closet.profile.breed.palette[.furBase])
    }

    func testRetiredSwatchesMoveToTheirReplacements() throws {
        // Every swatch earlier builds offered still lands on a current one.
        let earlier = ["#F2A65A", "#C98B5B", "#8A5A3C", "#3B3434", "#9AA3AD", "#F4ECE0", "#E58FA8", "#8FB8E8"]
        for hex in earlier {
            var profile = PetProfile(name: "Pip", breed: .orangeTabby)
            profile.tintFur(try XCTUnwrap(PetColor(hex: hex)))
            let closet = PetCloset(save: PetSave(profile: profile))
            XCTAssertTrue(PetCloset.furSwatches.contains(try XCTUnwrap(closet.furTint)), hex)
        }
    }

    func testSwatchesAreDistinct() {
        XCTAssertEqual(Set(PetCloset.furSwatches).count, PetCloset.furSwatches.count)
        XCTAssertGreaterThanOrEqual(PetCloset.furSwatches.count, 6)
        let names = PetCloset.furSwatches.compactMap(PetCloset.name(ofSwatch:))
        XCTAssertEqual(Set(names).count, PetCloset.furSwatches.count, "every swatch has its own name")
        XCTAssertNil(PetCloset.name(ofSwatch: PetColor(hex: "#123456")!))
    }

    func testNextUnlockReportsTheGap() throws {
        var closet = closet(earned: 10)
        let next = try XCTUnwrap(closet.nextUnlock)
        XCTAssertEqual(next.item, .accessory(.beanie))
        XCTAssertEqual(next.missing, 25)
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

    func testFreeStartersAreOwnedFromTheStart() {
        var closet = closet()
        for item in PetCloset.wardrobe where item.isFree {
            XCTAssertEqual(closet.state(of: item), .owned, item.id)
        }
        XCTAssertEqual(closet.tap(.accessory(.partyHat)), .wore)
        XCTAssertEqual(closet.profile.accessories, [.partyHat])
        XCTAssertEqual(closet.balance, 0)
    }

    func testShelvesGroupEveryItemOnceByThemeCheapestFirst() {
        XCTAssertEqual(PetCloset.shelves.map(\.theme), PetItemTheme.allCases)
        let shelved = PetCloset.shelves.flatMap(\.items)
        XCTAssertEqual(Set(shelved), Set(PetCloset.wardrobe))
        XCTAssertEqual(shelved.count, PetCloset.wardrobe.count)
        for shelf in PetCloset.shelves {
            XCTAssertTrue(shelf.items.allSatisfy { $0.theme == shelf.theme })
            XCTAssertEqual(shelf.items.map(\.cost), shelf.items.map(\.cost).sorted(), shelf.theme.displayName)
            XCTAssertGreaterThanOrEqual(shelf.items.count, 3, "\(shelf.theme.displayName) is too thin to be a shelf")
        }
        XCTAssertEqual(PetItem.outfit(.whiteCoat).theme, .study)
        XCTAssertEqual(PetItem.accessory(.blindfoldedSorcerer).theme, .fantasy)
        XCTAssertEqual(PetItem.outfit(.dinosaurHoodie).theme, .silly)
    }

    func testCozySeasonalAndSillyShelvesStartWithAFreeItem() {
        let starters = PetCloset.shelves.compactMap { shelf in shelf.items.first.flatMap { $0.isFree ? shelf.theme : nil } }
        XCTAssertEqual(starters, [.cozy, .seasonal, .silly])
    }

    func testNewBadgeShowsOnFreshItemsUntilOwned() throws {
        XCTAssertFalse(PetItem.accessory(.scarf).isNew, "the med set shipped first")
        XCTAssertFalse(PetItem.outfit(.scrubs).isNew)
        XCTAssertFalse(PetItem.accessory(.wizardHat).isNew, "the second batch is no longer the latest")
        XCTAssertTrue(PetItem.accessory(.angelWings).isNew)
        XCTAssertFalse(PetItem.accessory(.goldenLaurel).isNew, "limited items have their own badge")

        var closet = closet(earned: 2000)
        XCTAssertTrue(closet.isNew(.accessory(.angelWings)))
        XCTAssertEqual(closet.tap(.accessory(.angelWings)), .boughtAndWore)
        XCTAssertFalse(closet.isNew(.accessory(.angelWings)), "the badge goes once the item is unlocked")
    }
}
