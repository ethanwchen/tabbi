import XCTest
import NotchDeckCore

final class StudySessionTests: XCTestCase {
    private let minute: TimeInterval = 60
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Basics

    func testNewSessionIsIdleFocusAtFullLength() {
        let session = StudySession(method: .pomodoro)
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.remaining(at: at(10)), 25 * minute)
        XCTAssertEqual(session.progress(at: at(10)), 0)
        XCTAssertNil(session.endsAt)
        XCTAssertTrue(session.log.isEmpty)
    }

    func testRunningCountsDownFromWallClock() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        XCTAssertEqual(session.runState, .running)
        XCTAssertEqual(session.endsAt, at(25))
        XCTAssertEqual(session.remaining(at: at(10)), 15 * minute)
        XCTAssertEqual(session.progress(at: at(10))!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(session.remaining(at: at(40)), 0)
    }

    func testStartWhileRunningDoesNotRestartTheClock() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.start(at: at(5))
        XCTAssertEqual(session.endsAt, at(25))
    }

    func testPauseFreezesAndResumeShiftsTheEnd() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.pause(at: at(10))
        XCTAssertEqual(session.runState, .paused)
        XCTAssertNil(session.endsAt)
        XCTAssertEqual(session.remaining(at: at(60)), 15 * minute)
        XCTAssertTrue(session.advance(to: at(120)).isEmpty, "a paused phase never runs out")

        session.start(at: at(30))
        XCTAssertEqual(session.endsAt, at(45))
        XCTAssertEqual(session.elapsed(at: at(35)), 15 * minute)
    }

    func testPauseWhenNotRunningIsNoOp() {
        var session = StudySession(method: .pomodoro)
        session.pause(at: t0)
        XCTAssertEqual(session.runState, .idle)
    }

    // MARK: Phase flow

    func testFocusEndAutoStartsBreakAndBreakEndWaitsIdle() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)

        let first = session.advance(to: at(26))
        XCTAssertEqual(first.map(\.phase), [.focus])
        XCTAssertEqual(first.first?.endedAt, at(25))
        XCTAssertEqual(first.first?.outcome, .completed)
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.runState, .running)
        XCTAssertEqual(session.endsAt, at(30))
        XCTAssertEqual(session.completedFocusCount, 1)

        let second = session.advance(to: at(31))
        XCTAssertEqual(second.map(\.phase), [.shortBreak])
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.remaining(at: at(90)), 25 * minute)
    }

    func testLongSleepCatchesUpWithRealEndTimes() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let ended = session.advance(to: at(600))
        XCTAssertEqual(ended.map(\.phase), [.focus, .shortBreak])
        XCTAssertEqual(ended.map(\.endedAt), [at(25), at(30)])
        XCTAssertEqual(ended.last?.startedAt, at(25))
        XCTAssertEqual(session.runState, .idle, "never runs on into a new focus while away")
    }

    func testPomodoroLongBreakAfterFourthCompletedFocus() {
        var session = StudySession(method: .pomodoro)
        var now = t0
        var breaks: [StudyPhaseKind] = []
        for _ in 1...4 {
            session.start(at: now)
            now = session.endsAt!
            session.advance(to: now)
            breaks.append(session.phase)
            now = session.endsAt!
            session.advance(to: now)
        }
        XCTAssertEqual(breaks, [.shortBreak, .shortBreak, .shortBreak, .longBreak])
        XCTAssertEqual(session.completedFocusCount, 4)
    }

    func testSkippedFocusDoesNotCountOrEarnLongBreak() {
        var session = StudySession(method: .pomodoro)
        var now = t0
        for _ in 1...4 {
            session.start(at: now)
            now = session.endsAt!
            session.advance(to: now)
            now = session.endsAt!
            session.advance(to: now)
        }
        XCTAssertEqual(session.completedFocusCount, 4)
        session.start(at: now)
        session.skip(at: now.addingTimeInterval(2 * minute))
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.completedFocusCount, 4)
        XCTAssertEqual(session.log.last?.outcome, .skipped)
    }

    func testSkipKeepsRunningOnlyIfItWasRunning() {
        var running = StudySession(method: .pomodoro)
        running.start(at: t0)
        running.skip(at: at(3))
        XCTAssertEqual(running.phase, .shortBreak)
        XCTAssertEqual(running.endsAt, at(8))

        var paused = StudySession(method: .pomodoro)
        paused.start(at: t0)
        paused.pause(at: at(3))
        paused.skip(at: at(4))
        XCTAssertEqual(paused.phase, .shortBreak)
        XCTAssertEqual(paused.runState, .idle)
        XCTAssertEqual(paused.log.last?.activeDuration, 3 * minute)
    }

    func testSkippingBreakWhileRunningDropsIntoRunningFocus() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(25))
        session.skip(at: at(26))
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.endsAt, at(51))
    }

    func testSkippingIdlePhaseLogsNothing() {
        var session = StudySession(method: .pomodoro)
        session.skip(at: t0)
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertTrue(session.log.isEmpty)
    }

    func testResetAbandonsCurrentPhaseAndStartsOver() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(27))
        session.reset(at: at(27))
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.completedFocusCount, 0)
        XCTAssertEqual(session.log.map(\.outcome), [.completed, .abandoned])
        XCTAssertEqual(session.log.last?.activeDuration, 2 * minute)
    }

    func testResetWhileIdleLogsNothing() {
        var session = StudySession(method: .pomodoro)
        session.reset(at: t0)
        XCTAssertTrue(session.log.isEmpty)
    }

    func testSwitchMethodStartsNewMethodIdle() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.switchMethod(to: .ultradian, at: at(5))
        XCTAssertEqual(session.method, .ultradian)
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(session.remaining(at: at(5)), 90 * minute)
        XCTAssertEqual(session.log.map(\.method), [.pomodoro])
    }

    // MARK: Question block

    func testQuestionBlockRunsFocusThenReviewThenBreak() {
        var session = StudySession(method: .questionBlock)
        session.start(at: t0)
        let ended = session.advance(to: at(130))
        XCTAssertEqual(ended.map(\.phase), [.focus, .review, .shortBreak])
        XCTAssertEqual(ended.map(\.endedAt), [at(60), at(120), at(130)])
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.runState, .idle)
    }

    // MARK: Flowtime

    func testFlowtimeFocusIsOpenEndedUntilStopped() {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        XCTAssertNil(session.endsAt)
        XCTAssertNil(session.remaining(at: at(10)))
        XCTAssertNil(session.progress(at: at(10)))
        XCTAssertTrue(session.advance(to: at(500)).isEmpty)
        XCTAssertEqual(session.elapsed(at: at(40)), 40 * minute)
    }

    func testFlowtimeStopStartsProportionalBreak() {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        session.pause(at: at(20))
        session.start(at: at(30))
        XCTAssertTrue(session.stopFocus(at: at(60)))
        // 50 min worked (pause excluded) -> 8 min break on the tiered scheme.
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.phaseDuration, 8 * minute)
        XCTAssertEqual(session.endsAt, at(68))
        XCTAssertEqual(session.completedFocusCount, 1)
        XCTAssertEqual(session.log.last?.outcome, .stopped)
        XCTAssertEqual(session.log.last?.activeDuration, 50 * minute)
    }

    func testFlowtimeFifthSchemeBreak() {
        var session = StudySession(method: .flowtime(scheme: .fifth))
        session.start(at: t0)
        session.stopFocus(at: at(75))
        XCTAssertEqual(session.phaseDuration, 15 * minute)
    }

    func testStopFocusIsRejectedOutsideOpenEndedFocus() {
        var timed = StudySession(method: .pomodoro)
        timed.start(at: t0)
        XCTAssertFalse(timed.stopFocus(at: at(5)))
        XCTAssertEqual(timed.phase, .focus)

        var idle = StudySession(method: .flowtime)
        XCTAssertFalse(idle.stopFocus(at: t0), "nothing to stop before it starts")

        var onBreak = StudySession(method: .flowtime)
        onBreak.start(at: t0)
        onBreak.stopFocus(at: at(10))
        XCTAssertFalse(onBreak.stopFocus(at: at(11)))
        XCTAssertEqual(onBreak.phase, .shortBreak)
    }

    // MARK: Anki sprint

    func testSprintCountsCardsFromReviewedTodayDeltas() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(100, at: t0) // baseline right after starting
        session.recordReviewedToday(120, at: at(5))
        XCTAssertEqual(session.cardsDone, 20)
        XCTAssertEqual(session.progress(at: at(5))!, 0.4, accuracy: 1e-9)
        XCTAssertNil(session.endsAt)
    }

    func testSprintFirstReadingOnlySetsBaseline() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(300, at: at(1))
        XCTAssertEqual(session.cardsDone, 0)
        session.recordReviewedToday(310, at: at(2))
        XCTAssertEqual(session.cardsDone, 10)
    }

    func testSprintIgnoresCardsWhilePausedOrOnBreak() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(0, at: t0)
        session.recordReviewedToday(10, at: at(1))
        session.pause(at: at(2))
        session.recordReviewedToday(30, at: at(3))
        session.start(at: at(4))
        session.recordReviewedToday(32, at: at(4))
        session.recordReviewedToday(37, at: at(5))
        XCTAssertEqual(session.cardsDone, 15)
    }

    func testSprintGoalEndsFocusAndStartsBreak() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(0, at: t0)
        let ended = session.recordReviewedToday(55, at: at(12))
        XCTAssertEqual(ended.map(\.phase), [.focus])
        XCTAssertEqual(ended.first?.cards, 55)
        XCTAssertEqual(ended.first?.outcome, .completed)
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(session.endsAt, at(17))
        XCTAssertEqual(session.cardsDone, 0)

        session.recordReviewedToday(70, at: at(14))
        XCTAssertEqual(session.cardsDone, 0, "cards on a break don't count toward the next sprint")
    }

    func testSprintRolloverDropRebasesWithoutLosingProgress() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.start(at: t0)
        session.recordReviewedToday(200, at: t0)
        session.recordReviewedToday(210, at: at(1))
        session.recordReviewedToday(0, at: at(2)) // Anki's day rolled over
        session.recordReviewedToday(5, at: at(3))
        XCTAssertEqual(session.cardsDone, 15)
    }

    func testSprintIgnoresCardsAnsweredBeforeItStarted() {
        var session = StudySession(method: .ankiSprint(cards: 50))
        session.recordReviewedToday(100, at: t0) // panel open, sprint idle
        // The notch closes, polling stops, and 30 cards are done in Anki.
        session.start(at: at(20))
        session.recordReviewedToday(130, at: at(20))
        XCTAssertEqual(session.cardsDone, 0)
        session.recordReviewedToday(140, at: at(25))
        XCTAssertEqual(session.cardsDone, 10)
    }

    func testSprintStartedBySkippingABreakTakesAFreshBaseline() {
        var session = StudySession(method: .ankiSprint(cards: 20))
        session.start(at: t0)
        session.recordReviewedToday(0, at: t0)
        session.recordReviewedToday(20, at: at(5)) // goal: break starts
        XCTAssertEqual(session.phase, .shortBreak)
        session.skip(at: at(6))
        XCTAssertEqual(session.phase, .focus)
        XCTAssertTrue(session.isRunning)
        session.recordReviewedToday(25, at: at(7))
        XCTAssertEqual(session.cardsDone, 0)
        session.recordReviewedToday(28, at: at(8))
        XCTAssertEqual(session.cardsDone, 3)
    }

    func testSprintSuggestsBreakAfterThirtyMinutesOrTwoHundredCards() {
        var session = StudySession(method: .ankiSprint(cards: 500))
        session.recordReviewedToday(0, at: t0)
        session.start(at: t0)
        XCTAssertFalse(session.suggestsSprintBreak(at: at(29)))
        XCTAssertTrue(session.suggestsSprintBreak(at: at(30)))

        var fast = StudySession(method: .ankiSprint(cards: 500))
        fast.start(at: t0)
        fast.recordReviewedToday(0, at: t0)
        fast.recordReviewedToday(200, at: at(10))
        XCTAssertTrue(fast.suggestsSprintBreak(at: at(10)))

        XCTAssertFalse(StudySession(method: .pomodoro).suggestsSprintBreak(at: at(60)))
    }

    func testCardsAreIgnoredByTimedMethods() {
        var session = StudySession(method: .pomodoro)
        session.recordReviewedToday(0, at: t0)
        session.start(at: t0)
        session.recordReviewedToday(400, at: at(5))
        XCTAssertEqual(session.cardsDone, 0)
        XCTAssertNil(session.log.last?.cards)
    }

    // MARK: Persistence and log

    func testCodableRoundTripResumesMidPhaseAfterRelaunch() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.pause(at: at(5))
        session.start(at: at(8))

        let data = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(StudySession.self, from: data)
        XCTAssertEqual(restored, session)
        XCTAssertEqual(restored.endsAt, at(28))

        // The app was closed past the end; relaunch catches up.
        let ended = restored.advance(to: at(29))
        XCTAssertEqual(ended.first?.endedAt, at(28))
        XCTAssertEqual(ended.first?.activeDuration, 25 * minute)
        XCTAssertEqual(restored.phase, .shortBreak)
    }

    func testCodableRoundTripKeepsSprintBaseline() throws {
        var session = StudySession(method: .ankiSprint(cards: 30))
        session.start(at: t0)
        session.recordReviewedToday(10, at: t0)
        session.recordReviewedToday(20, at: at(1))
        var restored = try JSONDecoder().decode(StudySession.self, from: JSONEncoder().encode(session))
        restored.recordReviewedToday(25, at: at(2))
        XCTAssertEqual(restored.cardsDone, 15)
    }

    func testDecodedZeroLengthMethodDoesNotCompleteInstantly() throws {
        // A corrupt or hand-edited file could carry a zero-length phase.
        let json = #"{"kind":"custom","focus":{"duration":{"_0":0}},"breakRule":{"fixed":{"_0":0}}}"#
        let method = try JSONDecoder().decode(StudyMethod.self, from: Data(json.utf8))
        var session = StudySession(method: method)
        session.start(at: t0)
        XCTAssertTrue(session.advance(to: t0).isEmpty)
        XCTAssertEqual(session.endsAt, at(1))
    }

    func testTakeLogDrainsRecords() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(25))
        let taken = session.takeLog()
        XCTAssertEqual(taken.count, 1)
        XCTAssertEqual(taken.first?.startedAt, t0)
        XCTAssertEqual(taken.first?.method, .pomodoro)
        XCTAssertTrue(session.log.isEmpty)
        XCTAssertTrue(session.takeLog().isEmpty)
    }

    func testOutcomeCounting() {
        XCTAssertTrue(StudyPhaseOutcome.completed.countsAsDone)
        XCTAssertTrue(StudyPhaseOutcome.stopped.countsAsDone)
        XCTAssertFalse(StudyPhaseOutcome.skipped.countsAsDone)
        XCTAssertFalse(StudyPhaseOutcome.abandoned.countsAsDone)
    }
}
