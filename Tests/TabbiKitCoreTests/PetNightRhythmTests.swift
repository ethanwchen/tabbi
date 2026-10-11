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
}
