import XCTest
import NotchDeckCore

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
        XCTAssertEqual(pet.playback?.animation, .idle)
        XCTAssertNotNil(pet.nextBlinkAt)

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
}
