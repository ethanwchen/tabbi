import XCTest
@testable import TabbiKitCore

/// The pet's cheer for a finished focus session: how long it holds the
/// closed notch and when the ticker shows it.
final class PetCheerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func cheer(id: Int = 1) -> PetCheer {
        PetCheer(kind: .dance, id: id, startedAt: start)
    }

    private func sources(pet: Bool = true, focus: ProvidedFocus? = nil) -> TickerSources {
        TickerSources(isMusicPlaying: true, focus: focus,
                      pet: pet ? PetPresence(profile: .starter(.cat), lastActive: start) : nil)
    }

    func testACheerLastsAboutTwoSeconds() {
        let cheer = cheer()
        XCTAssertTrue((1.5...2.5).contains(PetCheer.duration))
        XCTAssertTrue(cheer.isShowing(at: start))
        XCTAssertTrue(cheer.isShowing(at: start.addingTimeInterval(PetCheer.duration - 0.01)))
        XCTAssertFalse(cheer.isShowing(at: cheer.endsAt))
        // A clock set back before the start never shows an endless cheer.
        XCTAssertFalse(cheer.isShowing(at: start.addingTimeInterval(-60)))
    }

    func testTheCheeringPetTakesTheNotchWhileTheCheerLasts() {
        let sources = sources()
        // Music would normally lead the rotation.
        XCTAssertEqual(sources.items(at: start).first, .nowPlaying)

        let item = sources.cheering(cheer(), at: start.addingTimeInterval(0.5)) { _ in true }
        guard case .pet(let pet) = item else { return XCTFail("expected the pet, got \(String(describing: item))") }
        XCTAssertEqual(pet.cheer, cheer())
        XCTAssertEqual(pet.profile, .starter(.cat))
        XCTAssertEqual(pet.mood, .awake)

        XCTAssertNil(sources.cheering(cheer(), at: cheer().endsAt) { _ in true }, "over: the rotation is back")
        XCTAssertNil(sources.cheering(nil, at: start) { _ in true })
    }

    func testTheCheeringPetKeepsItsMood() {
        let rest = ProvidedFocus(source: .focus, phase: .rest,
                                 clock: .countdown(endsAt: start.addingTimeInterval(300)), phaseLength: 300)
        let item = sources(focus: rest).cheering(cheer(), at: start) { _ in true }
        guard case .pet(let pet) = item else { return XCTFail("expected the pet") }
        XCTAssertEqual(pet.mood, .onBreak, "the break that just began shows once the hops end")
    }

    func testNoCheerWithoutAPetOrWithThePetPreviewOff() {
        XCTAssertNil(sources(pet: false).cheering(cheer(), at: start) { _ in true })
        XCTAssertNil(sources().cheering(cheer(), at: start) { $0 != .pet })
    }

    func testACrownCheerPutsATinyCrownOnThePet() {
        var hatted = PetProfile.starter(.cat)
        hatted.wear(.wizardHat)
        let sources = TickerSources(isMusicPlaying: false, focus: nil,
                                    pet: PetPresence(profile: hatted, lastActive: start))
        let crown = PetCheer(kind: .crown, id: 1, startedAt: start)
        guard case .pet(let pet) = sources.cheering(crown, at: start, enabled: { _ in true }) else {
            return XCTFail("expected the pet")
        }
        XCTAssertTrue(pet.profile.isWearing(.accessory(.tinyCrown)))
        XCTAssertFalse(pet.profile.isWearing(.accessory(.wizardHat)), "the crown takes the hat's place for now")

        guard case .pet(let dancing) = sources.cheering(cheer(), at: start, enabled: { _ in true }) else {
            return XCTFail("expected the pet")
        }
        XCTAssertEqual(dancing.profile, hatted, "a dance keeps the pet's own look")
        XCTAssertNil(sources.cheering(crown, at: crown.endsAt) { _ in true }, "the crown comes off with the cheer")
    }

    func testASipHoldsThePetOnABreakLongEnoughForTheSip() {
        let sip = PetCheer(kind: .sip, id: 1, startedAt: start)
        XCTAssertGreaterThan(sip.length, PetCheer.duration, "the hop, then the mug comes up")
        XCTAssertLessThanOrEqual(sip.length, 5, "still brief")
        guard case .pet(let pet) = sources().cheering(sip, at: start.addingTimeInterval(3), enabled: { _ in true }) else {
            return XCTFail("expected the pet")
        }
        XCTAssertEqual(pet.mood, .onBreak, "on a break, the pet holds its mug")
        XCTAssertTrue(pet.isSipping)
        XCTAssertEqual(pet.profile, .starter(.cat), "a sip keeps the pet's own look")
        XCTAssertEqual(TickerFormat.petSummary(pet), "Your Mac is charging, and \(pet.profile.name) is having a sip")
        XCTAssertNil(sources().cheering(sip, at: sip.endsAt) { _ in true }, "over: the rotation is back")
        XCTAssertNil(sources().cheering(sip, at: start) { $0 != .pet }, "no sip with the pet preview off")
    }
}
