import Foundation
import XCTest
@testable import TabbiKitCore

/// The Radiant effects file (`radiant.json`) and its costs.
final class RadiantArtTests: XCTestCase {
    func testTheFilesLoadAndEveryEffectEndsOnAPlacementWithoutZones() throws {
        let art = RadiantArt.shared
        XCTAssertEqual(art.loop, 24)
        XCTAssertEqual(art.upgradeMultiplier, 5)
        XCTAssertEqual(art.items.count, 8)
        XCTAssertEqual(RadiantMarkerArt.size, 9)
        for item in art.items {
            for effect in [item.bold, item.subtle] {
                XCTAssertFalse(effect.placements.isEmpty, effect.name)
                XCTAssertEqual(effect.placements.last?.zones, [], "\(effect.name) always fits")
            }
        }
        let costs = RadiantArt.costs
        XCTAssertEqual(costs.perTickBudget, 30)
        XCTAssertEqual(costs.combinedBudget, 42)
        XCTAssertGreaterThanOrEqual(costs.combinedBudget, costs.perTickBudget,
                                    "effects that take turns stay within the combined budget")
    }

    func testBrokenFilesAreRefused() {
        XCTAssertThrowsError(try RadiantArt.decode(Data(#"{"schema": "radiant.v2"}"#.utf8)))
        let base = #"{"schema": "radiant.v1", "loop": 2, "upgradeMultiplier": 5, "slotPriority": [], "marker": ["Y"], "shapes": {"dot": {"rows": ["Z"], "origin": [0, 0]}}, "items": [ITEM]}"#
        func file(_ item: String) -> Data { Data(base.replacingOccurrences(of: "ITEM", with: item).utf8) }
        let fine = #"{"item": "accessory.wizardHat", "bold": {"name": "A", "placements": [{"zones": [], "pieces": []}]}, "subtle": {"name": "B", "placements": [{"zones": [], "pieces": []}]}}"#
        XCTAssertNoThrow(try RadiantArt.decode(file(fine)))
        let lastHasZones = fine.replacingOccurrences(of: #""name": "A", "placements": [{"zones": []"#,
                                                     with: #""name": "A", "placements": [{"zones": ["chest"]"#)
        XCTAssertThrowsError(try RadiantArt.decode(file(lastHasZones)))
        let unknownZone = fine.replacingOccurrences(of: #"[{"zones": [], "pieces": []}]}, "subtle""#,
                                                    with: #"[{"zones": ["moon"], "pieces": []}, {"zones": [], "pieces": []}]}, "subtle""#)
        XCTAssertThrowsError(try RadiantArt.decode(file(unknownZone)))
        let shortTable = fine.replacingOccurrences(of: #""zones": [], "pieces": []}]}, "subtle""#,
                                                   with: #""zones": [], "pieces": [{"type": "blink", "roles": ["Y"], "which": [0], "color": "r", "ticks": [0]}, {"type": "glint", "roles": ["Y"], "color": "r", "positions": [0]}]}]}, "subtle""#)
        XCTAssertThrowsError(try RadiantArt.decode(file(shortTable)), "a per-tick table must cover the loop")
        let unknownItem = fine.replacingOccurrences(of: "accessory.wizardHat", with: "accessory.cape")
        XCTAssertThrowsError(try RadiantArt.decode(file(unknownItem)))
    }

    /// Every effect's name has a translation in every language.
    func testEffectNamesAreTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/TabbiKitCore/Localization/Localizable.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        for item in PetRadiant.eligibleItems {
            for intensity in [PetRadiantIntensity.bold, .subtle] {
                let name = try XCTUnwrap(PetRadiant.effectName(item, intensity))
                let localizations = try XCTUnwrap(strings[name]?["localizations"] as? [String: Any], name)
                XCTAssertEqual(localizations.count, 11, "\(name) in every language")
            }
        }
    }

    func testTheZonesSplitEveryFrame() {
        for breed in PetBreed.allCases {
            for animation in [PetAnimation.idle, .walk, .celebrate, .nap, .stretch] {
                for frame in PetComposer.clip(animation, for: breed).frames {
                    let geometry = RadiantGeometry(bare: frame.canvas)
                    for y in 0..<frame.canvas.height {
                        for x in 0..<frame.canvas.width {
                            let zone = geometry.zone(x, y)
                            // Only the head itself is in no zone.
                            if zone == nil {
                                XCTAssertTrue(y >= geometry.top && y <= geometry.chin && geometry.head.contains(x),
                                              "\(breed) \(animation) (\(x), \(y))")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Breeds that share a body shape draw the same Radiant pixels: the
    /// renderer reads only where the pet is, where its face and effects are,
    /// and where its items are, never fur colors. So the default (CI) run of
    /// `RadiantBudgetTests` and `RadiantCombinationTests` checks one breed per
    /// body shape, and `TABBI_RADIANT_EXHAUSTIVE=1` all 19.
    func testBreedsSharingABodyShapeLookTheSameToTheEffects() {
        func signature(_ canvas: PetCanvas) -> [UInt8] {
            canvas.pixels.map { role in
                guard let role else { return 0 }
                if RadiantGeometry.faceRoles.contains(role) { return 1 }
                if RadiantGeometry.effectRoles.contains(role) { return 2 }
                if [.blush, .outline].contains(role) { return 3 }
                // Fur in any color is the same to the effects; item roles are
                // the item's own and are compared exactly.
                return PetPalette.tintableFurRoles.contains(role) || role == .belly ? 4 : 10 + UInt8(PetPaletteRole.allCases.firstIndex(of: role)!)
            }
        }
        for breed in PetBreed.allCases {
            guard let twin = PetGallery.bodyShapeBreeds.first(where: { $0.bodyShape == breed.bodyShape }), twin != breed else { continue }
            XCTAssertEqual(breed.hasTail, twin.hasTail, "\(breed)")
            for item in [nil] + PetRadiant.eligibleItems {
                let (outfit, accessories) = RadiantAudit.wearing(item.map { [$0] } ?? [])
                for animation in PetAnimation.allCases {
                    let a = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories)
                    let b = PetComposer.clip(animation, for: twin, outfit: outfit, accessories: accessories)
                    for (fa, fb) in zip(a.frames, b.frames) {
                        let ta = fa.itemFrames.isEmpty ? [fa.canvas] : fa.itemFrames
                        let tb = fb.itemFrames.isEmpty ? [fb.canvas] : fb.itemFrames
                        XCTAssertEqual(ta.map(signature), tb.map(signature), "\(breed) as \(twin): \(item.map(\.id) ?? "bare") \(animation)")
                    }
                }
            }
        }
    }
}
