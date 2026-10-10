import XCTest
import TabbiKitCore

/// Every costume item on every breed through every frame of every animation.
/// The checks compare each dressed frame with the same frame undressed, so
/// they hold for any breed or item added later without new expectations.
final class PetCostumeFitTests: XCTestCase {
    /// Each item worn on its own, plus the bare outfit `none` left out.
    private static let looks: [(name: String, outfit: PetOutfit, accessories: [PetAccessory])] =
        PetOutfit.allCases.filter { $0 != .none }.map { ($0.rawValue, $0, []) }
            + PetAccessory.allCases.map { ($0.rawValue, .none, [$0]) }

    /// Where a dressed frame differs from the plain one, minus outline
    /// pixels, which only follow the silhouette.
    private func costumePixels(_ dressed: PetCanvas, over plain: PetCanvas) -> [PetPoint] {
        var points: [PetPoint] = []
        for y in 0..<dressed.height {
            for x in 0..<dressed.width {
                if let role = dressed[x, y], role != .outline, role != plain[x, y] {
                    points.append(PetPoint(x: x, y: y))
                }
            }
        }
        return points
    }

    private func bounds(_ points: [PetPoint]) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        guard !points.isEmpty else { return nil }
        return (points.map(\.x).min()!, points.map(\.y).min()!, points.map(\.x).max()!, points.map(\.y).max()!)
    }

    /// Peek frames slide a hanging pet in from beyond the top edge, so
    /// clipping there is the animation itself.
    private func isSliding(_ animation: PetAnimation) -> Bool {
        animation == .peekIn || animation == .peekOut
    }

    /// A held mug or a chin tucked in for a nap can hide a neck item.
    private func hidesTheNeck(_ animation: PetAnimation, _ accessories: [PetAccessory]) -> Bool {
        (animation == .coffee || animation == .nap) && accessories.contains { $0.slot == .neck }
    }

    /// A curled-up pet lies on the bottom row, and so does what it wears
    /// on its neck and body.
    private func liesOnTheFloor(_ animation: PetAnimation, _ outfit: PetOutfit, _ accessories: [PetAccessory]) -> Bool {
        animation == .nap && (outfit != .none || accessories.contains { $0.slot == .neck })
    }

    /// A raised mug or a waving paw can pass in front of the head; in a
    /// frame where it hides part of the item or of the nose, what shows
    /// can't say where the item sits.
    private func isCovered(_ animation: PetAnimation, item: Int, nose: Int, sitting: (item: Int, nose: Int)) -> Bool {
        (animation == .coffee || animation == .wave) && (item < sitting.item || nose < sitting.nose)
    }

    func testEveryItemShowsAndStaysInsideTheFrameInEveryAnimation() {
        let edge = PetComposer.frameSize - 1
        for breed in PetBreed.allCases {
            for animation in PetAnimation.allCases where !isSliding(animation) {
                let plain = PetComposer.clip(animation, for: breed).frames
                for look in Self.looks {
                    let dressed = PetComposer.clip(animation, for: breed, outfit: look.outfit,
                                                   accessories: look.accessories).frames
                    XCTAssertEqual(dressed.count, plain.count)
                    for (index, frame) in dressed.enumerated() {
                        let label = "\(look.name) on \(breed), \(animation) \(index + 1)"
                        let pixels = costumePixels(frame.canvas, over: plain[index].canvas)
                        if !hidesTheNeck(animation, look.accessories) {
                            XCTAssertFalse(pixels.isEmpty, "not visible: \(label)")
                        }
                        // A one-pixel margin leaves room for the costume's outline.
                        // Aura particles have none and drift in and out past the edges.
                        guard !look.accessories.contains(where: { $0.slot == .aura }) else { continue }
                        let floor = liesOnTheFloor(animation, look.outfit, look.accessories) ? edge + 1 : edge
                        XCTAssertFalse(pixels.contains { $0.x == 0 || $0.y == 0 || $0.x == edge || $0.y == floor },
                                       "clipped at the frame edge: \(label)")
                    }
                }
            }
        }
    }

    func testHeadAndFaceItemsMoveWithTheHeadInEveryFrame() throws {
        // Neck and back items follow the body instead.
        let items = PetAccessory.allCases.filter { $0.slot == .head || $0.slot == .face }
        for breed in PetBreed.allCases {
            let plainSitting = PetComposer.sitting(breed)
            for accessory in items {
                let sitting = (item: costumePixels(PetComposer.sitting(breed, accessories: [accessory]), over: plainSitting).count,
                               nose: points(of: .nose, in: plainSitting).count)
                var offset: PetPoint?
                for animation in PetAnimation.allCases {
                    let plain = PetComposer.clip(animation, for: breed).frames
                    let dressed = PetComposer.clip(animation, for: breed, accessories: [accessory]).frames
                    for (index, frame) in dressed.enumerated() {
                        let label = "\(accessory) on \(breed), \(animation) \(index + 1)"
                        let itemPixels = costumePixels(frame.canvas, over: plain[index].canvas)
                        let nosePixels = points(of: .nose, in: frame.canvas)
                        guard let item = bounds(itemPixels), let nose = bounds(nosePixels),
                              !isCovered(animation, item: itemPixels.count, nose: nosePixels.count, sitting: sitting) else { continue }
                        // A sliding frame that clips the item can't show where it sits.
                        if isSliding(animation), item.minY == 0 { continue }
                        let here = PetPoint(x: item.minX - nose.minX, y: item.minY - nose.minY)
                        if let offset {
                            XCTAssertEqual(here, offset, "drifted off the head: \(label)")
                        } else {
                            offset = here
                        }
                    }
                }
                XCTAssertNotNil(offset, "\(accessory) on \(breed) never seen")
            }
        }
    }

    func testHeadItemsSitAboveTheEyesOnEveryBreed() throws {
        for breed in PetBreed.allCases {
            let plain = PetComposer.sitting(breed)
            let eyes = points(of: .eye, in: plain) + points(of: .eyeLight, in: plain)
            let eyeTop = try XCTUnwrap(eyes.map(\.y).min())
            for accessory in PetAccessory.allCases where accessory.slot == .head {
                let dressed = PetComposer.sitting(breed, accessories: [accessory])
                let label = "\(accessory) on \(breed)"
                let shownEyes = points(of: .eye, in: dressed) + points(of: .eyeLight, in: dressed)
                if accessory.coversEyes {
                    XCTAssertLessThan(shownEyes.count * 2, eyes.count + 1, "leaves both eyes showing: \(label)")
                } else {
                    XCTAssertEqual(shownEyes, eyes, "covers an eye: \(label)")
                }
                let item = try XCTUnwrap(bounds(costumePixels(dressed, over: plain)), label)
                // The Shih Tzu's topknot takes the crown, so its hats sit a row lower.
                let hatLine = breed == .shihTzu ? eyeTop - 1 : eyeTop - 2
                XCTAssertLessThan(item.minY, hatLine, "sits too low to read as a hat: \(label)")
                // Hats rest on the skull: each one covers the head or sits right on
                // it. The halo is meant to float.
                guard accessory != .halo else { continue }
                XCTAssertTrue(costumePixels(dressed, over: plain).contains { plain[$0.x, $0.y] != nil || plain[$0.x, $0.y + 1] != nil },
                              "floats above the head: \(label)")
            }
        }
    }

    /// Outfits, hoods included, leave the face alone on every breed and
    /// in every frame where the plain pet's eyes show.
    func testOutfitsNeverCoverAnEye() {
        for breed in PetBreed.allCases {
            for animation in PetAnimation.allCases {
                let plain = PetComposer.clip(animation, for: breed).frames
                for outfit in PetOutfit.allCases where outfit != .none {
                    let dressed = PetComposer.clip(animation, for: breed, outfit: outfit).frames
                    for (index, frame) in dressed.enumerated() {
                        let eyes = points(of: .eye, in: plain[index].canvas) + points(of: .eyeLight, in: plain[index].canvas)
                        let shown = points(of: .eye, in: frame.canvas) + points(of: .eyeLight, in: frame.canvas)
                        XCTAssertEqual(shown, eyes, "\(outfit) covers an eye on \(breed), \(animation) \(index + 1)")
                    }
                }
            }
        }
    }

    /// Face items sit on the eyes whatever the eye shape: glasses ring them,
    /// shades hide them completely.
    func testFaceItemsSitOnTheEyesOfEveryBreed() throws {
        for breed in PetBreed.allCases {
            let plain = PetComposer.sitting(breed)
            let eyes = points(of: .eye, in: plain) + points(of: .eyeLight, in: plain)
            let eyeRows = try XCTUnwrap(eyes.map(\.y).min())...(try XCTUnwrap(eyes.map(\.y).max()))
            for accessory in PetAccessory.allCases where accessory.slot == .face {
                let item = try XCTUnwrap(bounds(costumePixels(PetComposer.sitting(breed, accessories: [accessory]), over: plain)))
                XCTAssertTrue(item.minY <= eyeRows.lowerBound && item.maxY >= eyeRows.upperBound - 1,
                              "\(accessory) misses the eyes on \(breed)")
            }
        }
    }

    private func points(of role: PetPaletteRole, in canvas: PetCanvas) -> [PetPoint] {
        var points: [PetPoint] = []
        for y in 0..<canvas.height {
            for x in 0..<canvas.width where canvas[x, y] == role { points.append(PetPoint(x: x, y: y)) }
        }
        return points
    }
}
