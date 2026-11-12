import XCTest
import TabbiKitCore

/// A clip built with a ceiling (the closed notch) draws nothing above it
/// and changes nothing that already fits; without one, the frames are the
/// full art the Closet shows (pinned by the golden fixtures).
final class PetCeilingTests: XCTestCase {
    private func top(_ clip: PetClip) -> Int {
        clip.frames.flatMap { [$0.canvas] + $0.itemFrames }.compactMap { $0.opaqueBounds?.minY }.min() ?? .max
    }

    func testAFrameThatFitsIsUntouched() {
        let full = PetComposer.clip(.idle, for: .orangeTabby)
        XCTAssertGreaterThanOrEqual(top(full), 2)
        XCTAssertEqual(PetComposer.clip(.idle, for: .orangeTabby, ceiling: 2), full)
    }

    func testATallHatHopsLowerUnderTheCeiling() {
        let full = PetComposer.clip(.celebrate, for: .corgi, accessories: [.wizardHat])
        let fitted = PetComposer.clip(.celebrate, for: .corgi, accessories: [.wizardHat], ceiling: 2)
        XCTAssertLessThan(top(full), 2, "the hat's tip leaves the top rows mid-hop")
        XCTAssertGreaterThanOrEqual(top(fitted), 2)
        // The pet still lands on the floor: only the airborne frames move.
        XCTAssertEqual(fitted.frames.first, full.frames.first)
        XCTAssertEqual(fitted.frames.map(\.duration), full.frames.map(\.duration))
    }

    func testPetalsAndSparklesDriftInFromAboveTheCeiling() {
        for accessory in [PetAccessory.cherryPetals, .sparkleTrail] {
            // The rain cloud moves down instead (`testTheRainCloudShowsUnderTheCeiling`).
            let full = PetComposer.clip(.idle, for: .orangeTabby, accessories: [accessory])
            let fitted = PetComposer.clip(.idle, for: .orangeTabby, accessories: [accessory], ceiling: 2)
            XCTAssertLessThan(top(full), 2, "\(accessory) starts at the frame's top")
            XCTAssertGreaterThanOrEqual(top(fitted), 2, "\(accessory)")
            let shown = fitted.frames.flatMap { [$0.canvas] + $0.itemFrames }.map { $0.pixels.compactMap { $0 }.count }
            let bare = PetComposer.clip(.idle, for: .orangeTabby).frames[0].canvas.pixels.compactMap { $0 }.count
            XCTAssertTrue(shown.contains { $0 > bare }, "\(accessory) still shows lower down")
        }
    }

    /// The Tiny Rain Cloud hangs at the frame's top. Under the ceiling it
    /// moves down as a whole (`lowersUnderCeiling`), so the closed notch
    /// shows the cloud itself and not just its drops, sitting, walking and
    /// through the whole drizzle. The Sphynx's and the French Bulldog's tall
    /// ears reach where it would hang, so there it is left out sitting, as
    /// any particle that would touch the pet.
    func testTheRainCloudShowsUnderTheCeiling() {
        for breed in PetGallery.bodyShapeBreeds {
            for animation in [PetAnimation.idle, .walk, .sleep] {
                // Where tall ears (the Sphynx, French Bulldog and Corgi
                // sitting) or the dachshund's raised head lying down reach
                // the spot, the lowered cloud would touch the pet, so it is
                // left out there like any particle.
                let blocked = ([PetBodyShape.sphynxCat, .batEaredDog, .pointyEaredDog].contains(breed.bodyShape)
                               && animation == .idle) || (breed.bodyShape == .longDog && animation == .sleep)
                let full = PetComposer.clip(animation, for: breed, accessories: [.rainCloud])
                let fitted = PetComposer.clip(animation, for: breed, accessories: [.rainCloud], ceiling: 2)
                XCTAssertGreaterThanOrEqual(top(fitted), 2, "\(breed) \(animation)")
                for (whole, frame) in zip(full.frames, fitted.frames) {
                    let ticks = frame.itemFrames.isEmpty ? [frame.canvas] : frame.itemFrames
                    let wholeTicks = whole.itemFrames.isEmpty ? [whole.canvas] : whole.itemFrames
                    for (shown, art) in zip(ticks, wholeTicks) {
                        XCTAssertGreaterThanOrEqual(art.pixels.filter { $0 == .coat }.count, 10,
                                                    "the Closet shows the cloud: \(breed) \(animation)")
                        guard !blocked else { continue }
                        XCTAssertGreaterThanOrEqual(shown.pixels.filter { $0 == .coat }.count, 10,
                                                    "the notch shows the cloud: \(breed) \(animation)")
                    }
                }
            }
        }
    }

    func testTheCacheHandsBackTheSameClipsPerLookAndCeiling() {
        var profile = PetProfile.starter(.dog)
        profile.rename("Biscuit")
        let fitted = PetClipSet.cached(profile: profile, ceiling: 2)
        XCTAssertEqual(fitted, PetClipSet(profile: profile, ceiling: 2))
        XCTAssertEqual(PetClipSet.cached(profile: profile, ceiling: 2), fitted)
        XCTAssertEqual(PetClipSet.cached(profile: profile), PetClipSet(profile: profile), "the ceiling is part of the key")
        // A rename changes nothing drawn, so it reuses the clips.
        profile.rename("Waffles")
        XCTAssertEqual(PetClipSet.cached(profile: profile, ceiling: 2), fitted)
    }
}
