import Foundation
import XCTest
@testable import TabbiKitCore

/// How `RadiantLayout.resolve` lays out the Radiant items worn together.
final class RadiantResolverTests: XCTestCase {
    private let sorcerer = PetItem.accessory(.blindfoldedSorcerer)
    private let coat = PetItem.outfit(.whiteCoat)
    private let rain = PetItem.accessory(.rainCloud)
    private let crown = PetItem.accessory(.tinyCrown)

    private func layout(_ look: [PetItem: PetRadiantIntensity], costs: RadiantCosts = RadiantArt.costs) -> RadiantLayout? {
        let (outfit, accessories) = RadiantAudit.wearing(Array(look.keys))
        return RadiantLayout.resolve(PetRadiantLook(look), outfit: outfit, accessories: accessories, art: .shared,
                                     costs: costs)
    }

    func testNothingWornOrAllOffLaysOutNothing() {
        XCTAssertNil(layout([:]))
        XCTAssertNil(layout([sorcerer: .off]))
        // Upgraded but not worn.
        XCTAssertNil(RadiantLayout.resolve(PetRadiantLook([sorcerer: .bold]), outfit: .none, accessories: []))
    }

    func testAnEffectAloneGetsItsPreferredPlacement() throws {
        for item in PetRadiant.eligibleItems {
            for intensity in [PetRadiantIntensity.bold, .subtle] {
                let result = try XCTUnwrap(layout([item: intensity]))
                XCTAssertEqual(result.entries.map(\.placement), [0], "\(item) \(intensity)")
                XCTAssertEqual(result.cycles, 1)
            }
        }
    }

    /// The owner's example: with the White Coat on, the sorcerer's orb no
    /// longer crosses the chest; it circles at head height on the left,
    /// while the coat's heartbeat runs above the head.
    func testTheCoatHoldsTheChestSoTheOrbCirclesBesideTheHead() throws {
        let result = try XCTUnwrap(layout([sorcerer: .bold, coat: .bold]))
        XCTAssertEqual(result.entries.map(\.item), [sorcerer, coat], "the hat first, by slot priority")
        let art = RadiantArt.shared
        let orb = art.item(sorcerer)!.bold.placements[result.entries[0].placement]
        let beat = art.item(coat)!.bold.placements[result.entries[1].placement]
        XCTAssertEqual(orb.zones, [.leftOfHead])
        XCTAssertTrue(beat.zones.contains(.aboveHead))
        XCTAssertTrue(orb.zones.isDisjoint(with: beat.zones))
    }

    func testTheHatComesFirstAndTheOthersMoveAside() throws {
        let result = try XCTUnwrap(layout([crown: .bold, rain: .bold, coat: .bold]))
        XCTAssertEqual(result.entries.map(\.item), [crown, coat, rain])
        XCTAssertEqual(result.entries[0].placement, 0, "the crown keeps its halo above the head")
        let art = RadiantArt.shared
        var used = Set<RadiantZone>()
        for entry in result.entries {
            let zones = art.item(entry.item)!.effect(entry.intensity)!.placements[entry.placement].zones
            XCTAssertTrue(zones.isDisjoint(with: used), "\(entry.item) shares a zone")
            used.formUnion(zones)
        }
    }

    /// When the effects together would change more than the combined budget
    /// on some tick, they take turns: each plays in its own cycle and holds
    /// its still (tick 0) in the others'.
    func testEffectsOverTheCombinedBudgetTakeTurns() throws {
        let tight = RadiantCosts(perTickBudget: RadiantArt.costs.perTickBudget, combinedBudget: 10,
                                 table: RadiantArt.costs.table)
        let result = try XCTUnwrap(layout([sorcerer: .bold, coat: .bold], costs: tight))
        XCTAssertEqual(result.cycles, 2)
        XCTAssertEqual(result.entries.map(\.turn), [0, 1])
        XCTAssertEqual(result.loop, 48)
        XCTAssertEqual(result.ticks(at: 5, loop: 24), [5, 0])
        XCTAssertEqual(result.ticks(at: 29, loop: 24), [0, 5])
        XCTAssertEqual(result.ticks(at: 0, loop: 24), [0, 0], "the still shows both at rest")
        let together = try XCTUnwrap(layout([sorcerer: .bold, coat: .bold]))
        XCTAssertEqual(together.cycles, 1, "within the real budget they play together")
    }

    func testTheLayoutDoesNotDependOnTheBreed() throws {
        // Resolution takes no breed at all; the same look draws the same way
        // on every body shape (pinned per breed by radiant.json's digests).
        let a = try XCTUnwrap(layout([sorcerer: .subtle, coat: .bold, rain: .bold]))
        let b = try XCTUnwrap(layout([rain: .bold, coat: .bold, sorcerer: .subtle]))
        XCTAssertEqual(a, b)
    }
}
