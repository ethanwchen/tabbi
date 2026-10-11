import XCTest
import TabbiKitCore

/// The sleep "z" drifts up and to the right from the head, getting smaller
/// and then fading as it rises: one glyph at a time, always whole, so the
/// closed notch (which shows the top of the frame) never cuts one off.
final class PetSleepDriftTests: XCTestCase {
    private static let animations: [PetAnimation] = [.sleep, .nap]

    /// Where the z is in each frame, for a pet with no costume: every
    /// effect pixel (a costume adds glints and sparkles of its own).
    private func zPixels(in canvas: PetCanvas) -> [(x: Int, y: Int, faint: Bool)] {
        var pixels: [(x: Int, y: Int, faint: Bool)] = []
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas[x, y] == .effect || canvas[x, y] == .effectFaint {
                pixels.append((x, y, canvas[x, y] == .effectFaint))
            }
        }
        return pixels
    }

    private func center(_ pixels: [(x: Int, y: Int, faint: Bool)]) -> (x: Double, y: Double) {
        (Double(pixels.map(\.x).reduce(0, +)) / Double(pixels.count),
         Double(pixels.map(\.y).reduce(0, +)) / Double(pixels.count))
    }

    func testTheZShrinksAndFadesAsItDriftsUpAndRight() {
        for breed in PetBreed.allCases {
            for animation in Self.animations {
                let label = "\(breed) \(animation)"
                let clip = PetComposer.clip(animation, for: breed)
                XCTAssertEqual(clip.frames.count, 4, label)
                let zs = clip.frames.map { zPixels(in: $0.canvas) }
                // Every pixel of each glyph shows: none is cut off by the
                // frame's edge or hidden behind the pet.
                XCTAssertEqual(zs.map(\.count), [11, 8, 8, 0], "\(label): large, small, faded, then gone")
                XCTAssertEqual(zs.map { $0.filter(\.faint).count }, [0, 0, 8, 0], "\(label): only the last one fades")
                let centers = zs.prefix(3).map(center)
                for (lower, higher) in zip(centers, centers.dropFirst()) {
                    XCTAssertLessThan(higher.y, lower.y, "\(label) rises")
                    XCTAssertGreaterThan(higher.x, lower.x, "\(label) drifts right")
                    // A gentle angle: it rises at least as much as it drifts.
                    XCTAssertGreaterThanOrEqual(lower.y - higher.y, higher.x - lower.x, label)
                }
            }
        }
    }

    func testCostumesNeverHideTheZ() {
        // Every pixel of a bare pet's z is still a z pixel in the same frame
        // with each outfit, each accessory, and the top bond look.
        for animation in Self.animations {
            let cat = PetBreed.orangeTabby
            var looks = PetOutfit.allCases.map { ("\($0)", PetComposer.clip(animation, for: cat, outfit: $0)) }
            looks += PetAccessory.allCases.map { ("\($0)", PetComposer.clip(animation, for: cat, accessories: [$0])) }
            looks.append(("top bond", PetComposer.clip(animation, for: cat, bond: PetBondLook(level: 10))))
            let expected = PetComposer.clip(animation, for: cat).frames.map { zPixels(in: $0.canvas) }
            for (name, clip) in looks {
                for (frame, pixels) in zip(clip.frames, expected) {
                    for pixel in pixels {
                        XCTAssertEqual(frame.canvas[pixel.x, pixel.y], pixel.faint ? .effectFaint : .effect,
                                       "\(name) \(animation) at \(pixel.x),\(pixel.y)")
                    }
                }
            }
        }
    }

    func testTheSleepZKeepsClearOfTheFramesTopRows() {
        // The closed notch draws nothing above a ceiling row a few rows
        // down (`NotchPreviewLayout.petCeilingRow`, checked in the app
        // tests); the z's own art stays below row 5 anyway, so the ceiling
        // never has to move it and it reads the same in the Closet.
        for breed in PetBreed.allCases {
            for frame in PetComposer.clip(.sleep, for: breed).frames {
                XCTAssertTrue(zPixels(in: frame.canvas).allSatisfy { $0.y >= 5 }, "\(breed)")
            }
        }
    }

    func testAStillPetHoldsABrightZ() {
        for animation in Self.animations {
            let still = zPixels(in: PetComposer.clip(animation, for: .corgi).stillFrame.canvas)
            XCTAssertEqual(still.count, 8, "\(animation)")
            XCTAssertFalse(still.contains(where: \.faint), "\(animation): Reduce Motion freezes a z mid-drift, not a fading one")
        }
    }
}
