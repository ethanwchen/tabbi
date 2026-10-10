import Foundation
import TabbiKitCore
import XCTest

/// Animated costume items: each loops a few frames on the item clock, in
/// step on every body shape and pose, holds its still frame under Reduce
/// Motion, and wakes the player only when the picture changes.
final class PetItemLoopTests: XCTestCase {
    private var tick: TimeInterval { PetFrame.itemFrameDuration }

    private func outfitAndAccessories(_ item: PetItem) -> (PetOutfit, [PetAccessory]) {
        switch item {
        case .outfit(let outfit): (outfit, [])
        case .accessory(let accessory): (.none, [accessory])
        }
    }

    /// Limited items animate exactly when they carry an effect; in the
    /// shop, the animated showpieces.
    func testItemsWithAnEffectAndAnimatedShowpiecesAreTheOnesThatAnimate() {
        let animatedShopItems: Set<PetItem> = [
            .accessory(.angelWings), .accessory(.kingsCape), .accessory(.halo),
        ]
        for item in PetItem.allCases {
            XCTAssertEqual(item.loopFrameCount > 1, item.effect != nil || animatedShopItems.contains(item), "\(item)")
        }
        XCTAssertEqual(PetItem.accessory(.angelWings).loopFrameCount, 4)
        XCTAssertEqual(PetItem.accessory(.kingsCape).loopFrameCount, 8)
        XCTAssertEqual(PetItem.accessory(.halo).loopFrameCount, 8)
        XCTAssertEqual(PetItem.accessory(.flameHeadband).loopFrameCount, 4)
        XCTAssertEqual(PetItem.accessory(.goldenLaurel).loopFrameCount, 12)
        XCTAssertEqual(PetItem.accessory(.teamMedal).loopFrameCount, 8)
    }

    /// Every loop starts on the still frame and moves a few pixels of the
    /// item, sitting and walking, on every body shape.
    func testEffectItemsMoveSubtlyOnEveryBodyShape() {
        for item in PetItem.allCases where item.effect != nil {
            let (outfit, accessories) = outfitAndAccessories(item)
            for breed in PetGallery.bodyShapeBreeds {
                for animation in [PetAnimation.idle, .walk] {
                    let frame = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories).frames[0]
                    let label = "\(item) on \(breed) \(animation)"
                    XCTAssertEqual(frame.itemFrames.count, item.loopFrameCount, label)
                    XCTAssertEqual(frame.itemFrames.first, frame.canvas, "the loop opens on the still: \(label)")
                    let changed = frame.itemFrames.map { canvas in
                        zip(canvas.pixels, frame.canvas.pixels).filter { $0 != $1 }.count
                    }
                    XCTAssertTrue(changed.contains { $0 > 0 }, "moves: \(label)")
                    XCTAssertLessThanOrEqual(changed.max() ?? 0, 6, "stays subtle: \(label)")
                }
            }
        }
    }

    /// Back items (wings, the cape) go on the layer behind the pet: in
    /// every animation and every tick of the loop, each pixel of the bare
    /// pet stays as it was, the item shows around it, and it moves.
    func testBackItemsMoveBehindThePetOnEveryBodyShape() {
        // A color only the item brings, to tell it shows.
        let backItems: [PetAccessory: PetPaletteRole] = [.angelWings: .coat, .kingsCape: .crimson]
        XCTAssertEqual(Set(backItems.keys), Set(PetAccessory.allCases.filter { $0.slot == .back }))
        for (accessory, color) in backItems {
            let loop = PetItem.accessory(accessory).loopFrameCount
            for breed in PetGallery.bodyShapeBreeds {
                for animation in PetAnimation.allCases {
                    let bare = PetComposer.clip(animation, for: breed)
                    let worn = PetComposer.clip(animation, for: breed, accessories: [accessory])
                    for (index, (plain, frame)) in zip(bare.frames, worn.frames).enumerated() {
                        let label = "\(accessory) on \(breed) \(animation) frame \(index)"
                        let ticks = frame.itemFrames.isEmpty ? [frame.canvas] : frame.itemFrames
                        for canvas in ticks {
                            let covered = zip(plain.canvas.pixels, canvas.pixels).filter { $0 != nil && $0 != $1 }.count
                            XCTAssertEqual(covered, 0, "nothing in front of the pet: \(label)")
                        }
                        // Hanging from the notch, the body (and the item) are out of view.
                        guard animation != .peekIn, animation != .peekOut else { continue }
                        XCTAssertTrue(ticks.allSatisfy { $0.pixels.contains(color) && $0 != plain.canvas },
                                      "shows: \(label)")
                        XCTAssertEqual(ticks.count, loop, "loops: \(label)")
                        XCTAssertGreaterThan(Set(ticks).count, 1, "moves: \(label)")
                    }
                }
            }
        }
    }

    /// The halo floats over the head on every body shape, sitting and
    /// walking: half the loop up, the other half a pixel lower, its gold
    /// never touching the fur (only the outlines meet), and its glint shows
    /// only on the way up. The poodle's and the Shih Tzu's topknots reach
    /// into it, and the Scottish Fold's flat crown sits higher than other
    /// cats' hat line, so the low halo rests on it without covering it.
    func testHaloBobsAboveTheHeadOnEveryBodyShape() {
        func gold(_ canvas: PetCanvas) -> [PetPoint] {
            canvas.pixels.indices.filter { canvas.pixels[$0] == .gold }
                .map { PetPoint(x: $0 % canvas.width, y: $0 / canvas.width) }
        }
        for breed in PetGallery.bodyShapeBreeds {
            for animation in [PetAnimation.idle, .walk] {
                let bare = PetComposer.clip(animation, for: breed).frames[0].canvas
                let frame = PetComposer.clip(animation, for: breed, accessories: [.halo]).frames[0]
                let label = "\(breed) \(animation)"
                XCTAssertEqual(frame.itemFrames.count, 8, label)
                let tops = frame.itemFrames.map { gold($0).map(\.y).min() }
                guard let up = tops[0] else {
                    XCTFail("halo shows: \(label)")
                    continue
                }
                XCTAssertEqual(tops, Array(repeating: up, count: 4) + Array(repeating: up + 1, count: 4), label)
                let glints = frame.itemFrames.map { $0.pixels.filter { $0 == .effect }.count }
                XCTAssertEqual(glints, [0, 1, 1, 1, 0, 0, 0, 0], label)
                guard ![.poodleDog, .shihTzuDog].contains(breed.bodyShape) else { continue }
                let neighbors = breed.bodyShape == .foldCat ? [(0, 0)] : [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)]
                for (tick, canvas) in frame.itemFrames.enumerated() {
                    for point in gold(canvas) {
                        let around = neighbors.map { bare[point.x + $0.0, point.y + $0.1] }
                        XCTAssertTrue(around.allSatisfy { $0 == nil || $0 == .outline },
                                      "touches the fur at \(point), tick \(tick): \(label)")
                    }
                }
            }
        }
    }

    func testStillItemsHaveNoItemFrames() {
        let clips = PetClipSet(breed: .corgi, outfit: .superheroCape, accessories: [.beanie, .bowTie])
        for animation in PetAnimation.allCases {
            XCTAssertTrue(clips[animation].frames.allSatisfy(\.itemFrames.isEmpty), "\(animation)")
        }
    }

    /// The medal's glint shows on ticks 5 and 6 of 8: the player sleeps
    /// through the plain ticks and wakes on each change.
    func testItemClockPicksTheTickAndSkipsTicksThatLookTheSame() {
        let frame = PetComposer.clip(.sit, for: .orangeTabby, accessories: [.teamMedal]).frames[0]
        XCTAssertEqual(frame.itemFrames.count, 8)
        XCTAssertEqual(frame.atItemTime(5.5 * tick).canvas, frame.itemFrames[5])
        XCTAssertEqual(frame.atItemTime(13.5 * tick).canvas, frame.itemFrames[5], "the loop wraps")
        XCTAssertEqual(frame.atItemTime(0.5 * tick).canvas, frame.canvas)
        XCTAssertNotEqual(frame.itemFrames[5], frame.canvas)
        XCTAssertNotEqual(frame.itemFrames[6], frame.itemFrames[5])
        XCTAssertEqual(frame.itemFrames[7], frame.canvas)
        XCTAssertEqual(try XCTUnwrap(frame.nextItemChange(after: 0.5 * tick)), 5 * tick, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(frame.nextItemChange(after: 5.5 * tick)), 6 * tick, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(frame.nextItemChange(after: 6.5 * tick)), 7 * tick, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(frame.nextItemChange(after: 7.5 * tick)), 13 * tick, accuracy: 1e-9)

        let still = PetComposer.clip(.sit, for: .orangeTabby, accessories: [.beanie]).frames[0]
        XCTAssertNil(still.nextItemChange(after: 0))
        XCTAssertEqual(still.atItemTime(3 * tick), still)
    }

    /// A pet resting on a long idle frame still redraws for its flame, while
    /// the Reduce Motion picture is the still frame.
    func testPlayerFollowsTheItemClockAndReduceMotionHoldsTheStill() throws {
        let clips = PetClipSet(breed: .goldenRetriever, accessories: [.flameHeadband])
        let animator = PetAnimator(durations: clips.durations, at: 0, seed: 7)
        let next = try XCTUnwrap(clips.nextChange(for: animator, after: 0.01))
        XCTAssertLessThanOrEqual(next, tick + 1e-9, "wakes for the next flicker, not the next breath")
        let idle = clips[.idle].frames[0]
        XCTAssertEqual(clips.frame(for: animator.playback, at: 1.5 * tick)?.canvas, idle.itemFrames[1])
        XCTAssertEqual(clips.stillFrame(for: animator)?.canvas, clips[.idle].stillFrame.canvas)
        XCTAssertEqual(clips[.idle].stillFrame.canvas, idle.canvas, "Reduce Motion shows the loop's still")
    }
}
