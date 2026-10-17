import XCTest
import TabbiKitCore

/// The pet's side of the break buddy: the guiding activity, the happy hop,
/// the sip and breathe clips, and the closed notch's ticker and wording.
final class BreakBuddyPetAnimatorTests: XCTestCase {
    private let clips = PetClipSet(breed: .orangeTabby)
    private var durations: [PetAnimation: TimeInterval] { clips.durations }

    func testGuidingLoopsALoopingClip() {
        var pet = PetAnimator(durations: durations, activity: .guiding(.breathe), at: 0)
        XCTAssertEqual(pet.playback, .init(animation: .breathe, startedAt: 0))
        pet.advance(to: 60)
        XCTAssertEqual(pet.playback, .init(animation: .breathe, startedAt: 0), "a loop just keeps playing")
        XCTAssertNil(pet.nextBlinkAt, "no idle blinks while guiding")
    }

    func testGuidingRestartsAOneShotClipTheMomentItEnds() throws {
        let stretch = try XCTUnwrap(durations[.stretch])
        var pet = PetAnimator(durations: durations, activity: .guiding(.stretch), at: 0)
        pet.advance(to: stretch * 2.5)
        XCTAssertEqual(pet.playback, .init(animation: .stretch, startedAt: stretch * 2))
    }

    func testLeavingAGuidedStretchFinishesItThenSipsCoffee() throws {
        let stretch = try XCTUnwrap(durations[.stretch])
        var pet = PetAnimator(durations: durations, activity: .guiding(.stretch), at: 0)
        pet.send(.activity(.onBreak), at: stretch / 2)
        XCTAssertEqual(pet.playback?.animation, .stretch, "the stretch plays out")
        pet.advance(to: stretch + 0.1)
        XCTAssertEqual(pet.playback, .init(animation: .coffee, startedAt: stretch))
    }

    func testSwitchingFromCoffeeToGuidingStartsTheMoveAtOnce() {
        var pet = PetAnimator(durations: durations, activity: .onBreak, at: 0)
        pet.send(.activity(.guiding(.sip)), at: 5)
        XCTAssertEqual(pet.playback, .init(animation: .sip, startedAt: 5))
        pet.send(.activity(.guiding(.walk)), at: 8)
        XCTAssertEqual(pet.playback, .init(animation: .walk, startedAt: 8))
    }

    func testHopPlaysOnceThenTheMoveComesBack() throws {
        let hop = try XCTUnwrap(durations[.hop])
        var pet = PetAnimator(durations: durations, activity: .guiding(.breathe), at: 0)
        XCTAssertTrue(pet.send(.hop, at: 3))
        XCTAssertEqual(pet.playback, .init(animation: .hop, startedAt: 3))
        pet.send(.activity(.onBreak), at: 3.2)
        XCTAssertEqual(pet.playback?.animation, .hop, "the hop is not cut short")
        pet.advance(to: 3 + hop + 0.01)
        XCTAssertEqual(pet.playback, .init(animation: .coffee, startedAt: 3 + hop))
        var hidden = PetAnimator(durations: durations, place: .hidden, at: 0)
        XCTAssertFalse(hidden.send(.hop, at: 1), "only beside the notch")
    }

    func testTheNewClipsLoopAndHoldAMeaningfulStill() {
        let sip = clips[.sip]
        XCTAssertTrue(sip.loops)
        XCTAssertEqual(sip.stillFrame, sip.frames[2], "Reduce Motion holds the sip itself")
        let breathe = clips[.breathe]
        XCTAssertTrue(breathe.loops)
        XCTAssertEqual(breathe.stillFrame, breathe.frames[0])
        XCTAssertGreaterThan(breathe.duration, 4, "a slow breath")
        XCTAssertGreaterThanOrEqual(PetComposer.clip(.breathe, for: .corgi).frames.count, 2)
    }

    func testTheSipHasNoSteamAndRaisesTheMug() {
        let coffee = clips[.coffee].frames.map(\.canvas)
        let sip = clips[.sip].frames.map(\.canvas)
        // The coffee's first frame has steam; the sip's matching pose doesn't.
        XCTAssertNotEqual(sip[0], coffee[0])
        XCTAssertNotEqual(sip[0], sip[2], "the mug comes up to the mouth")
        XCTAssertEqual(sip[2], coffee[5], "the sip itself is the coffee's steamless sip")
    }

    func testTheBreathSinksTheHeadOnTheWayOut() {
        let frames = clips[.breathe].frames.map(\.canvas)
        XCTAssertNotEqual(frames[0], frames[2])
        XCTAssertNotEqual(frames[1], frames[2], "the soft o closes again")
    }
}

final class BreakBuddyTickerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func moment(_ move: BreakMove = .stretch, startedAt offset: TimeInterval = -10) -> BreakMoment {
        let start = now.addingTimeInterval(offset)
        return BreakMoment(move: move, source: .study, breakStartedAt: start, startedAt: start,
                           endsAt: start.addingTimeInterval(move.length))
    }

    private func sources(moment: BreakMoment?) -> TickerSources {
        var presence = PetPresence(profile: PetProfile(name: "Mochi", breed: .orangeTabby), lastActive: now)
        presence.breakMoment = moment
        let focus = ProvidedFocus(source: .study, phase: .rest, clock: .countdown(endsAt: now.addingTimeInterval(280)),
                                  phaseLength: 300)
        return TickerSources(focus: focus, pet: presence)
    }

    func testThePetCarriesTheMomentWhileItShows() {
        let shown = moment()
        guard case .pet(let pet) = sources(moment: shown).items(at: now, enabled: [.pet]).first else {
            return XCTFail("no pet")
        }
        XCTAssertEqual(pet.breakMoment, shown)
        XCTAssertEqual(pet.mood, .onBreak)
        guard case .pet(let later) = sources(moment: shown).items(at: now.addingTimeInterval(60), enabled: [.pet]).first
        else { return XCTFail("no pet") }
        XCTAssertNil(later.breakMoment, "over once it ends")
    }

    func testTheGuidingPetTakesTheNotchWhileTheMomentShows() {
        let shown = moment()
        XCTAssertNotNil(sources(moment: shown).guiding(at: now) { _ in true })
        XCTAssertNil(sources(moment: shown).guiding(at: now) { $0 != .pet }, "not with the pet's preview off")
        XCTAssertNil(sources(moment: nil).guiding(at: now) { _ in true })
        XCTAssertNil(sources(moment: shown).guiding(at: shown.endsAt) { _ in true })
    }

    func testTheTickerWakesWhenTheMomentEnds() {
        let shown = moment()
        let next = sources(moment: shown).nextChange(after: now, enabled: [.pet])
        XCTAssertEqual(next, shown.endsAt)
    }

    func testNoUnlockHintDuringAMoment() {
        var pet = TickerPet(profile: .starter(.cat), mood: .awake,
                            unlock: UnlockProgress(balance: 40, ledger: PetPointsLedger(purchased: [.accessory(.beanie)])))
        pet.breakMoment = moment()
        XCTAssertNil(pet.unlockHint)
    }

    func testCountdownIsDigitsOnlyAndTheSummaryNamesTheMove() {
        XCTAssertEqual(TickerFormat.breakCountdown(29.2), "0:30")
        XCTAssertEqual(TickerFormat.breakCountdown(60), "1:00")
        XCTAssertEqual(TickerFormat.breakCountdown(-3), "0:00")
        XCTAssertEqual(TickerFormat.breakCountdownSample.count, TickerFormat.breakCountdown(60).count)
        let pet = TickerPet(profile: PetProfile(name: "Mochi", breed: .orangeTabby), mood: .onBreak,
                            breakMoment: moment())
        XCTAssertEqual(TickerFormat.petSummary(pet, at: now), "Stretch with Mochi, 0:30 left")
        let unnamed = TickerPet(profile: PetProfile(name: PetBreed.corgi.displayName, breed: .corgi), mood: .onBreak,
                                breakMoment: moment(.sip))
        XCTAssertEqual(TickerFormat.petSummary(unnamed, at: now), "Sip some water, 0:10 left")
    }
}
