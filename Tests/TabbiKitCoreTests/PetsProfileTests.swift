import XCTest
import TabbiKitCore

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

    func testNewUsersStartWithTheBritishShorthairAndNameItThemselves() {
        let starter = PetProfile.starter(.cat)
        XCTAssertEqual(starter.breed, .britishShorthair)
        XCTAssertEqual(starter.name, PetBreed.britishShorthair.displayName, "no made-up name until the user picks one")
        XCTAssertTrue(starter.hasDefaultName)
        XCTAssertEqual(starter.palette, PetBreed.britishShorthair.palette.withVisibleRim())
        XCTAssertEqual(PetProfile.starter(kit: nil), starter)
        XCTAssertFalse(PetProfile(name: "Earl Grey", breed: .britishShorthair).hasDefaultName)
    }

    func testAnExistingSavedPetKeepsItsBreedAndName() throws {
        let old = Data(#"{"name": "Mochi", "breed": "orangeTabby", "outfit": "none", "accessories": []}"#.utf8)
        let profile = try JSONDecoder().decode(PetProfile.self, from: old)
        XCTAssertEqual(profile.breed, .orangeTabby)
        XCTAssertEqual(profile.name, "Mochi")
    }

    func testTheStarterPetRendersEveryAnimationInEveryCostume() {
        let starter = PetProfile.starter(.cat)
        let palette = starter.palette
        let looks = [PetProfile(name: "", breed: starter.breed)]
            + PetOutfit.allCases.dropFirst().map { PetProfile(name: "", breed: starter.breed, outfit: $0) }
            + PetAccessory.allCases.map { PetProfile(name: "", breed: starter.breed, accessories: [$0]) }
        for look in looks {
            let clips = PetClipSet(profile: look)
            for animation in PetAnimation.allCases {
                // A peek starts or ends hidden inside the notch, so only
                // some of its frames show the pet.
                let shown = clips[animation].frames.filter { $0.canvas.opaqueBounds != nil }
                XCTAssertFalse(shown.isEmpty, "\(animation) \(look.outfit) \(look.accessories)")
                for frame in shown {
                    let colors = frame.canvas.colors(using: palette)
                    XCTAssertTrue(colors.contains(palette[.furBase]),
                                  "the silver fur shows: \(animation) \(look.outfit) \(look.accessories)")
                }
            }
        }
    }

    func testTheBritishShorthairTailIsRingedSittingAndWalking() {
        // Its dark-ringed tail is what tells it apart from a gray tabby at
        // notch size: some column must cross at least three dark bands
        // (two while walking, where the swaying tail runs diagonally).
        func ringCount(_ canvas: PetCanvas) -> Int {
            (0..<canvas.width).map { x in
                var runs = 0
                var inRing = false
                for y in 0..<canvas.height {
                    let isRing = canvas[x, y] == .furAccent
                    if isRing && !inRing { runs += 1 }
                    inRing = isRing
                }
                return runs
            }.max() ?? 0
        }
        let clips = PetClipSet(profile: PetProfile(name: "", breed: .britishShorthair))
        XCTAssertGreaterThanOrEqual(ringCount(PetComposer.sitting(.britishShorthair)), 3)
        for frame in clips[.walk].frames {
            XCTAssertGreaterThanOrEqual(ringCount(frame.canvas), 2)
        }
        XCTAssertLessThan(ringCount(PetComposer.sitting(.grayTabby)), 3, "plain cats keep their plain tail")
    }

    func testTheBritishShorthairHasTheSharedCatEyesInBlue() {
        let palette = PetBreed.britishShorthair.palette
        XCTAssertGreaterThan(Int(palette[.eye].blue), Int(palette[.eye].red) + 80, "a clear blue iris")
        XCTAssertGreaterThan(palette[.eyeLight].luminance, 0.9, "a white highlight")

        // The eye and highlight pixels land exactly where every plain cat's
        // do: a 2x3 eye with the highlight at its top left
        // over the pupil and a row of iris.
        func eyePixels(_ canvas: PetCanvas) -> [String] {
            (0..<canvas.height).flatMap { y in
                (0..<canvas.width).compactMap { x in
                    let role = canvas[x, y]
                    return role == .eye || role == .pupil || role == .eyeLight ? "\(x),\(y),\(role!.symbol)" : nil
                }
            }
        }
        let reference = eyePixels(PetComposer.sitting(.orangeTabby))
        XCTAssertEqual(reference.count, 12)
        XCTAssertEqual(eyePixels(PetComposer.sitting(.britishShorthair)), reference)
        let clips = PetClipSet(profile: PetProfile(name: "", breed: .britishShorthair))
        let tabby = PetClipSet(profile: PetProfile(name: "", breed: .orangeTabby))
        for animation in PetAnimation.allCases {
            for (frame, plain) in zip(clips[animation].frames, tabby[animation].frames) {
                XCTAssertEqual(eyePixels(frame.canvas), eyePixels(plain.canvas), "\(animation)")
            }
        }
    }

    func testTheBritishShorthairHasASoftWhiteSilverCoat() {
        let palette = PetBreed.britishShorthair.palette
        XCTAssertGreaterThan(palette[.furBase].luminance, 0.8, "a white-silver base")
        XCTAssertGreaterThan(palette[.furShade].luminance, 0.6, "ticking stays faint")
        XCTAssertLessThan(palette[.furAccent].luminance, palette[.furShade].luminance, "tail rings still show")
        XCTAssertNotEqual(palette[.furBase], PetBreed.whiteCat.palette[.furBase], "still not the white cat")
    }

    func testTheBritishShorthairSitsPlumpAndCenteredUnderItsHead() {
        // The first solid run across the belly, outline included: the
        // British Shorthair's is wider than a plain cat's but shares its
        // center, so the body sits square under the head and costumes.
        func belly(_ canvas: PetCanvas) -> ClosedRange<Int> {
            let y = 25
            let start = (0..<canvas.width).first { canvas[$0, y] != nil }!
            let end = (start..<canvas.width).first { canvas[$0, y] == nil }! - 1
            return start...end
        }
        let plump = belly(PetComposer.sitting(.britishShorthair))
        let plain = belly(PetComposer.sitting(.orangeTabby))
        XCTAssertGreaterThanOrEqual(plump.count, plain.count + 2)
        XCTAssertEqual(plump.lowerBound + plump.upperBound, plain.lowerBound + plain.upperBound)
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

    func testRecoloringFurDarkAddsTheLightRim() {
        var profile = PetProfile(name: "Pip", breed: .whiteCat)
        profile.setColor(PetColor(hex: "#151217")!, for: .furBase)
        XCTAssertEqual(profile.palette[.outline], profile.palette.rim)
    }

    func testFurTintKeepsEachBreedsLightAndDarkMarkings() {
        let lilac = PetColor(hex: "#B4A2C8")!
        for breed in PetBreed.allCases {
            var profile = PetProfile(name: "Pip", breed: breed)
            profile.tintFur(lilac)
            let original = breed.palette, tinted = profile.palette
            XCTAssertEqual(tinted[.furBase], lilac, "\(breed)")
            for role in PetPalette.tintableFurRoles where role != .furBase {
                // A lighter golden chest stays lighter; darker tabby stripes stay darker.
                let wasLighter = original[role].luminance > original[.furBase].luminance
                let isLighter = tinted[role].luminance > tinted[.furBase].luminance
                if original[role] != original[.furBase] {
                    XCTAssertEqual(wasLighter, isLighter, "\(breed) \(role)")
                }
                // The picked hue carries to every fur role: purple stays blue-and-red heavy.
                XCTAssertGreaterThan(tinted[role].blue, tinted[role].green, "\(breed) \(role)")
            }
            // Markings outside the fur roles keep their breed colors.
            XCTAssertEqual(tinted[.belly], original[.belly], "\(breed)")
            XCTAssertEqual(tinted[.furSpot], original[.furSpot], "\(breed)")
        }
    }

    func testFurTintCanBeClearedWithoutLosingOtherColors() {
        let pink = PetColor(hex: "#FF77AA")!
        var profile = PetProfile(name: "Pip", breed: .goldenRetriever)
        profile.setColor(pink, for: .costumeBase)
        profile.tintFur(PetColor(hex: "#1C1719")!)
        XCTAssertEqual(profile.palette[.outline], profile.palette.rim, "black fur still gets the light rim")

        profile.tintFur(nil)
        XCTAssertEqual(profile.paletteOverrides, [.costumeBase: pink])
        XCTAssertEqual(profile.palette[.furAccent], PetBreed.goldenRetriever.palette[.furAccent])
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
         "paletteOverrides": {"furBase": "#112233", "sparkle": "#FFFFFF", "eye": "#12345", "nose": "tan"}}
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
        XCTAssertEqual(items.map(\.cost), items.map(\.cost).sorted())
        XCTAssertEqual(Set(items.filter(\.isFree)),
                       [.outfit(.none), .accessory(.scarf), .accessory(.partyHat), .accessory(.bowTie)],
                       "no outfit plus one free starter per playful theme")
        let prices = items.filter { !$0.isFree }.map(\.cost)
        XCTAssertEqual(Set(prices).count, prices.count, "every paid item has its own price")
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
        XCTAssertEqual(ledger.nextUnlock, .accessory(.beanie))
        XCTAssertEqual(ledger.recordStudy(minutes: 25, completed: true), 35)
        XCTAssertTrue(ledger.canBuy(.accessory(.beanie)))
        try ledger.buy(.accessory(.beanie))
        XCTAssertEqual(ledger.balance, 5)
        XCTAssertEqual(ledger.earned, 35)
        XCTAssertEqual(ledger.nextUnlock, .accessory(.roundGlasses))
    }

    func testPurchasesAreRefusedWithAReason() throws {
        var ledger = PetPointsLedger()
        ledger.recordStudy(minutes: 50, completed: true)

        XCTAssertThrowsError(try ledger.buy(.outfit(.scrubs))) { error in
            XCTAssertEqual(error as? PetPurchaseError, .notEnoughPoints(missing: 40))
        }
        XCTAssertEqual(ledger.balance, 60, "a refused purchase costs nothing")

        try ledger.buy(.accessory(.ninjaHeadband))
        XCTAssertThrowsError(try ledger.buy(.accessory(.ninjaHeadband))) { error in
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

    func testOldSaveGetsTheScarfItBoughtRefundedOnce() throws {
        let old = Data(#"{"earned": 100, "spent": 60, "purchased": ["accessory.scarf", "accessory.beanie"]}"#.utf8)
        let ledger = try JSONDecoder().decode(PetPointsLedger.self, from: old)
        XCTAssertEqual(ledger.balance, 70)
        XCTAssertEqual(ledger.purchased, [.accessory(.beanie)])

        let reloaded = try JSONDecoder().decode(PetPointsLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(reloaded.balance, 70, "the refund applies once")
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
         "ledger": {"earned": 40, "spent": 30, "purchased": ["accessory.beanie", "accessory.fromTheFuture"]}}
        """
        let save = try PetSave.decode(Data(json.utf8))
        XCTAssertEqual(save.profile.outfit, .none)
        XCTAssertEqual(save.profile.accessories, [])
        XCTAssertEqual(save.ledger.purchased, [.accessory(.beanie)])
        XCTAssertEqual(save.ledger.balance, 10)
    }

    func testCorruptSaveThrows() {
        XCTAssertThrowsError(try PetSave.decode(Data("not json".utf8)))
    }
}
