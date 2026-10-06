import XCTest
import TabbiKitCore

final class PetStudyCreditTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func closet(earned: Int = 0, credited: Int? = 0) -> PetCloset {
        var save = PetSave(profile: .starter(.cat), ledger: PetPointsLedger(earned: earned))
        save.creditedFocusCount = credited
        return PetCloset(save: save)
    }

    /// A 25-minute focus phase started at `t0`.
    private func running() -> FocusTimer {
        var timer = FocusTimer()
        timer.start(at: t0)
        return timer
    }

    func testCompletedSessionEarnsMinutesPlusBonus() throws {
        var closet = closet()
        let old = running()
        var new = old
        new.advance(to: t0.addingTimeInterval(25 * 60))

        let award = try XCTUnwrap(closet.credit(from: old.shared, to: new.shared, at: t0.addingTimeInterval(25 * 60)))
        XCTAssertEqual(award.completedSessions, 1)
        XCTAssertEqual(award.minutes, 25)
        XCTAssertEqual(award.points, 25 + PetPointsRules.completionBonus)
        XCTAssertEqual(closet.balance, 35)
        XCTAssertEqual(closet.save.creditedFocusCount, 1)
    }

    func testACompletionIsPaidOnlyOnce() {
        var closet = closet()
        var done = running()
        done.advance(to: t0.addingTimeInterval(25 * 60))
        XCTAssertNotNil(closet.credit(from: running().shared, to: done.shared, at: t0.addingTimeInterval(25 * 60)))
        XCTAssertNil(closet.credit(from: done.shared, to: done.shared, at: t0.addingTimeInterval(26 * 60)))
        XCTAssertNil(closet.credit(from: nil, to: done.shared, at: t0.addingTimeInterval(27 * 60)), "a relaunch sees the same count")
        XCTAssertEqual(closet.balance, 35)
    }

    func testFirstTimerOnlySetsTheBaseline() {
        var closet = closet(credited: nil)
        var timer = running()
        timer.advance(to: t0.addingTimeInterval(25 * 60))
        XCTAssertNil(closet.credit(from: nil, to: timer.shared, at: t0.addingTimeInterval(25 * 60)))
        XCTAssertEqual(closet.balance, 0, "history from before the pet existed is not paid out")
        XCTAssertEqual(closet.save.creditedFocusCount, 1)
    }

    func testSessionsThatEndedWhileClosedArePaidAtLaunch() throws {
        var closet = closet()
        var timer = running()
        // Asleep through the focus end and the break end.
        timer.advance(to: t0.addingTimeInterval(40 * 60))
        let award = try XCTUnwrap(closet.credit(from: nil, to: timer.shared, at: t0.addingTimeInterval(40 * 60)))
        XCTAssertEqual(award.completedSessions, 1)
        XCTAssertEqual(award.points, 35)
    }

    func testAResetTimerHistoryRebaselinesWithoutPaying() {
        var closet = closet(credited: 4)
        XCTAssertNil(closet.credit(from: nil, to: FocusTimer().shared, at: t0))
        XCTAssertEqual(closet.save.creditedFocusCount, 0)
        var done = running()
        done.advance(to: t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(closet.credit(from: running().shared, to: done.shared, at: t0.addingTimeInterval(25 * 60))?.points, 35)
    }

    func testSkippingMidFocusEarnsTheMinutesStudiedWithoutBonus() throws {
        var closet = closet()
        let old = running()
        let now = t0.addingTimeInterval(12 * 60 + 40)
        var skipped = old
        skipped.skip(at: now)

        let award = try XCTUnwrap(closet.credit(from: old.shared, to: skipped.shared, at: now))
        XCTAssertEqual(award.completedSessions, 0)
        XCTAssertEqual(award.minutes, 12)
        XCTAssertEqual(award.points, 12)
    }

    func testResettingAPausedFocusEarnsTheMinutesStudied() {
        var closet = closet()
        var paused = running()
        paused.pause(at: t0.addingTimeInterval(9 * 60))
        var reset = paused
        reset.reset()
        XCTAssertEqual(closet.credit(from: paused.shared, to: reset.shared, at: t0.addingTimeInterval(60 * 60))?.points, 9,
                       "time spent paused doesn't count")
    }

    func testShortOrNonFocusChangesEarnNothing() {
        var closet = closet()
        let old = running()
        var reset = old
        reset.reset()
        XCTAssertNil(closet.credit(from: old.shared, to: reset.shared, at: t0.addingTimeInterval(3 * 60)), "under the minimum")

        var paused = old
        paused.pause(at: t0.addingTimeInterval(10 * 60))
        XCTAssertNil(closet.credit(from: old.shared, to: paused.shared, at: t0.addingTimeInterval(10 * 60)), "pausing is not ending")

        var onBreak = old
        onBreak.advance(to: t0.addingTimeInterval(25 * 60))
        var skippedBreak = onBreak
        skippedBreak.skip(at: t0.addingTimeInterval(26 * 60))
        closet = self.closet(credited: 1)
        XCTAssertNil(closet.credit(from: onBreak.shared, to: skippedBreak.shared, at: t0.addingTimeInterval(26 * 60)), "skipping a break")
        XCTAssertNil(closet.credit(from: old.shared, to: nil, at: t0.addingTimeInterval(10 * 60)), "the timer going away")
        XCTAssertEqual(closet.balance, 0)
    }

    func testAwardNamesItemsThatJustBecameAffordable() throws {
        var closet = closet(earned: 20)
        var done = running()
        done.advance(to: t0.addingTimeInterval(25 * 60))
        let award = try XCTUnwrap(closet.credit(from: running().shared, to: done.shared, at: t0.addingTimeInterval(25 * 60)))
        XCTAssertEqual(closet.balance, 55)
        XCTAssertEqual(award.unlocked, [.accessory(.beanie), .accessory(.roundGlasses)])
        XCTAssertTrue(award.isLevelUp)

        var next = done
        next.advance(to: t0.addingTimeInterval(30 * 60))
        next.start(at: t0.addingTimeInterval(30 * 60))
        let first = next
        next.advance(to: t0.addingTimeInterval(55 * 60))
        let second = try XCTUnwrap(closet.credit(from: first.shared, to: next.shared, at: t0.addingTimeInterval(55 * 60)))
        XCTAssertEqual(second.unlocked, [.accessory(.ninjaHeadband), .accessory(.bunnyEars), .accessory(.coolSunglasses)],
                       "only newly affordable items")
    }

    func testSwitchingToAnotherClockOnlySetsANewBaseline() throws {
        var closet = closet()
        var pomodoro = running()
        pomodoro.advance(to: t0.addingTimeInterval(25 * 60))
        XCTAssertNotNil(closet.credit(from: running().shared, to: pomodoro.shared, at: t0.addingTimeInterval(25 * 60)))
        let balance = closet.balance

        // A Study session starts at zero; then the Pomodoro, with its lifetime
        // total, comes back. Neither switch is a completed session.
        let study = ProvidedFocus(source: .study, phase: .focus, clock: .countUp(since: t0), phaseLength: nil)
        XCTAssertNil(closet.credit(from: pomodoro.shared, to: study, at: t0.addingTimeInterval(26 * 60)))
        XCTAssertNil(closet.credit(from: study, to: pomodoro.shared, at: t0.addingTimeInterval(27 * 60)))
        XCTAssertEqual(closet.balance, balance)
        XCTAssertEqual(closet.save.creditedFocusSource, pomodoro.shared.source)

        // The baseline still pays the Pomodoro's next completion once.
        var next = pomodoro
        next.advance(to: t0.addingTimeInterval(30 * 60))
        next.start(at: t0.addingTimeInterval(30 * 60))
        let started = next
        next.advance(to: t0.addingTimeInterval(55 * 60))
        XCTAssertEqual(closet.credit(from: started.shared, to: next.shared, at: t0.addingTimeInterval(55 * 60))?.completedSessions, 1)
    }

    func testCreditedCountSurvivesSaving() throws {
        var save = PetSave(profile: .starter(.dog))
        save.creditedFocusCount = 7
        save.creditedFocusSource = .study
        XCTAssertEqual(try PetSave.decode(save.encoded()).creditedFocusCount, 7)
        XCTAssertEqual(try PetSave.decode(save.encoded()).creditedFocusSource, .study)
        let old = Data(#"{"version":1,"profile":\#(String(decoding: try JSONEncoder().encode(PetProfile.starter(.cat)), as: UTF8.self)),"ledger":{"earned":0,"spent":0,"purchased":[]}}"#.utf8)
        XCTAssertNil(try PetSave.decode(old).creditedFocusCount, "saves from before credits decode")
    }

    func testCelebrationCopy() {
        let done = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        XCTAssertFalse(done.headline.isEmpty)
        XCTAssertNil(done.unlockLine)
        XCTAssertFalse(done.isLevelUp)
        XCTAssertEqual(done.pointsText, "+35")
        XCTAssertEqual(PetStudyAward(completedSessions: 0, minutes: 12, points: 12).headline, "12 minutes in the bank.")
        XCTAssertEqual(PetStudyAward(completedSessions: 2, minutes: 50, points: 70).headline, "2 sessions done. Wow!")

        let one = PetStudyAward(completedSessions: 1, minutes: 25, points: 35, unlocked: [.outfit(.scrubs)])
        XCTAssertEqual(one.unlockLine, "Enough for the Scrubs now.")
        let three = PetStudyAward(completedSessions: 1, minutes: 25, points: 35,
                                  unlocked: [.accessory(.scarf), .accessory(.beanie), .accessory(.roundGlasses)])
        XCTAssertEqual(three.unlockLine, "Enough for the \(PetItem.accessory(.scarf).displayName) and the \(PetItem.accessory(.beanie).displayName) now.",
                       "names at most two so the line fits the bubble")
    }
}
