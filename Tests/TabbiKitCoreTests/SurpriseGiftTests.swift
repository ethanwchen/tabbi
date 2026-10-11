import XCTest
import TabbiKitCore

/// A generator whose every draw is the same fraction of its range, so a
/// `Double.random(in: 0..<1)` returns about `fraction` and a random element
/// is the one at `fraction` of the way through.
///
/// `Double.random` reads a draw's low 53 bits and an integer draw
/// (`randomElement`) its high bits, so both carry `fraction`. The lowest
/// bits also step on every call: integer draws reject some raw values and
/// draw again, and a constant they reject would loop forever.
struct FixedRandom: RandomNumberGenerator {
    var fraction: Double
    private var calls: UInt64 = 0

    init(fraction: Double) {
        self.fraction = fraction
    }

    mutating func next() -> UInt64 {
        calls &+= 1
        let clamped = min(max(fraction, 0), 0.999_999)
        let high = UInt64(clamped * 2048) << 53
        let low = UInt64(clamped * 9_007_199_254_740_992) & ~UInt64(0x7FF)
        return high | low | (calls % 0x7FF + 1)
    }
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

    func testAnAwardRollsOnlyForCompletedSessionsAtOneSessionsLength() {
        var state = SurpriseGiftState()
        var win = FixedRandom(fraction: 0.0)
        let stopped = PetStudyAward(completedSessions: 0, minutes: 40, points: 30)
        XCTAssertNil(state.roll(after: stopped, at: time(day: 0), calendar: calendar, using: &win))
        // Two 10 minute sessions credited together are two short sessions.
        let short = PetStudyAward(completedSessions: 2, minutes: 20, points: 30)
        XCTAssertNil(state.roll(after: short, at: time(day: 0), calendar: calendar, using: &win))
        XCTAssertEqual(state.dryRolls, 0)
        let session = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        XCTAssertNotNil(state.roll(after: session, at: time(day: 0), calendar: calendar, using: &win))
    }

    func testBonusPointsAddToTheBalanceAsEarnedPoints() {
        var closet = PetCloset(save: PetSave(profile: .starter(.cat)))
        let before = closet.balance
        closet.receiveGift(points: 15)
        XCTAssertEqual(closet.balance, before + 15)
        closet.receiveGift(points: -5)
        XCTAssertEqual(closet.balance, before + 15)
    }

    func testEveryGiftMessageIsOneShortLine() {
        let gifts: [SurpriseGift] = SurpriseGiftRules.bonusPoints.map { .bonusPoints($0) }
            + RareFur.all.map { .rareFur($0) } + [.seasonMinutes(eventID: "halloween", minutes: 15)]
        for gift in gifts {
            XCTAssertLessThanOrEqual(gift.message.count, 40, gift.message)
            XCTAssertLessThanOrEqual(gift.adventureMessage.count, gift.message.count,
                                     "fits wherever the plain line fits: \(gift.adventureMessage)")
        }
    }

    func testADeliveryFromAnAdventureSaysThePetBroughtItBack() {
        let gift = SurpriseGift.bonusPoints(15)
        let date = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(SurpriseGiftDelivery(gift: gift, date: date).message, "A gift: 15 bonus points")
        let adventure = PetJournal.Entry(line: "leaf", date: date, gift: gift)
        XCTAssertEqual(SurpriseGiftDelivery(gift: gift, date: date, adventure: adventure).message,
                       "Found: 15 bonus points")
    }

    func testEveryGiftRoundTripsAsJSON() throws {
        let gifts: [SurpriseGift] = [.bonusPoints(20), .rareFur(RareFur.all[2]),
                                     .seasonMinutes(eventID: "lunar:new-year", minutes: 15)]
        for gift in gifts {
            XCTAssertEqual(try JSONDecoder().decode(SurpriseGift.self, from: JSONEncoder().encode(gift)), gift)
        }
        let unknown = Data(#"{"kind":"crown","value":"1"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SurpriseGift.self, from: unknown))
    }
}

final class SurpriseGiftStateFileTests: XCTestCase {
    func testStateRoundTripsThroughItsVersionedFile() throws {
        var state = SurpriseGiftState()
        var win = FixedRandom(fraction: 0.0)
        _ = state.roll(sessionEnd: Date(timeIntervalSince1970: 1_800_000_000), focusMinutes: 25, using: &win)
        let data = try state.encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), SurpriseGiftState.schema.current)
        XCTAssertEqual(try SurpriseGiftState.decode(data), state)
    }

    func testRareFurSwatchesHaveTheirNames() {
        for fur in RareFur.all {
            XCTAssertEqual(PetCloset.name(ofSwatch: fur.color), fur.name)
        }
    }
}

final class SurpriseGiftDemoTests: XCTestCase {
    func testDemoHasRareFursButNoHistoryOrPity() {
        let demo = SurpriseGiftState.demo
        XCTAssertEqual(demo.rareFurs.count, 2)
        XCTAssertTrue(demo.history.isEmpty)
        XCTAssertEqual(demo.dryRolls, 0)
    }
}
