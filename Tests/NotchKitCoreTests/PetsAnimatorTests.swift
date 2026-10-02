import XCTest
import NotchKitCore

final class PetAnimatorTests: XCTestCase {
    private let clips = PetClipSet(breed: .tuxedo)
    private var durations: [PetAnimation: TimeInterval] { clips.durations }

    private func animator(_ place: PetAnimator.Place = .beside, asleep: Bool = false, seed: UInt64 = 7) -> PetAnimator {
        PetAnimator(durations: durations, place: place, asleep: asleep, at: 0, seed: seed)
    }

    private func animation(_ animator: inout PetAnimator, at time: TimeInterval) -> PetAnimation? {
        animator.advance(to: time)
        return animator.playback?.animation
    }

    func testClipSetHasEveryAnimationAndDurationsMatchTheClips() {
        for animation in PetAnimation.allCases {
            XCTAssertEqual(clips[animation].animation, animation)
            XCTAssertEqual(durations[animation], clips[animation].duration)
        }
        let profile = PetProfile(name: "Mochi", breed: .corgi, outfit: .scrubs, accessories: [.stethoscope])
        XCTAssertEqual(PetClipSet(profile: profile)[.idle],
                       PetComposer.clip(.idle, for: .corgi, outfit: .scrubs, accessories: [.stethoscope]))
    }

    func testStartsInTheRestingAnimationForItsPlace() {
        XCTAssertEqual(animator().playback, .init(animation: .idle, startedAt: 0))
        XCTAssertEqual(animator(asleep: true).playback?.animation, .sleep)
        XCTAssertNil(animator(.hidden).playback, "nothing to draw inside the notch")
        XCTAssertFalse(animator(.hidden, asleep: true).isAsleep, "only a pet beside the notch can doze")

        let hanging = animator(.hanging)
        XCTAssertEqual(hanging.playback?.animation, .peekIn)
        let frame = clips.frame(for: hanging.playback, at: 0)
        XCTAssertEqual(frame, clips[.peekIn].frames.last, "a hanging pet shows the settled frame at once")
        XCTAssertFalse(hanging.isTransitioning(at: 0))
    }

    func testIdleBlinksAtRandomIntervalsAndReturnsToIdleExactlyWhenTheBlinkEnds() throws {
        var pet = animator()
        var blinkStarts: [TimeInterval] = []
        var time: TimeInterval = 0
        while time < 60 {
            time += 1.0 / 30
            pet.advance(to: time)
            if let playback = pet.playback, playback.animation == .blink, blinkStarts.last != playback.startedAt {
                blinkStarts.append(playback.startedAt)
            }
        }
        XCTAssertGreaterThanOrEqual(blinkStarts.count, 60 / Int(PetAnimator.blinkInterval.upperBound + 1))
        var restStart: TimeInterval = 0
        for start in blinkStarts {
            XCTAssertTrue(PetAnimator.blinkInterval.contains(start - restStart), "gap \(start - restStart)")
            restStart = try start + XCTUnwrap(durations[.blink])
        }
        XCTAssertGreaterThan(Set(zip(blinkStarts, blinkStarts.dropFirst()).map { $1 - $0 }).count, 1,
                             "blinks are not on a fixed beat")
    }

    func testBlinkTimingIsReproducibleFromTheSeedAndIndependentOfFrameRate() {
        var coarse = animator(seed: 42)
        var fine = animator(seed: 42)
        coarse.advance(to: 30)
        var time: TimeInterval = 0
        while time < 30 { time += 1.0 / 120; fine.advance(to: min(time, 30)) }
        XCTAssertEqual(coarse, fine, "jumping ahead lands in the same state as ticking")
        XCTAssertNotEqual(animator(seed: 1).nextBlinkAt, animator(seed: 2).nextBlinkAt)
    }

    func testNudgeAlertsThenReturnsToIdleWhenTheClipEnds() throws {
        var pet = animator(asleep: true)
        XCTAssertTrue(pet.send(.nudge, at: 1))
        XCTAssertFalse(pet.isAsleep, "a nudge wakes the pet")
        XCTAssertEqual(pet.playback, .init(animation: .alert, startedAt: 1))
        XCTAssertNotNil(clips.frame(for: pet.playback, at: 1.05)?.bubbleAnchor)

        let end = 1 + (try XCTUnwrap(durations[.alert]))
        XCTAssertEqual(animation(&pet, at: end - 0.01), .alert)
        XCTAssertEqual(animation(&pet, at: end + 0.5), .idle)
        XCTAssertEqual(pet.playback?.startedAt, end, "idle restarts at the clip's end, not the tick")
    }

    func testCelebrateIsNotCutShortByANudgeButCelebrateOverridesAlert() throws {
        var pet = animator()
        pet.send(.celebrate, at: 0)
        XCTAssertFalse(pet.send(.nudge, at: 0.2))
        XCTAssertEqual(pet.playback?.animation, .celebrate)

        pet.advance(to: 10)
        pet.send(.nudge, at: 10)
        XCTAssertTrue(pet.send(.celebrate, at: 10.1))
        XCTAssertEqual(pet.playback, .init(animation: .celebrate, startedAt: 10.1))
    }

    func testSleepAndWake() throws {
        var pet = animator()
        XCTAssertFalse(pet.send(.wake, at: 0), "already awake")
        XCTAssertTrue(pet.send(.sleep, at: 1))
        XCTAssertEqual(pet.playback, .init(animation: .sleep, startedAt: 1))
        XCTAssertNil(pet.nextBlinkAt, "no blinking while asleep")
        XCTAssertEqual(animation(&pet, at: 120), .sleep, "sleep loops")
        XCTAssertTrue(pet.send(.wake, at: 121))
        XCTAssertEqual(pet.playback, .init(animation: .stretch, startedAt: 121), "waking stretches first")
        XCTAssertNil(pet.nextBlinkAt, "no blink mid-stretch")
        let stretchEnd = 121 + (try XCTUnwrap(durations[.stretch]))
        XCTAssertEqual(animation(&pet, at: stretchEnd - 0.01), .stretch)
        XCTAssertEqual(animation(&pet, at: stretchEnd), .idle)
        XCTAssertEqual(pet.playback?.startedAt, stretchEnd, "idle starts exactly when the stretch ends")
        XCTAssertNotNil(pet.nextBlinkAt)

        // Dozing off again mid-stretch waits for the stretch to finish.
        pet.send(.sleep, at: 150)
        pet.send(.wake, at: 151)
        pet.send(.sleep, at: 151.2)
        XCTAssertEqual(pet.playback?.animation, .stretch)
        XCTAssertEqual(animation(&pet, at: 151 + (try XCTUnwrap(durations[.stretch]))), .sleep)

        // A nudge interrupts the stretch: it's the user's attention that matters.
        pet.send(.wake, at: 160)
        XCTAssertTrue(pet.send(.nudge, at: 160.2))
        XCTAssertEqual(pet.playback, .init(animation: .alert, startedAt: 160.2))

        // Dozing off mid-celebration lets the celebration finish first.
        pet.send(.celebrate, at: 200)
        pet.send(.sleep, at: 200.1)
        XCTAssertEqual(pet.playback?.animation, .celebrate)
        XCTAssertEqual(animation(&pet, at: 200 + (try XCTUnwrap(durations[.celebrate]))), .sleep)
    }

    func testPeekInHangsUntilPeekOutThenHides() throws {
        let peek = try XCTUnwrap(durations[.peekIn])
        var pet = animator(.hidden)
        XCTAssertFalse(pet.send(.celebrate, at: 0), "can't celebrate inside the notch")
        XCTAssertTrue(pet.send(.nudge, at: 1), "a nudge from inside the notch peeks out")
        XCTAssertEqual(pet.place, .hanging)
        XCTAssertEqual(pet.playback, .init(animation: .peekIn, startedAt: 1))
        XCTAssertTrue(pet.isTransitioning(at: 1 + peek / 2))

        XCTAssertEqual(animation(&pet, at: 30), .peekIn, "hangs on the held last frame")
        XCTAssertEqual(clips.frame(for: pet.playback, at: 30), clips[.peekIn].frames.last)
        XCTAssertFalse(pet.send(.peekIn, at: 30))

        XCTAssertTrue(pet.send(.peekOut, at: 31))
        XCTAssertEqual(pet.place, .hidden)
        XCTAssertEqual(animation(&pet, at: 31 + peek / 2), .peekOut)
        XCTAssertNil(animation(&pet, at: 31 + peek + 0.01), "gone once it climbs back in")
    }

    func testEventsDuringAPeekTransitionWaitForItToFinish() throws {
        let peek = try XCTUnwrap(durations[.peekIn])
        var pet = animator(.hidden)
        pet.send(.peekIn, at: 0)
        XCTAssertTrue(pet.send(.peekOut, at: peek / 2), "deferred, not dropped")
        XCTAssertEqual(pet.playback?.animation, .peekIn, "the climb out isn't cut")

        XCTAssertEqual(animation(&pet, at: peek + 0.01), .peekOut)
        XCTAssertEqual(pet.playback?.startedAt, peek, "the deferred event starts as the transition ends")

        // Deferred into the hidden state: appear right after climbing back in.
        pet.send(.appear, at: peek + 0.02)
        XCTAssertEqual(animation(&pet, at: peek * 2), .idle)
        XCTAssertEqual(pet.place, .beside)
        XCTAssertEqual(pet.playback?.startedAt, peek * 2)
    }

    func testAppearAndDisappearCutStraightToAPlace() {
        var pet = animator(.hanging)
        pet.send(.disappear, at: 1)
        XCTAssertNil(pet.playback)
        pet.send(.appear, at: 2)
        XCTAssertEqual(pet.place, .beside)
        XCTAssertEqual(pet.playback, .init(animation: .idle, startedAt: 2))
        XCTAssertNil(clips.frame(for: nil, at: 2))
    }

    func testNextFrameBoundaryForLoopingAndOneShotClips() {
        let canvas = PetCanvas(width: 1, height: 1)
        let frames = [PetFrame(canvas: canvas, duration: 0.5), PetFrame(canvas: canvas, duration: 0.25)]
        let loop = PetClip(animation: .idle, frames: frames)
        XCTAssertEqual(loop.nextFrameBoundary(after: 0), 0.5)
        XCTAssertEqual(loop.nextFrameBoundary(after: 0.5), 0.75, "a boundary itself is not 'after'")
        XCTAssertEqual(loop.nextFrameBoundary(after: 0.8), 1.25, "wraps into the next cycle")
        XCTAssertNil(PetClip(animation: .sit, frames: [frames[0]]).nextFrameBoundary(after: 3),
                     "a single-frame loop never changes")

        let once = PetClip(animation: .alert, frames: frames)
        XCTAssertEqual(once.nextFrameBoundary(after: 0.6), 0.75, "the last boundary is the clip's end")
        XCTAssertNil(once.nextFrameBoundary(after: 0.75), "a finished one-shot holds its last frame")
    }

    /// Redrawing only at `nextChange` must never miss a frame: sampling every
    /// millisecond through blinks, an alert, sleep, and a peek finds each
    /// change exactly at a scheduled time, and nothing is scheduled while
    /// the picture holds.
    func testNextChangePredictsEveryFrameChange() throws {
        var pet = animator(seed: 3)
        let events: [Int: PetAnimator.Event] = [4_000: .nudge, 9_000: .sleep, 13_000: .disappear, 14_000: .peekIn]
        struct Shown: Equatable { let animation: PetAnimation?; let index: Int? }
        func shown(_ pet: PetAnimator, _ time: TimeInterval) -> Shown {
            guard let playback = pet.playback else { return Shown(animation: nil, index: nil) }
            return Shown(animation: playback.animation,
                         index: clips[playback.animation].frameIndex(at: playback.elapsed(at: time)))
        }

        var previous = shown(pet, 0)
        var scheduled = clips.nextChange(for: pet, after: 0)
        var changes = 0
        for millisecond in 1...20_000 {
            let time = Double(millisecond) / 1000
            if let event = events[millisecond] {
                pet.send(event, at: time)
            } else {
                pet.advance(to: time)
            }
            let now = shown(pet, time)
            if now != previous, events[millisecond] == nil {
                let due = try XCTUnwrap(scheduled, "frame changed at \(time) with nothing scheduled")
                XCTAssertEqual(due, time, accuracy: 0.001, "frame changed at \(time), scheduled for \(due)")
                changes += 1
            }
            previous = now
            scheduled = clips.nextChange(for: pet, after: time)
            if let scheduled { XCTAssertGreaterThan(scheduled, time) }
        }
        XCTAssertGreaterThan(changes, 20)
        XCTAssertEqual(pet.place, .hanging)
        XCTAssertNil(scheduled, "hanging holds its frame until the next event")
        pet.send(.disappear, at: 20.5)
        XCTAssertNil(clips.nextChange(for: pet, after: 20.5), "nothing to redraw while hidden")
    }
}
