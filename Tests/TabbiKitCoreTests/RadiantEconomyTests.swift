import Foundation
import XCTest
@testable import TabbiKitCore

/// Radiant upgrades in the economy: the 5x rule, who may upgrade what, the
/// ledger and profile they change, the pinned goal, how they sync and how
/// Party carries them. `shared/fixtures/closet/radiant.json` pins all of it
/// for the Windows port (record with `TABBI_RECORD_FIXTURES=1`).
final class RadiantEconomyTests: XCTestCase {
    private let sorcerer = PetItem.accessory(.blindfoldedSorcerer)
    private let coat = PetItem.outfit(.whiteCoat)

    func testEightItemsAreEligibleAndCostFiveTimesTheirPrice() {
        XCTAssertEqual(PetRadiant.eligibleItems.map(\.id), [
            "accessory.blindfoldedSorcerer", "accessory.wizardHat", "accessory.tinyCrown", "outfit.dinosaurHoodie",
            "accessory.astronautHelmet", "accessory.graduationCap", "accessory.rainCloud", "outfit.whiteCoat",
        ])
        // Every item that can be Radiant is a Showpiece for now.
        let showpieceTop = 2_100
        for item in PetRadiant.eligibleItems {
            XCTAssertEqual(PetRadiant.price(of: item), item.cost * 5, "\(item)")
            XCTAssertGreaterThan(PetRadiant.price(of: item), showpieceTop, "an upgrade costs more than any Showpiece: \(item)")
            XCTAssertNotNil(PetRadiant.effectName(item, .bold))
            XCTAssertNotNil(PetRadiant.effectName(item, .subtle))
            XCTAssertNil(PetRadiant.effectName(item, .off))
        }
        XCTAssertFalse(PetRadiant.isEligible(.accessory(.beanie)))
        XCTAssertFalse(PetRadiant.isEligible(.accessory(.halo)))
    }

    func testUpgradeNeedsTheItemHappensOnceAndSpendsExactlyItsPrice() {
        var ledger = PetPointsLedger(earned: 20_000)
        XCTAssertThrowsError(try ledger.upgradeToRadiant(sorcerer)) { XCTAssertEqual($0 as? PetRadiantPurchaseError, .notOwned) }
        XCTAssertThrowsError(try ledger.upgradeToRadiant(.accessory(.beanie))) {
            XCTAssertEqual($0 as? PetRadiantPurchaseError, .notEligible)
        }
        try? ledger.buy(sorcerer)
        let before = ledger.balance
        XCTAssertTrue(ledger.canUpgrade(sorcerer))
        XCTAssertNoThrow(try ledger.upgradeToRadiant(sorcerer))
        XCTAssertEqual(before - ledger.balance, 9_750)
        XCTAssertTrue(ledger.isRadiant(sorcerer))
        XCTAssertThrowsError(try ledger.upgradeToRadiant(sorcerer)) {
            XCTAssertEqual($0 as? PetRadiantPurchaseError, .alreadyRadiant)
        }
        var poor = PetPointsLedger(earned: 2_000)
        try? poor.buy(sorcerer)
        XCTAssertThrowsError(try poor.upgradeToRadiant(sorcerer)) {
            XCTAssertEqual($0 as? PetRadiantPurchaseError, .notEnoughPoints(missing: 9_750 - 50))
        }
        XCTAssertEqual(poor.spent, 1_950, "a refused upgrade spends nothing")
    }

    func testTheClosetWearsTheUpgradeOnBoldAndFinishesItsGoal() throws {
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair),
                                             ledger: PetPointsLedger(earned: 11_000)))
        _ = closet.tap(sorcerer)
        _ = closet.tap(sorcerer) // take it off again
        XCTAssertEqual(closet.radiantState(of: sorcerer), .locked(missing: 9_750 - (11_000 - 1_950)))
        closet.pinRadiantGoal(sorcerer)
        XCTAssertEqual(closet.radiantGoalProgress, PetRadiantGoal(item: sorcerer, have: 9_050, price: 9_750))
        closet.receiveGift(points: 700)
        XCTAssertEqual(closet.radiantState(of: sorcerer), .affordable)
        XCTAssertTrue(try XCTUnwrap(closet.radiantGoalProgress).isReady)
        try closet.upgradeToRadiant(sorcerer)
        XCTAssertEqual(closet.radiantState(of: sorcerer), .radiant(.bold))
        XCTAssertTrue(closet.profile.isWearing(sorcerer))
        XCTAssertNil(closet.save.radiantGoal, "the goal is done")
        XCTAssertEqual(closet.profile.radiantLook, PetRadiantLook([sorcerer: .bold]))
        closet.setRadiance(.off, for: sorcerer)
        XCTAssertEqual(closet.radiantState(of: sorcerer), .radiant(.off))
        XCTAssertTrue(closet.profile.radiantLook.isEmpty, "Off draws the normal item")
        closet.pinRadiantGoal(sorcerer)
        XCTAssertNil(closet.save.radiantGoal, "an upgraded item cannot be pinned")
        closet.pinRadiantGoal(.accessory(.beanie))
        XCTAssertNil(closet.save.radiantGoal)
    }

    func testTheSaveKeepsUpgradesAndOlderSavesReadAsBefore() throws {
        var ledger = PetPointsLedger(earned: 12_000, purchased: [sorcerer, coat])
        try ledger.upgradeToRadiant(coat)
        var save = PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair, outfit: .whiteCoat), ledger: ledger)
        save.profile.setRadiance(.subtle, for: coat)
        save.radiantGoal = sorcerer
        let decoded = try PetSave.decode(save.encoded())
        XCTAssertEqual(decoded, save)
        XCTAssertEqual(decoded.profile.radiance(of: coat), .subtle)
        XCTAssertEqual(decoded.radiantGoal, sorcerer)
        // A save without upgrades writes no new keys, so it reads as before.
        let plain = try String(decoding: PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair)).encoded(),
                               as: UTF8.self)
        XCTAssertFalse(plain.contains("radian"))
        // A hand-edited save cannot claim an upgrade for an item it does not own.
        XCTAssertFalse(PetPointsLedger(earned: 50_000, radiant: [.accessory(.wizardHat)]).isRadiant(.accessory(.wizardHat)))
    }

    func testUpgradesSyncAsUnlocksThatOlderBuildsSkip() throws {
        var ledger = PetPointsLedger(earned: 12_000, purchased: [coat])
        try ledger.upgradeToRadiant(coat)
        let save = PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair), ledger: ledger)
        let document = SyncDocument.empty.recording(save, changedAt: nil, device: "mac-a")
        XCTAssertTrue(document.unlocks.contains("radiant.outfit.whiteCoat"))
        XCTAssertNil(PetItem(id: "radiant.outfit.whiteCoat"), "an older build reads no item from it")
        XCTAssertTrue(document.ledger.isRadiant(coat))
        let fresh = document.applied(to: PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair)))
        XCTAssertTrue(fresh.ledger.isRadiant(coat))
        XCTAssertEqual(fresh.profile.radiance(of: coat), .bold)
        // A goal pinned on this Mac survives a sync round while it can.
        var pinned = PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair),
                             ledger: PetPointsLedger(earned: 3_000, purchased: [.accessory(.wizardHat)]))
        pinned.radiantGoal = .accessory(.wizardHat)
        let synced = SyncDocument.empty.recording(pinned, changedAt: nil, device: "mac-a").applied(to: pinned)
        XCTAssertEqual(synced.radiantGoal, .accessory(.wizardHat))
    }

    func testPartyCarriesTheWornEffectsAndOlderAppsSkipThem() {
        let pet = PetProfile(name: "Pepper", breed: .blackCat, outfit: .whiteCoat, accessories: [.blindfoldedSorcerer],
                             radiance: [sorcerer: .bold, coat: .subtle, .accessory(.wizardHat): .bold])
        let update = PartyPetAppearance.update(for: pet)
        XCTAssertEqual(update.radiant, ["blindfolded-sorcerer:bold", "white-coat:subtle"], "only worn items")
        let profile = PartyProfile(code: "A", name: "A", petName: "Pepper", species: "cat", breed: "black-cat",
                                   costume: "white-coat", accessories: ["blindfolded-sorcerer"],
                                   radiant: ["white-coat:subtle", "blindfolded-sorcerer:bold", "wizard-hat:bold",
                                             "rain-cloud:sparkly", "nonsense"])
        let friend = PartyPetAppearance.pet(for: profile)
        XCTAssertEqual(friend.radiantLook, PetRadiantLook([sorcerer: .bold, coat: .subtle]))
        let older = PartyProfile(code: "A", name: "A", petName: "Pepper", species: "cat", breed: "black-cat",
                                 accessories: ["blindfolded-sorcerer"])
        XCTAssertTrue(PartyPetAppearance.pet(for: older).radiantLook.isEmpty, "an older app's profile shows the normal item")
        XCTAssertNil(update.olderCatalogFallback?.radiant, "a server that refuses the field gets the rest")
        XCTAssertEqual(update.olderCatalogFallback?.accessories, update.accessories)
    }

    func testRadiantFixtureMatches() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("shared/fixtures/closet/radiant.json")
        let value = RadiantEconomyFixture.make()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try PetGoldenFixtures.encode(value).write(to: url)
            return
        }
        XCTAssertEqual(try JSONDecoder().decode(RadiantEconomyFixture.self, from: Data(contentsOf: url)), value)
    }
}

/// `shared/fixtures/closet/radiant.json`.
struct RadiantEconomyFixture: Codable, Equatable {
    struct Item: Codable, Equatable {
        var item: String
        var price: Int
        var radiantPrice: Int
        var bold: String
        var subtle: String
        var wire: String
    }

    struct Step: Codable, Equatable {
        var op: String
        var item: String?
        var intensity: String?
        var points: Int?
        /// After the step: the outcome, the balance, the radiant state of the
        /// item, the save as JSON text.
        var result: String
        var balance: Int
        var state: String?
        var save: String
    }

    struct Wire: Codable, Equatable {
        var outfit: String
        var accessories: [String]
        var radiance: [String: String]
        var sent: [String]
    }

    struct Read: Codable, Equatable {
        var costume: String
        var accessories: [String]
        var radiant: [String]
        var look: [String: String]
    }

    var schema: String
    var version: Int
    var multiplier: Int
    var items: [Item]
    var steps: [Step]
    var unlocks: [String]
    var wire: [Wire]
    var reads: [Read]

    static func state(_ state: PetRadiantState) -> String {
        switch state {
        case .notEligible: "notEligible"
        case .needsItem: "needsItem"
        case .affordable: "affordable"
        case .locked(let missing): "locked:\(missing)"
        case .radiant(let intensity): "radiant:\(intensity.rawValue)"
        }
    }

    static func make() -> RadiantEconomyFixture {
        let items = PetRadiant.eligibleItems.map {
            Item(item: $0.id, price: $0.cost, radiantPrice: PetRadiant.price(of: $0),
                 bold: PetRadiant.effectName($0, .bold)!, subtle: PetRadiant.effectName($0, .subtle)!,
                 wire: PartyPetAppearance.wireItem($0))
        }
        var closet = PetCloset(save: PetSave(profile: PetProfile(name: "Mochi", breed: .britishShorthair),
                                             ledger: PetPointsLedger(earned: 3_000)))
        var steps: [Step] = []
        func record(_ op: String, _ item: PetItem?, intensity: PetRadiantIntensity? = nil, points: Int? = nil,
                    _ result: String) {
            let save = (try? closet.save.encoded()).map { String(decoding: $0, as: UTF8.self) } ?? ""
            steps.append(Step(op: op, item: item?.id, intensity: intensity?.rawValue, points: points, result: result,
                              balance: closet.balance, state: item.map { state(closet.radiantState(of: $0)) }, save: save))
        }
        func upgrade(_ item: PetItem) {
            do {
                try closet.upgradeToRadiant(item)
                record("upgrade", item, "upgraded")
            } catch {
                record("upgrade", item, "\(error)")
            }
        }
        let wizard = PetItem.accessory(.wizardHat), sorcerer = PetItem.accessory(.blindfoldedSorcerer)
        upgrade(wizard)
        _ = closet.tap(wizard)
        record("tap", wizard, "bought")
        upgrade(wizard)
        closet.pinRadiantGoal(wizard)
        record("pin", wizard, "pinned")
        closet.receiveGift(points: 4_900)
        record("gift", nil, points: 4_900, "credited")
        upgrade(wizard)
        upgrade(wizard)
        closet.setRadiance(.subtle, for: wizard)
        record("set", wizard, intensity: .subtle, "set")
        closet.setRadiance(.off, for: wizard)
        record("set", wizard, intensity: .off, "set")
        upgrade(.accessory(.beanie))
        upgrade(sorcerer)
        let unlocks = SyncDocument.empty.recording(closet.save, changedAt: nil, device: "mac").unlocks.sorted()
        let wears: [(PetOutfit, [PetAccessory], [PetItem: PetRadiantIntensity])] = [
            (.whiteCoat, [.blindfoldedSorcerer], [.outfit(.whiteCoat): .subtle, sorcerer: .bold]),
            (.dinosaurHoodie, [.graduationCap, .rainCloud],
             [.outfit(.dinosaurHoodie): .bold, .accessory(.graduationCap): .off, .accessory(.rainCloud): .bold]),
            (.none, [.tinyCrown], [wizard: .bold]),
        ]
        let wire = wears.map { outfit, accessories, radiance in
            let pet = PetProfile(name: "A", breed: .corgi, outfit: outfit, accessories: accessories, radiance: radiance)
            return Wire(outfit: outfit.rawValue, accessories: accessories.map(\.rawValue),
                        radiance: Dictionary(uniqueKeysWithValues: radiance.map { ($0.key.id, $0.value.rawValue) }),
                        sent: PartyPetAppearance.radiant(for: pet))
        }
        let reads = [
            ("white-coat", ["blindfolded-sorcerer"], ["blindfolded-sorcerer:bold", "white-coat:subtle"]),
            ("none", ["crown"], ["crown:subtle", "wizard-hat:bold", "crown:bold"]),
            ("dinosaur-hoodie", ["rain-cloud"], ["rain-cloud:glowing", "dinosaur-hoodie:off", "x", "halo:bold"]),
            ("none", ["graduation-cap"], ["graduation-cap:bold", "a:bold", "b:bold", "graduation-cap:subtle"]),
        ].map { costume, accessories, radiant in
            let profile = PartyProfile(code: "A", name: "A", petName: "P", species: "cat", breed: "tabby", costume: costume,
                                       accessories: accessories, radiant: radiant)
            let look = PartyPetAppearance.pet(for: profile).radiantLook.intensities
            return Read(costume: costume, accessories: accessories, radiant: radiant,
                        look: Dictionary(uniqueKeysWithValues: look.map { ($0.key.id, $0.value.rawValue) }))
        }
        return RadiantEconomyFixture(schema: "tabbi.closet.radiant", version: 1, multiplier: 5, items: items,
                                     steps: steps, unlocks: unlocks, wire: wire, reads: reads)
    }
}
