import XCTest
import TabbiKitCore

/// A generator whose every draw is the same fraction of its range, so a
/// `Double.random(in: 0..<1)` returns about `fraction` and a random element
/// is the one at `fraction` of the way through.
struct FixedRandom: RandomNumberGenerator {
    var fraction: Double
    mutating func next() -> UInt64 { UInt64(min(fraction, 0.999_999) * Double(UInt64.max)) }
}

/// Deterministic generator (SplitMix64) for statistical checks.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class SurpriseGiftTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Noon on the `day`th day after 2026-10-05 (UTC), plus `minutes`.
    private func time(day: Int, minutes: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + day, hour: 12, minute: minutes))!
    }

    func testWinningRollGivesAGiftAndLosingRollCountsTowardPity() {
        var state = SurpriseGiftState()
        var lose = FixedRandom(fraction: 0.9)
        XCTAssertNil(state.roll(sessionEnd: time(day: 0), focusMinutes: 25, calendar: calendar, using: &lose))
        XCTAssertEqual(state.dryRolls, 1)

        var win = FixedRandom(fraction: 0.0)
        let gift = state.roll(sessionEnd: time(day: 1), focusMinutes: 25, calendar: calendar, using: &win)
        XCTAssertEqual(gift, .bonusPoints(10))
        XCTAssertEqual(state.dryRolls, 0)
        XCTAssertEqual(state.lastGiftDay, PlannerDayKey(date: time(day: 1), calendar: calendar))
    }

    func testShortSessionsNeverRoll() {
        var state = SurpriseGiftState()
        var win = FixedRandom(fraction: 0.0)
        XCTAssertNil(state.roll(sessionEnd: time(day: 0), focusMinutes: 14, calendar: calendar, using: &win))
        XCTAssertEqual(state.dryRolls, 0)
        XCTAssertNotNil(state.roll(sessionEnd: time(day: 0, minutes: 30), focusMinutes: 15,
                                   calendar: calendar, using: &win))
    }

    func testAtMostOneGiftPerDay() {
        var state = SurpriseGiftState()
        var win = FixedRandom(fraction: 0.0)
        XCTAssertNotNil(state.roll(sessionEnd: time(day: 0), focusMinutes: 25, calendar: calendar, using: &win))
        for session in 1...5 {
            XCTAssertNil(state.roll(sessionEnd: time(day: 0, minutes: session * 30), focusMinutes: 25,
                                    calendar: calendar, using: &win))
        }
        // Capped sessions couldn't win, so they don't count toward pity.
        XCTAssertEqual(state.dryRolls, 0)
        XCTAssertNotNil(state.roll(sessionEnd: time(day: 1), focusMinutes: 25, calendar: calendar, using: &win))
    }

    func testPityTimerGuaranteesAGiftAfterADrySpell() {
        var state = SurpriseGiftState()
        var lose = FixedRandom(fraction: 0.99)
        for day in 0..<SurpriseGiftRules.pityAfter {
            XCTAssertNil(state.roll(sessionEnd: time(day: day), focusMinutes: 25, calendar: calendar, using: &lose))
        }
        XCTAssertEqual(state.dryRolls, SurpriseGiftRules.pityAfter)
        XCTAssertNotNil(state.roll(sessionEnd: time(day: SurpriseGiftRules.pityAfter), focusMinutes: 25,
                                   calendar: calendar, using: &lose))
        XCTAssertEqual(state.dryRolls, 0)
    }

    func testTheSameSessionNeverRollsTwiceEvenAfterARestart() throws {
        var state = SurpriseGiftState()
        var lose = FixedRandom(fraction: 0.9)
        XCTAssertNil(state.roll(sessionEnd: time(day: 0), focusMinutes: 25, calendar: calendar, using: &lose))

        // Saved and loaded again, as on a relaunch.
        let data = try SurpriseGiftState.schema.encode(state)
        var restored = try SurpriseGiftState.schema.decode(SurpriseGiftState.self, from: data)
        XCTAssertEqual(restored, state)
        var win = FixedRandom(fraction: 0.0)
        XCTAssertNil(restored.roll(sessionEnd: time(day: 0), focusMinutes: 25, calendar: calendar, using: &win))
        XCTAssertNil(restored.roll(sessionEnd: time(day: 0, minutes: -30), focusMinutes: 25,
                                   calendar: calendar, using: &win))
        XCTAssertEqual(restored.dryRolls, 1)
    }

    func testAboutOneInFiveQualifyingSessionsBringsAGift() {
        var state = SurpriseGiftState()
        var random = SplitMix(state: 11)
        var gifts = 0
        let days = 4_000
        // One session a day, so the daily cap never interferes.
        for day in 0..<days where state.roll(sessionEnd: time(day: day), focusMinutes: 25,
                                             calendar: calendar, using: &random) != nil {
            gifts += 1
        }
        // 1 in 5, nudged up a little by the pity timer.
        let rate = Double(gifts) / Double(days)
        XCTAssertGreaterThan(rate, 0.19)
        XCTAssertLessThan(rate, 0.27)
    }

    func testRareFursAreFoundOnceEachAndSeasonGiftsNeedAnEvent() {
        var state = SurpriseGiftState()
        var random = SplitMix(state: 3)
        var furs: [RareFur] = []
        var seasonal = 0
        for day in 0..<2_000 {
            let season = day.isMultiple(of: 2) ? "halloween" : nil
            switch state.roll(sessionEnd: time(day: day), focusMinutes: 25, activeSeasonID: season,
                              calendar: calendar, using: &random) {
            case .rareFur(let fur)?: furs.append(fur)
            case .seasonMinutes(let eventID, let minutes)?:
                XCTAssertEqual(eventID, "halloween")
                XCTAssertEqual(minutes, SurpriseGiftRules.seasonMinutes)
                XCTAssertTrue(day.isMultiple(of: 2))
                seasonal += 1
            case .bonusPoints(let points)?: XCTAssertTrue(SurpriseGiftRules.bonusPoints.contains(points))
            case nil: break
            }
        }
        XCTAssertEqual(furs, RareFur.all)
        XCTAssertEqual(state.rareFurs, RareFur.all)
        XCTAssertGreaterThan(seasonal, 0)
        XCTAssertLessThanOrEqual(state.history.count, SurpriseGiftRules.historyLimit)
    }

    func testRareFursAreNotAmongTheClosetSwatches() {
        for fur in RareFur.all {
            XCTAssertFalse(PetCloset.furSwatches.contains(fur.color), fur.name)
        }
    }
}
