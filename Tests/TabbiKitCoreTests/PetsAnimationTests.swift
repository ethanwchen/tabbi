import XCTest
import TabbiKitCore

final class PetAnimationTests: XCTestCase {
    private let baseline = PetComposer.frameSize - 1

    private func eyePixels(_ canvas: PetCanvas) -> Int {
        canvas.pixels.filter { $0 == .eye || $0 == .eyeLight }.count
    }

    private func petPixels(_ canvas: PetCanvas) -> Int {
        canvas.pixels.filter { $0 != nil && $0 != .effect && $0 != .heart }.count
    }

    func testEveryAnimationBuildsForEveryBreedWithPositiveDurations() {
        for breed in PetBreed.allCases {
            for animation in PetAnimation.allCases {
                let clip = PetComposer.clip(animation, for: breed)
                XCTAssertFalse(clip.frames.isEmpty, "\(animation) \(breed)")
                XCTAssertTrue(clip.frames.allSatisfy { $0.duration > 0 }, "\(animation) \(breed)")
                XCTAssertTrue(clip.frames.allSatisfy { $0.canvas.width == PetComposer.frameSize }, "\(animation)")
            }
        }
    }

    func testLoopingClipsWrapAndOneShotClipsHoldTheirLastFrame() {
        let idle = PetComposer.clip(.idle, for: .calico)
        XCTAssertTrue(idle.loops)
        XCTAssertEqual(idle.frameIndex(at: 0), 0)
        XCTAssertEqual(idle.frameIndex(at: idle.frames[0].duration + 0.01), 1)
        XCTAssertEqual(idle.frameIndex(at: idle.duration + 0.01), 0, "wraps after one pass")

        let celebrate = PetComposer.clip(.celebrate, for: .calico)
        XCTAssertFalse(celebrate.loops)
        XCTAssertEqual(celebrate.frameIndex(at: celebrate.duration * 3), celebrate.frames.count - 1)
        XCTAssertEqual(celebrate.frameIndex(at: -1), 0, "negative time shows the first frame")
    }

    func testFrameTimingFollowsEachFramesDuration() {
        let clip = PetComposer.clip(.sleep, for: .beagle)
        var start: TimeInterval = 0
        for (index, frame) in clip.frames.enumerated() {
            XCTAssertEqual(clip.frameIndex(at: start), index)
            XCTAssertEqual(clip.frameIndex(at: start + frame.duration * 0.99), index)
            start += frame.duration
        }
    }

    func testRestingAnimationsKeepThePawsOnTheBaseline() throws {
        for breed in PetBreed.allCases {
            for animation in [PetAnimation.idle, .blink, .sit, .sleep] {
                for frame in PetComposer.clip(animation, for: breed).frames {
                    XCTAssertEqual(try XCTUnwrap(frame.canvas.opaqueBounds).maxY, baseline, "\(animation) \(breed)")
                }
            }
        }
    }

    func testBlinkAndSleepCloseTheEyesAndSleepDriftsZs() {
        for breed in PetBreed.allCases {
            let open = PetComposer.sitting(breed)
            let blink = PetComposer.clip(.blink, for: breed).frames[0].canvas
            XCTAssertFalse(blink.pixels.contains(.eyeLight), "closed eyes have no highlight: \(breed)")
            XCTAssertLessThan(eyePixels(blink), eyePixels(open), "\(breed)")
            XCTAssertNotEqual(blink, open)

            let sleep = PetComposer.clip(.sleep, for: breed)
            XCTAssertTrue(sleep.frames.allSatisfy { !$0.canvas.pixels.contains(.eyeLight) }, "\(breed)")
            XCTAssertTrue(sleep.frames.contains { $0.canvas.pixels.contains(.effect) }, "a z appears: \(breed)")
        }
    }

    func testSleepingDogsCloseTheirMouthButKeepTheirCheeks() {
        let blush: (PetCanvas) -> Int = { $0.pixels.filter { $0 == .blush }.count }
        for breed in PetBreed.allCases {
            let awake = blush(PetComposer.sitting(breed))
            let happy = PetComposer.clip(.celebrate, for: breed).frames.map { blush($0.canvas) }
            XCTAssertTrue(happy.allSatisfy { $0 == awake }, "celebrating keeps the tongue: \(breed)")
            for frame in PetComposer.clip(.sleep, for: breed).frames {
                let asleep = blush(frame.canvas)
                if breed.species == .dog {
                    XCTAssertLessThan(asleep, awake, "the tongue is tucked in: \(breed)")
                    XCTAssertGreaterThanOrEqual(asleep, 4, "cheeks stay rosy: \(breed)")
                } else {
                    XCTAssertEqual(asleep, awake, "cats have no tongue to tuck in: \(breed)")
                }
            }
        }
    }

    func testCelebrationHopsShowsAHeartAndLandsBackOnTheBaseline() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.celebrate, for: breed, outfit: .whiteCoat, accessories: [.graduationCap])
            let lowest = try clip.frames.map { try XCTUnwrap($0.canvas.opaqueBounds).maxY }
            XCTAssertLessThan(lowest.min() ?? baseline, baseline, "the pet leaves the ground: \(breed)")
            XCTAssertEqual(lowest.last, baseline, "and lands again: \(breed)")
            XCTAssertTrue(clip.frames.contains { $0.canvas.pixels.contains(.heart) }, "\(breed)")
            // Hopping with the tallest hat must not clip anything off the top.
            let resting = petPixels(clip.frames[0].canvas)
            for frame in clip.frames {
                XCTAssertEqual(petPixels(frame.canvas), resting, "nothing clipped mid-hop: \(breed)")
            }
        }
    }

    func testAlertFramesCarryASpeechBubbleAnchorBesideTheHead() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.alert, for: breed, accessories: [.beanie])
            XCTAssertFalse(clip.loops)
            for frame in clip.frames {
                let anchor = try XCTUnwrap(frame.bubbleAnchor, "\(breed)")
                let bounds = try XCTUnwrap(frame.canvas.opaqueBounds)
                XCTAssertTrue((0..<PetComposer.frameSize).contains(anchor.x), "\(breed)")
                XCTAssertTrue((bounds.minY...bounds.maxY).contains(anchor.y), "anchor on the pet: \(breed)")
                XCTAssertGreaterThan(anchor.x, PetComposer.frameSize / 2, "right side of the head: \(breed)")
            }
        }
        XCTAssertNil(PetComposer.clip(.idle, for: .corgi).frames[0].bubbleAnchor)
    }

    func testPeekLowersTheHeadOutOfTheTopEdgeAndPeekOutReversesIt() throws {
        for breed in PetBreed.allCases {
            let peekIn = PetComposer.clip(.peekIn, for: breed)
            XCTAssertNil(peekIn.frames[0].canvas.opaqueBounds, "starts hidden in the notch: \(breed)")
            let out = try XCTUnwrap(peekIn.frames.last?.canvas)
            XCTAssertEqual(try XCTUnwrap(out.opaqueBounds).minY, 0, "paws hold the top edge: \(breed)")
            XCTAssertEqual(eyePixels(out), eyePixels(PetComposer.sitting(breed)), "whole face visible: \(breed)")
            // Each frame shows at least as much of the pet as the one before,
            // apart from the final settle after the bounce.
            let shown = peekIn.frames.map { petPixels($0.canvas) }
            XCTAssertEqual(Array(shown.dropLast()), shown.dropLast().sorted(), "\(breed)")

            let peekOut = PetComposer.clip(.peekOut, for: breed)
            XCTAssertEqual(peekOut.frames.map(\.canvas), peekIn.frames.map(\.canvas).reversed(), "\(breed)")
        }
    }

    func testCostumesFollowEveryAnimation() throws {
        let plain = PetComposer.clip(.celebrate, for: .labrador)
        let dressed = PetComposer.clip(.celebrate, for: .labrador, outfit: .scrubs, accessories: [.surgicalCap])
        for (a, b) in zip(plain.frames, dressed.frames) {
            XCTAssertNotEqual(a.canvas, b.canvas)
            XCTAssertTrue(b.canvas.pixels.contains(.costumeBase))
        }
        let peek = PetComposer.clip(.peekIn, for: .labrador, outfit: .scrubs, accessories: [.surgicalCap])
        let hanging = try XCTUnwrap(peek.frames.last?.canvas)
        XCTAssertTrue(hanging.pixels.contains(.costumeBase), "the cap shows while peeking")
    }

    func testWalkCycleLoopsStepsAndStaysInsideTheFrame() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.walk, for: breed, outfit: .whiteCoat, accessories: [.scarf, .graduationCap])
            XCTAssertTrue(clip.loops)
            XCTAssertEqual(clip.frames.count, 4, "\(breed)")
            let canvases = clip.frames.map(\.canvas)
            XCTAssertNotEqual(canvases[0], canvases[1], "contact and passing steps differ: \(breed)")
            XCTAssertNotEqual(canvases[0], canvases[2], "the legs swap on the second contact: \(breed)")
            let last = PetComposer.frameSize - 1
            for canvas in canvases {
                let bounds = try XCTUnwrap(canvas.opaqueBounds)
                XCTAssertEqual(bounds.maxY, baseline, "paws stay on the baseline: \(breed)")
                // Only the outline may touch the frame edges; anything else was clipped.
                let edges = (0...last).flatMap { [canvas[0, $0], canvas[last, $0], canvas[$0, 0]] }
                XCTAssertTrue(edges.allSatisfy { $0 == nil || $0 == .outline }, "nothing clipped: \(breed)")
                XCTAssertTrue(canvas.pixels.contains(.coat), "the coat follows the walk: \(breed)")
            }
            // Walking is side-on: clearly wider than tall.
            let walk = try XCTUnwrap(PetComposer.clip(.walk, for: breed).frames[0].canvas.opaqueBounds)
            XCTAssertGreaterThan(walk.maxX - walk.minX, walk.maxY - walk.minY + 4, "\(breed)")
        }
    }

    func testWalkingCostumesNeverCoverTheFace() {
        for breed in PetBreed.allCases {
            let plain = PetComposer.clip(.walk, for: breed)
            let dressed = PetComposer.clip(.walk, for: breed, outfit: .scrubs,
                                           accessories: [.stethoscope, .roundGlasses, .surgicalCap])
            for (a, b) in zip(plain.frames, dressed.frames) {
                XCTAssertEqual(eyePixels(a.canvas), eyePixels(b.canvas), "\(breed)")
                XCTAssertEqual(a.canvas.pixels.filter { $0 == .nose }.count,
                               b.canvas.pixels.filter { $0 == .nose }.count, "\(breed)")
            }
        }
    }

    func testStretchBowsDownAndRisesBackToStanding() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.stretch, for: breed, outfit: .scrubs, accessories: [.stethoscope, .beanie])
            XCTAssertFalse(clip.loops)
            let canvases = clip.frames.map(\.canvas)
            // It starts and ends on the walk's standing (passing) step, so it
            // chains with walking without a jump.
            let standing = PetComposer.clip(.walk, for: breed, outfit: .scrubs, accessories: [.stethoscope, .beanie])
                .frames[1].canvas
            XCTAssertEqual(canvases.first, standing, "\(breed)")
            XCTAssertEqual(canvases.last, standing, "\(breed)")

            let last = PetComposer.frameSize - 1
            for canvas in canvases {
                let bounds = try XCTUnwrap(canvas.opaqueBounds)
                XCTAssertEqual(bounds.maxY, baseline, "paws stay on the baseline: \(breed)")
                let edges = (0...last).flatMap { [canvas[0, $0], canvas[last, $0], canvas[$0, 0]] }
                XCTAssertTrue(edges.allSatisfy { $0 == nil || $0 == .outline }, "nothing clipped: \(breed)")
                XCTAssertTrue(canvas.pixels.contains(.costumeBase), "scrubs follow the bow: \(breed)")
            }

            // In the bow the head (topmost pixel, under the beanie) sinks while
            // the rump stays up and the eyes squint happily.
            let bow = try XCTUnwrap(canvases.max { $0.opaqueTop(inColumns: 0..<12) < $1.opaqueTop(inColumns: 0..<12) })
            XCTAssertGreaterThan(bow.opaqueTop(inColumns: 0..<12), standing.opaqueTop(inColumns: 0..<12) + 1, "\(breed)")
            XCTAssertEqual(bow.opaqueTop(inColumns: 24..<30), standing.opaqueTop(inColumns: 24..<30),
                           "the rump stays up: \(breed)")
            XCTAssertLessThan(eyePixels(bow), eyePixels(standing), "\(breed)")
        }
    }

    func testYawnOpensTheMouthWideWithEyesSqueezedAndSettlesBack() throws {
        let mouth: (PetCanvas) -> Int = { $0.pixels.filter { $0 == .mouth }.count }
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.yawn, for: breed, accessories: [.graduationCap])
            XCTAssertFalse(clip.loops)
            let sitting = PetComposer.sitting(breed, accessories: [.graduationCap])
            XCTAssertEqual(clip.frames.first?.canvas, sitting, "starts from sitting: \(breed)")
            XCTAssertEqual(clip.frames.last?.canvas, sitting, "and settles back: \(breed)")
            for frame in clip.frames {
                XCTAssertEqual(try XCTUnwrap(frame.canvas.opaqueBounds).maxY, baseline, "\(breed)")
                XCTAssertTrue((0..<PetComposer.frameSize).allSatisfy { frame.canvas[$0, 0] == nil },
                              "tipping the head back clips nothing: \(breed)")
            }
            // The longest frame is the big yawn: eyes shut, mouth open, tongue out.
            let wide = try XCTUnwrap(clip.frames.max { $0.duration < $1.duration }).canvas
            XCTAssertFalse(wide.pixels.contains(.eyeLight), "squeezed shut: \(breed)")
            XCTAssertGreaterThan(mouth(wide), mouth(sitting) + 3, "the mouth opens: \(breed)")
            XCTAssertTrue(wide.pixels.contains(.blush), "\(breed)")
        }
    }

    func testHopBouncesTwiceWithDustAndLandsSitting() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.hop, for: breed, outfit: .whiteCoat, accessories: [.graduationCap])
            XCTAssertFalse(clip.loops)
            let bottoms = try clip.frames.map { frame in
                try XCTUnwrap(frame.canvas.pixels.enumerated().filter { $0.element != nil && $0.element != .effect }
                    .map { $0.offset / PetComposer.frameSize }.max())
            }
            // Airborne, down, airborne again, down: two separate hops.
            let airborne = bottoms.map { $0 < baseline }
            let takeoffs = zip([false] + airborne, airborne).filter { !$0 && $1 }.count
            XCTAssertEqual(takeoffs, 2, "\(breed)")
            XCTAssertEqual(clip.frames.last?.canvas,
                           PetComposer.sitting(breed, outfit: .whiteCoat, accessories: [.graduationCap]), "\(breed)")
            let landings = clip.frames.filter { $0.canvas.pixels.contains(.effect) }
            XCTAssertEqual(landings.count, 2, "a dust puff on each landing: \(breed)")
            XCTAssertFalse(clip.frames.contains { $0.canvas.pixels.contains(.heart) }, "no heart: \(breed)")
            for frame in clip.frames {
                XCTAssertTrue((0..<PetComposer.frameSize).allSatisfy {
                    frame.canvas[$0, 0] == nil || frame.canvas[$0, 0] == .outline
                }, "the cap never clips off the top: \(breed)")
            }
        }
    }

    func testTypingTapsAlternatePawsOnALaptopAndPausesToRead() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.typing, for: breed, accessories: [.roundGlasses])
            XCTAssertTrue(clip.loops, "plays for the whole focus session")
            for frame in clip.frames {
                XCTAssertEqual(try XCTUnwrap(frame.canvas.opaqueBounds).maxY, baseline, "\(breed)")
                XCTAssertTrue(frame.canvas.pixels.contains(.metal), "the laptop is always there: \(breed)")
                XCTAssertTrue(frame.canvas.pixels.contains(.eyeLight), "eyes on the screen: \(breed)")
            }
            // Taps lift one paw at a time, so the tapping frames differ from
            // each other and from resting, and taps come in quick frames.
            let resting = PetComposer.sitting(breed, pose: PetPose(prop: .laptop(tap: 0)), accessories: [.roundGlasses])
            let left = PetComposer.sitting(breed, pose: PetPose(prop: .laptop(tap: -1)), accessories: [.roundGlasses])
            let right = PetComposer.sitting(breed, pose: PetPose(prop: .laptop(tap: 1)), accessories: [.roundGlasses])
            XCTAssertEqual(Set([resting, left, right]).count, 3, "\(breed)")
            let canvases = clip.frames.map(\.canvas)
            XCTAssertTrue(canvases.contains(left) && canvases.contains(right), "both paws type: \(breed)")
            XCTAssertTrue(clip.frames.filter { $0.canvas == left || $0.canvas == right }.allSatisfy { $0.duration < 0.2 })
            // The longest frame is the pause, reading with the head bent.
            let pause = try XCTUnwrap(clip.frames.max { $0.duration < $1.duration })
            XCTAssertGreaterThanOrEqual(pause.duration, 0.5)
            XCTAssertNotEqual(pause.canvas, resting, "reading nods the head: \(breed)")
        }
    }

    func testCoffeeRaisesTheMugToTheMouthForASipWithSteamBetweenSips() throws {
        let mugTop: (PetCanvas) -> Int? = { canvas in
            canvas.pixels.enumerated().filter { $0.element == .accessoryBase }.map { $0.offset / canvas.width }.min()
        }
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.coffee, for: breed)
            XCTAssertTrue(clip.loops, "plays for the whole break")
            let resting = try XCTUnwrap(mugTop(clip.frames[0].canvas), "a mug in the lap: \(breed)")
            for frame in clip.frames {
                XCTAssertEqual(try XCTUnwrap(frame.canvas.opaqueBounds).maxY, baseline, "\(breed)")
                XCTAssertNotNil(mugTop(frame.canvas), "the mug never leaves the paws: \(breed)")
            }
            // The longest frame is the sip: mug up at the mouth, eyes closed.
            let sip = try XCTUnwrap(clip.frames.max { $0.duration < $1.duration }).canvas
            XCTAssertLessThanOrEqual(try XCTUnwrap(mugTop(sip)), resting - 4, "raised to the mouth: \(breed)")
            XCTAssertFalse(sip.pixels.contains(.eyeLight), "eyes closed while sipping: \(breed)")
            // Steam curls above the mug while it rests in the lap.
            let plain = PetComposer.sitting(breed, pose: PetPose(prop: .mug(raise: 0)))
            XCTAssertTrue(clip.frames.contains { $0.canvas != plain && mugTop($0.canvas) == resting }, "\(breed)")
        }
    }

    /// Opaque pixels on the floor row in the frame's left half: a lifted
    /// left front paw leaves fewer there.
    private func leftFloorPixels(_ canvas: PetCanvas) -> Int {
        (0..<canvas.width / 2).filter { canvas[$0, baseline] != nil }.count
    }

    func testWaveLiftsAPawBesideTheHeadAndSwingsItBackAndForth() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.wave, for: breed, outfit: .whiteCoat)
            XCTAssertFalse(clip.loops)
            let sitting = PetComposer.sitting(breed, outfit: .whiteCoat)
            XCTAssertEqual(clip.frames.last?.canvas, sitting, "settles back: \(breed)")
            let out = PetComposer.sitting(breed, pose: PetPose(eyes: .happy, gesture: .wave(swing: 0)), outfit: .whiteCoat)
            let back = PetComposer.sitting(breed, pose: PetPose(eyes: .happy, gesture: .wave(swing: 1)), outfit: .whiteCoat)
            XCTAssertNotEqual(out, back, "\(breed)")
            // Out, in, out, in, out: at least three swings out with a swing
            // back between each.
            let swings = clip.frames.map(\.canvas).filter { $0 == out || $0 == back }
            XCTAssertGreaterThanOrEqual(swings.filter { $0 == out }.count, 3, "\(breed)")
            XCTAssertTrue(zip(swings, swings.dropFirst()).allSatisfy { $0 != $1 }, "swings alternate: \(breed)")
            XCTAssertLessThan(leftFloorPixels(out), leftFloorPixels(sitting), "the paw leaves the floor: \(breed)")
            for frame in clip.frames {
                let canvas = frame.canvas
                XCTAssertEqual(try XCTUnwrap(canvas.opaqueBounds).maxY, baseline, "\(breed)")
                let edges = (0...baseline).flatMap { [canvas[0, $0], canvas[baseline, $0], canvas[$0, 0]] }
                XCTAssertTrue(edges.allSatisfy { $0 == nil || $0 == .outline }, "nothing clipped: \(breed)")
            }
        }
    }

    func testGroomLicksTheRaisedPawThenWashesTheFace() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.groom, for: breed, accessories: [.scarf])
            XCTAssertFalse(clip.loops)
            let sitting = PetComposer.sitting(breed, accessories: [.scarf])
            XCTAssertEqual(clip.frames.last?.canvas, sitting, "settles back: \(breed)")
            let lick = PetComposer.sitting(breed, pose: PetPose(eyes: .closed, mouth: .open, gesture: .groom(reach: 1)),
                                           accessories: [.scarf])
            let canvases = clip.frames.map(\.canvas)
            XCTAssertEqual(canvases.filter { $0 == lick }.count, 3, "three licks: \(breed)")
            XCTAssertLessThan(leftFloorPixels(lick), leftFloorPixels(sitting), "the paw leaves the floor: \(breed)")
            // Each lick is a separate stroke: the paw comes down in between.
            for (index, canvas) in canvases.enumerated() where canvas == lick && index + 1 < canvases.count {
                XCTAssertNotEqual(canvases[index + 1], lick, "\(breed)")
            }
            // The wash bends the head into the paw; the eyes stay shut while
            // the paw is up.
            let wash = PetComposer.sitting(breed, pose: PetPose(eyes: .closed, gesture: .groom(reach: 2), headDrop: 1),
                                           accessories: [.scarf])
            XCTAssertTrue(canvases.contains(wash), "\(breed)")
            XCTAssertNotEqual(wash, lick)
            for frame in clip.frames[1..<(clip.frames.count - 2)] {
                XCTAssertFalse(frame.canvas.pixels.contains(.eyeLight), "eyes shut while grooming: \(breed)")
            }
            for frame in clip.frames {
                XCTAssertEqual(try XCTUnwrap(frame.canvas.opaqueBounds).maxY, baseline, "\(breed)")
            }
        }
    }

    func testTailSwishSweepsTheTailOutTwiceAndLeavesTheRestOfThePetStill() throws {
        for breed in PetBreed.allCases {
            let clip = PetComposer.clip(.tailSwish, for: breed, accessories: [.scarf])
            XCTAssertFalse(clip.loops)
            let sitting = PetComposer.sitting(breed, accessories: [.scarf])
            XCTAssertEqual(clip.frames.first?.canvas, sitting, "starts sitting: \(breed)")
            XCTAssertEqual(clip.frames.last?.canvas, sitting, "settles back: \(breed)")
            let out = PetComposer.sitting(breed, pose: PetPose(tailSwing: 2), accessories: [.scarf])
            let restRight = try XCTUnwrap(sitting.opaqueBounds).maxX
            XCTAssertGreaterThan(try XCTUnwrap(out.opaqueBounds).maxX, restRight, "the tail reaches out: \(breed)")
            // Two sweeps: runs of frames with the tail out, with a return to
            // sitting between them.
            let canvases = clip.frames.map(\.canvas)
            let sweeps = zip(canvases, canvases.dropFirst()).filter { $0 == sitting && $1 != sitting }.count
            XCTAssertEqual(sweeps, 2, "\(breed)")
            XCTAssertTrue(canvases.contains(out), "\(breed)")
            for canvas in canvases {
                // Only the tail moves: the head, face, paws and scarf hold still.
                for y in 0...baseline {
                    for x in 0..<16 { XCTAssertEqual(canvas[x, y], sitting[x, y], "\(breed) at \(x),\(y)") }
                }
                XCTAssertEqual(try XCTUnwrap(canvas.opaqueBounds).maxY, baseline, "\(breed)")
                let edge = (0...baseline).map { canvas[baseline, $0] }
                XCTAssertTrue(edge.allSatisfy { $0 == nil || $0 == .outline }, "nothing clipped: \(breed)")
            }
        }
    }

    func testCanvasShiftAndFlip() {
        var canvas = PetCanvas(width: 3, height: 3)
        canvas[0, 0] = .eye
        let shifted = canvas.shifted(x: 1, y: 2)
        XCTAssertEqual(shifted[1, 2], .eye)
        XCTAssertNil(shifted[0, 0])
        XCTAssertNil(canvas.shifted(x: 0, y: -1).opaqueBounds, "moved off the canvas is clipped")
        XCTAssertEqual(canvas.flippedVertically()[0, 2], .eye)
        XCTAssertEqual(canvas.flippedVertically().flippedVertically(), canvas)
    }
}

private extension PetCanvas {
    /// The highest opaque row within `columns`, or the canvas height if empty.
    func opaqueTop(inColumns columns: Range<Int>) -> Int {
        (0..<height).first { y in columns.contains { self[$0, y] != nil } } ?? height
    }
}
