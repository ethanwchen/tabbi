import XCTest
import NotchKitCore

final class PetPresenceTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let profile = PetProfile.starter(.cat)

    private func minutes(_ value: Double) -> Date { start.addingTimeInterval(value * 60) }

    private func focusRunning(since date: Date) -> FocusTimer {
        var timer = FocusTimer(config: FocusTimerConfig(focusDuration: 25 * 60, restDuration: 5 * 60))
        timer.start(at: date)
        return timer
    }

    private func breakRunning(since date: Date) -> FocusTimer {
        var timer = FocusTimer(config: FocusTimerConfig(focusDuration: 25 * 60, restDuration: 5 * 60))
        timer.skip(at: date)
        timer.start(at: date)
        return timer
    }

    // MARK: Mood

    func testPetIsAwakeAtFirstAndFallsAsleepAfterAQuietSpell() {
        let presence = PetPresence(profile: profile, lastActive: start)
        XCTAssertEqual(presence.mood(focus: nil, at: minutes(19)), .awake)
        XCTAssertEqual(presence.mood(focus: nil, at: minutes(20)), .asleep)
        XCTAssertEqual(presence.mood(focus: FocusTimer(), at: minutes(60)), .asleep, "an idle timer is no session")
    }

    func testRunningPhasesShowStudyingOrBreakWhateverTheQuietTime() {
        let presence = PetPresence(profile: profile, lastActive: start)
        XCTAssertEqual(presence.mood(focus: focusRunning(since: minutes(59)), at: minutes(60)), .studying)
        XCTAssertEqual(presence.mood(focus: breakRunning(since: minutes(59)), at: minutes(60)), .onBreak)
    }

    func testPausedSessionKeepsThePetAwake() {
        var timer = focusRunning(since: start)
        timer.pause(at: minutes(1))
        let presence = PetPresence(profile: profile, lastActive: start)
        XCTAssertEqual(presence.mood(focus: timer, at: minutes(90)), .awake)
    }

    func testEndingASessionCountsAsActivity() {
        var presence = PetPresence(profile: profile, lastActive: start)
        presence.observe(focusRunning(since: minutes(30)), at: minutes(30))
        XCTAssertEqual(presence.lastActive, minutes(30))
        // The user stops the timer 25 minutes later: the pet stays up for
        // another quiet spell from then, not from when the session began.
        presence.observe(FocusTimer(), at: minutes(55))
        XCTAssertEqual(presence.lastActive, minutes(55))
        XCTAssertEqual(presence.mood(focus: FocusTimer(), at: minutes(74)), .awake)
        XCTAssertEqual(presence.mood(focus: FocusTimer(), at: minutes(75)), .asleep)
        // Later idle observations don't keep it awake.
        presence.observe(nil, at: minutes(80))
        XCTAssertEqual(presence.lastActive, minutes(55))
    }

    func testObservingNeverMovesLastActiveBack() {
        var presence = PetPresence(profile: profile, lastActive: minutes(10))
        presence.observe(focusRunning(since: start), at: start)
        XCTAssertEqual(presence.lastActive, minutes(10))
    }

    func testSleepsAtIsTheEndOfTheQuietSpell() {
        let presence = PetPresence(profile: profile, lastActive: start)
        XCTAssertEqual(presence.sleepsAt(focus: nil, after: minutes(5)), minutes(20))
        XCTAssertNil(presence.sleepsAt(focus: nil, after: minutes(20)), "already asleep")
        XCTAssertNil(presence.sleepsAt(focus: focusRunning(since: start), after: minutes(5)))
    }

    // MARK: Ticker

    func testPetIsTheLastTickerItemAndCarriesItsMood() {
        let pet = PetPresence(profile: profile, lastActive: start)
        let sources = TickerSources(tasksRemaining: 2, pet: pet)
        XCTAssertEqual(sources.items(at: minutes(1)), [
            .tasks(remaining: 2),
            .pet(TickerPet(profile: profile, mood: .awake)),
        ])
        XCTAssertEqual(sources.items(at: minutes(30)).last, .pet(TickerPet(profile: profile, mood: .asleep)))
        XCTAssertEqual(sources.items(at: minutes(1), enabled: [.tasks]), [.tasks(remaining: 2)])
        XCTAssertEqual(TickerKind.pet.module, .closet)
    }

    func testTickerWakesWhenThePetFallsAsleep() {
        let sources = TickerSources(pet: PetPresence(profile: profile, lastActive: start))
        XCTAssertEqual(sources.nextChange(after: minutes(1)), minutes(20))
        XCTAssertNil(sources.nextChange(after: minutes(1), enabled: [.tasks]))
        XCTAssertNil(sources.nextChange(after: minutes(21)))
    }

    func testTooltipNamesThePetAndWhatItIsDoing() {
        var pet = TickerPet(profile: profile, mood: .studying)
        XCTAssertEqual(TickerFormat.petSummary(pet), "\(profile.name) is studying with you")
        pet.mood = .asleep
        XCTAssertEqual(TickerFormat.petSummary(pet), "\(profile.name) is napping until your next session")
    }

    // MARK: Providers

    func testSnapshotKeepsTheFirstPetInTabOrder() {
        let first = PetPresence(profile: profile, lastActive: start)
        let second = PetPresence(profile: .starter(.dog), lastActive: start)
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision()),
            (.closet, ModuleProvision(pet: first)),
            (.party, ModuleProvision(pet: second)),
        ])
        XCTAssertEqual(snapshot.pet, first)
        XCTAssertNil(ProviderSnapshot([(.planner, ModuleProvision())]).pet)
    }
}
