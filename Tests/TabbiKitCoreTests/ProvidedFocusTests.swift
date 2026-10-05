import XCTest
import TabbiKitCore

final class ProvidedFocusTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Today's Pomodoro

    func testAnIdleTimerSharesItsFullLengthAndIsNoSession() {
        let focus = FocusTimer().provided(by: .focus)
        XCTAssertEqual(focus.source, .focus)
        XCTAssertEqual(focus.clock, .idle)
        XCTAssertFalse(focus.isActive)
        XCTAssertEqual(focus.remaining(at: t0), 25 * 60)
        XCTAssertEqual(focus.elapsed(at: t0), 0)
    }

    func testARunningTimerCountsDownToItsEnd() {
        var timer = FocusTimer()
        timer.start(at: t0)
        let focus = timer.shared
        XCTAssertEqual(focus.clock, .countdown(endsAt: at(25)))
        XCTAssertTrue(focus.isRunning)
        XCTAssertFalse(focus.countsUp)
        XCTAssertEqual(focus.shownTime(at: at(10)), 15 * 60)
        XCTAssertEqual(focus.elapsed(at: at(10)), 10 * 60)
        XCTAssertEqual(focus.label, "Focus")
    }

    func testABreakKeepsTheFocusLengthForCrediting() {
        var timer = FocusTimer(config: FocusTimerConfig(focusDuration: 50 * 60, restDuration: 10 * 60))
        timer.start(at: t0)
        timer.advance(to: at(50))
        let focus = timer.shared
        XCTAssertEqual(focus.phase, .rest)
        XCTAssertEqual(focus.label, "Break")
        XCTAssertEqual(focus.phaseLength, 10 * 60)
        XCTAssertEqual(focus.focusLength, 50 * 60)
        XCTAssertEqual(focus.completedFocusCount, 1)
    }

    func testAPausedTimerFreezesTimeLeft() {
        var timer = FocusTimer()
        timer.start(at: t0)
        timer.pause(at: at(5))
        XCTAssertEqual(timer.shared.clock, .paused(shown: 20 * 60))
        XCTAssertEqual(timer.shared.elapsed(at: at(60)), 5 * 60)
    }

    // MARK: Followers

    func testTheCoachHoldsItsNudgesForADeepClock() {
        var focus = ProvidedFocus(source: .study, phase: .focus, clock: .countUp(since: t0), phaseLength: nil)
        XCTAssertFalse(PetCoachInput(now: at(5), idleSeconds: 0, frontmost: .neutral, timer: focus).deepFocus)
        focus.isDeep = true
        let input = PetCoachInput(now: at(5), idleSeconds: 0, frontmost: .neutral, timer: focus)
        XCTAssertTrue(input.deepFocus)
        XCTAssertEqual(input.study, .focusing)
    }

    func testAnOpenEndedStretchStudiesWithThePet() {
        let presence = PetPresence(profile: .starter(.cat), lastActive: t0)
        let stretch = ProvidedFocus(source: .study, phase: .focus, clock: .countUp(since: t0), phaseLength: nil)
        XCTAssertEqual(presence.mood(focus: stretch, at: at(90)), .studying)
        XCTAssertNil(presence.sleepsAt(focus: stretch, after: at(90)))
    }

    func testAnOpenEndedStretchCutShortEarnsTheMinutesWorked() throws {
        var save = PetSave(profile: .starter(.cat))
        save.creditedFocusCount = 0
        var closet = PetCloset(save: save)
        let stretch = ProvidedFocus(source: .study, phase: .focus, clock: .countUp(since: t0), phaseLength: nil)
        let stopped = ProvidedFocus(source: .study, phase: .focus, clock: .idle, phaseLength: nil)
        let award = try XCTUnwrap(closet.credit(from: stretch, to: stopped, at: at(30)))
        XCTAssertEqual(award.minutes, 30)
        XCTAssertEqual(award.completedSessions, 0)
    }
}
