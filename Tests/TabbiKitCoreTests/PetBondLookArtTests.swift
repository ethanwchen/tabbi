import Foundation
import TabbiKitCore
import XCTest

/// The bond's visible growth (`PetBondLook`) is drawn as breed-agnostic
/// overlays: a collar that upgrades and a soft sparkle in the air. These
/// pin that it shows on every breed, never covers the pet, steps aside for
/// a neck item, and stays out of the saved profile.
final class PetBondLookArtTests: XCTestCase {
    private func opaque(_ canvas: PetCanvas) -> Set<Int> {
        Set(canvas.pixels.indices.filter { canvas.pixels[$0] != nil })
    }

    func testNoBondLooksExactlyLikeTheBarePet() {
        for breed in PetBreed.allCases {
            XCTAssertEqual(PetComposer.sitting(breed, bond: .none), PetComposer.sitting(breed), "\(breed)")
            XCTAssertEqual(PetComposer.sitting(breed, bond: PetBondLook(level: 1)), PetComposer.sitting(breed))
        }
    }

    func testEveryCollarShowsAndDiffersOnEveryBreed() {
        let levels = PetCollar.allCases.map(\.unlockLevel)
        for breed in PetBreed.allCases {
            let frames = levels.map { PetComposer.sitting(breed, bond: PetBondLook(level: $0)) }
            XCTAssertEqual(Set(frames).count, levels.count, "\(breed): each collar upgrade changes the picture")
            let bare = opaque(frames[0])
            for frame in frames.dropFirst() {
                // A collar is drawn on the pet, so the silhouette stays the same.
                XCTAssertEqual(opaque(frame), bare, "\(breed)")
            }
        }
    }

    func testANeckItemIsWornInsteadOfTheCollar() {
        let gold = PetBondLook(level: PetCollar.gold.unlockLevel)
        for accessory in PetAccessory.allCases where accessory.slot == .neck {
            XCTAssertEqual(PetComposer.sitting(.calico, accessories: [accessory], bond: gold),
                           PetComposer.sitting(.calico, accessories: [accessory]), "\(accessory)")
        }
        // Other slots keep the collar.
        XCTAssertNotEqual(PetComposer.sitting(.calico, accessories: [.partyHat], bond: gold),
                          PetComposer.sitting(.calico, accessories: [.partyHat]))
    }

    func testTheSparkleOnlyFillsFreeAirInEveryClip() {
        let collar = PetBondLook(level: PetBondLook.sparkleLevel - 1)
        let sparkle = PetBondLook(level: PetBondLook.sparkleLevel)
        XCTAssertEqual(collar.collar, sparkle.collar, "the sparkle level adds only the sparkle")
        for breed in PetBreed.allCases {
            for animation in PetAnimation.allCases {
                let plain = PetComposer.clip(animation, for: breed, bond: collar)
                let sparkling = PetComposer.clip(animation, for: breed, bond: sparkle)
                XCTAssertEqual(plain.frames.count, sparkling.frames.count)
                for (before, after) in zip(plain.frames, sparkling.frames) {
                    for canvas in [after.canvas] + after.itemFrames {
                        for index in before.canvas.pixels.indices where before.canvas.pixels[index] != nil {
                            XCTAssertEqual(canvas.pixels[index], before.canvas.pixels[index],
                                           "\(breed) \(animation): the sparkle never covers the pet")
                        }
                    }
                }
            }
        }
        // It twinkles: the sitting idle loops through more than one picture.
        let idle = PetComposer.clip(.idle, for: .orangeTabby, bond: sparkle).frames[0]
        XCTAssertGreaterThan(Set(idle.itemFrames).count, 1)
    }

    func testTheProfileShowsItsBondButNeverSavesIt() throws {
        var profile = PetProfile(name: "Mochi", breed: .orangeTabby)
        profile.bondLook = PetBondLook(level: 8)
        XCTAssertEqual(profile.sittingCanvas(), PetComposer.sitting(.orangeTabby, bond: PetBondLook(level: 8)))
        XCTAssertEqual(PetClipSet(profile: profile), PetClipSet(breed: .orangeTabby, bond: PetBondLook(level: 8)))

        let data = try JSONEncoder().encode(profile)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("bond"))
        let decoded = try JSONDecoder().decode(PetProfile.self, from: data)
        XCTAssertEqual(decoded.bondLook, .none)
    }

    func testTheBondSheetShowsEveryBreedInEveryLookAndStance() {
        let sheet = PetGallery.bondLooks()
        XCTAssertEqual(sheet.rows.count, PetBreed.allCases.count)
        XCTAssertTrue(sheet.rows.allSatisfy { $0.count == PetGallery.bondLevels.count + 4 })
        XCTAssertEqual(sheet.rows[0][0].canvas, PetComposer.sitting(PetBreed.allCases[0],
                                                                     bond: PetBondLook(level: PetGallery.bondLevels[0])))
        XCTAssertNotNil(sheet.render(scale: 1))
    }
}
