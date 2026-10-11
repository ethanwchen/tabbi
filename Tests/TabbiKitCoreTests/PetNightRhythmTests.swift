import XCTest
import TabbiKitCore

final class PetNightRhythmTests: XCTestCase {
    private let rhythm = PetNightRhythm.standard

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0, in zone: String = "America/New_York") -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: 10, day: 11, hour: hour, minute: minute))!
    }

    private func runningFocus(at now: Date) -> ProvidedFocus {
        ProvidedFocus(source: .focus, phase: .focus, clock: .countdown(endsAt: now.addingTimeInterval(600)),
                      phaseLength: 25 * 60)
    }

    func testNightWindowWrapsPastMidnight() {
        let ny = calendar("America/New_York")
        XCTAssertFalse(rhythm.isNight(at: date(hour: 22, minute: 59), calendar: ny))
        XCTAssertTrue(rhythm.isNight(at: date(hour: 23), calendar: ny))
        XCTAssertTrue(rhythm.isNight(at: date(hour: 0, minute: 30), calendar: ny))
        XCTAssertTrue(rhythm.isNight(at: date(hour: 5, minute: 59), calendar: ny))
        XCTAssertFalse(rhythm.isNight(at: date(hour: 6), calendar: ny))
        XCTAssertFalse(rhythm.isNight(at: date(hour: 14), calendar: ny))
    }

    func testTimeZoneChangeFollowsLocalTime() {
        // 2 AM in New York is 7 AM in London: the same moment is night for a
        // user in New York and morning once they land in London.
        let moment = date(hour: 2)
        XCTAssertTrue(rhythm.isNight(at: moment, calendar: calendar("America/New_York")))
        XCTAssertFalse(rhythm.isNight(at: moment, calendar: calendar("Europe/London")))
        // 3 PM in New York is past 11 PM in Tokyo.
        let afternoon = date(hour: 15)
        XCTAssertFalse(rhythm.isNight(at: afternoon, calendar: calendar("America/New_York")))
        XCTAssertTrue(rhythm.isNight(at: afternoon, calendar: calendar("Asia/Tokyo")))
    }

    func testPetDozesAtNightWithoutASession() {
        let ny = calendar("America/New_York")
        let now = date(hour: 1)
        XCTAssertTrue(rhythm.dozes(at: now, focus: nil, lastWoken: nil, calendar: ny))
        XCTAssertFalse(rhythm.dozes(at: date(hour: 13), focus: nil, lastWoken: nil, calendar: ny))
    }

    func testARunningOrPausedSessionKeepsThePetAwake() {
        let ny = calendar("America/New_York")
        let now = date(hour: 1)
        XCTAssertFalse(rhythm.dozes(at: now, focus: runningFocus(at: now), lastWoken: nil, calendar: ny))
        let paused = ProvidedFocus(source: .focus, phase: .focus, clock: .paused(shown: 300), phaseLength: 1500)
        XCTAssertFalse(rhythm.dozes(at: now, focus: paused, lastWoken: nil, calendar: ny))
        let idle = ProvidedFocus(source: .focus, phase: .focus, clock: .idle, phaseLength: 1500)
        XCTAssertTrue(rhythm.dozes(at: now, focus: idle, lastWoken: nil, calendar: ny))
    }

    func testOpeningTheNotchWakesThePetForAQuietSpell() {
        let ny = calendar("America/New_York")
        let woke = date(hour: 1)
        XCTAssertFalse(rhythm.dozes(at: woke, focus: nil, lastWoken: woke, calendar: ny))
        XCTAssertFalse(rhythm.dozes(at: woke.addingTimeInterval(rhythm.wakeSpell - 1), focus: nil,
                                    lastWoken: woke, calendar: ny))
        XCTAssertTrue(rhythm.dozes(at: woke.addingTimeInterval(rhythm.wakeSpell), focus: nil,
                                   lastWoken: woke, calendar: ny))
    }

    func testAWakeInTheFutureNeverKeepsThePetUpForever() {
        // The clock was set back after the wake.
        let ny = calendar("America/New_York")
        XCTAssertTrue(rhythm.dozes(at: date(hour: 1), focus: nil, lastWoken: date(hour: 3), calendar: ny))
    }

    func testDaytimeWindowAndEmptyWindow() {
        let utc = calendar("UTC")
        let nap = PetNightRhythm(startHour: 13, endHour: 15, wakeSpell: 0)
        XCTAssertTrue(nap.isNight(at: date(hour: 14, in: "UTC"), calendar: utc))
        XCTAssertFalse(nap.isNight(at: date(hour: 15, in: "UTC"), calendar: utc))
        let never = PetNightRhythm(startHour: 4, endHour: 4, wakeSpell: 0)
        XCTAssertFalse(never.isNight(at: date(hour: 4, in: "UTC"), calendar: utc))
    }

    // MARK: Presence

    private func presence(lastActive: Date) -> PetPresence {
        PetPresence(profile: .starter(.cat), lastActive: lastActive, night: rhythm,
                    calendar: calendar("America/New_York"))
    }

    func testAtNightThePetDozesAfterTheShorterWakeSpell() {
        // A session ended at 11:30 PM: by day the pet would stay up 20
        // minutes, at night it nods off after 10.
        let pet = presence(lastActive: date(hour: 23, minute: 30))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 23, minute: 39)), .awake)
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 23, minute: 40)), .asleep)
        XCTAssertEqual(pet.mood(focus: runningFocus(at: date(hour: 23, minute: 45)), at: date(hour: 23, minute: 45)),
                       .studying, "a session wakes it")
    }

    func testOpeningTheNotchWakesItOnlyAtNight() {
        var pet = presence(lastActive: date(hour: 12))
        pet.wake(at: date(hour: 14))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 14, minute: 1)), .asleep,
                       "by day a napping pet waits for the next session")
        pet.wake(at: date(hour: 23, minute: 50))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 23, minute: 55)), .awake)
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 23, minute: 50).addingTimeInterval(rhythm.wakeSpell)),
                       .asleep, "nods off again after the wake spell")
    }

    func testMorningEndsTheNightDoze() {
        // A session ended at 5:45 AM: dozing at 5:55, awake again once the
        // day's longer quiet spell applies at 6.
        let pet = presence(lastActive: date(hour: 5, minute: 45))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 5, minute: 55)), .asleep)
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 6)), .awake)
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 6, minute: 5)), .asleep)
    }

    func testTickerWakesAtEachNightChange() {
        let pet = presence(lastActive: date(hour: 22))
        // By 10:30 PM the day's quiet spell is over; the next change is the night starting.
        XCTAssertEqual(pet.sleepsAt(focus: nil, after: date(hour: 22, minute: 30)), date(hour: 23))
        var woken = pet
        woken.wake(at: date(hour: 23, minute: 30))
        XCTAssertEqual(woken.sleepsAt(focus: nil, after: date(hour: 23, minute: 31)), date(hour: 23, minute: 40))
        XCTAssertNil(pet.sleepsAt(focus: runningFocus(at: date(hour: 23)), after: date(hour: 23)))
        let sources = TickerSources(pet: woken)
        XCTAssertEqual(sources.nextChange(after: date(hour: 23, minute: 31)), date(hour: 23, minute: 40))
    }

    func testNightFollowsTheCalendarsTimeZone() {
        // 2 AM in New York is 7 AM in London.
        var pet = presence(lastActive: date(hour: 0))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 2)), .asleep)
        pet.calendar = calendar("Europe/London")
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 2)), .asleep, "by day it naps after the quiet spell too")
        pet.wake(at: date(hour: 2))
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 2, minute: 1)), .asleep,
                       "opening the notch in the London morning doesn't wake it")
        pet.calendar = calendar("America/New_York")
        XCTAssertEqual(pet.mood(focus: nil, at: date(hour: 2, minute: 1)), .awake, "but it does at 2 AM in New York")
    }

    func testNextBoundaryIsTheNextNightStartOrEnd() {
        let ny = calendar("America/New_York")
        XCTAssertEqual(rhythm.nextBoundary(after: date(hour: 12), calendar: ny), date(hour: 23))
        XCTAssertEqual(rhythm.nextBoundary(after: date(hour: 3), calendar: ny), date(hour: 6))
        XCTAssertNil(PetNightRhythm(startHour: 5, endHour: 5, wakeSpell: 0).nextBoundary(after: date(hour: 3), calendar: ny))
    }
}
