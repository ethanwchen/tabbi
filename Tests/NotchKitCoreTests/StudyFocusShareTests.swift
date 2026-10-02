import XCTest
import NotchKitCore

final class StudyFocusShareTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testIdleSessionSharesNothing() {
        XCTAssertNil(StudySession(method: .pomodoro).sharedFocusTimer(at: t0))
    }

    func testRunningBlockCountsDownToTheSameEnd() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let timer = try XCTUnwrap(session.sharedFocusTimer(at: at(10)))
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.endsAt, at(25))
        XCTAssertEqual(timer.remaining(at: at(10)), 15 * 60)
        XCTAssertEqual(timer.progress(at: at(10)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(timer.config.focusDuration, 25 * 60)
    }

    func testPausedBlockKeepsItsRemainingTime() throws {
        var session = StudySession(method: .fiftyTwoSeventeen)
        session.start(at: t0)
        session.pause(at: at(12))
        let timer = try XCTUnwrap(session.sharedFocusTimer(at: at(40)))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: at(40)), 40 * 60)
        // The value doesn't depend on the clock, so it isn't republished every second.
        XCTAssertEqual(session.sharedFocusTimer(at: at(50)), timer)
    }

    func testBreakReadsAsRestAndCountsFinishedBlocks() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(26))
        let timer = try XCTUnwrap(session.sharedFocusTimer(at: at(26)))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.completedFocusCount, 1)
        XCTAssertEqual(timer.config.restDuration, 5 * 60)
        XCTAssertEqual(timer.config.focusDuration, 25 * 60)
        XCTAssertEqual(timer.endsAt, at(30))
    }

    func testQuestionReviewReadsAsFocus() throws {
        var session = StudySession(method: .questionBlock)
        session.start(at: t0)
        let block = try XCTUnwrap(StudyMethod.questionBlock.duration(of: .focus))
        session.advance(to: t0.addingTimeInterval(block + 60))
        XCTAssertEqual(session.phase, .review)
        let timer = try XCTUnwrap(session.sharedFocusTimer(at: t0.addingTimeInterval(block + 60)))
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertTrue(timer.isRunning)
    }

    func testOpenEndedStretchIsNotSharedButItsBreakIs() throws {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        XCTAssertNil(session.sharedFocusTimer(at: at(30)))

        session.stopFocus(at: at(40))
        let timer = try XCTUnwrap(session.sharedFocusTimer(at: at(40)))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.config.restDuration, 8 * 60)
        // The stretch actually worked stands in for a focus length.
        XCTAssertEqual(timer.config.focusDuration, 40 * 60)
    }

    func testCardSprintIsNotShared() {
        var session = StudySession(method: .ankiSprint())
        session.start(at: t0)
        XCTAssertNil(session.sharedFocusTimer(at: at(5)))
    }

    func testSharedTimerFeedsTheClosedNotchAndOpensStudy() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(focus: FocusTimer())),
            (.study, ModuleProvision(focus: session.sharedFocusTimer(at: at(5)))),
        ])
        XCTAssertEqual(snapshot.focusSource, .study)
        let items = TickerSources(focus: snapshot.focus, focusSource: snapshot.focusSource).items(at: at(5))
        XCTAssertEqual(items, [.focus(phase: .focus, remaining: 20 * 60, isRunning: true, source: .study)])
        XCTAssertEqual(items.first?.module, .study)
    }

    func testDeepFocusTravelsWithTheWinningTimer() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let study = ModuleProvision(focus: session.sharedFocusTimer(at: at(5)), focusIsDeep: true)
        let snapshot = ProviderSnapshot([(.planner, ModuleProvision(focus: FocusTimer())), (.study, study)])
        XCTAssertEqual(snapshot.focusSource, .study)
        XCTAssertTrue(snapshot.focusIsDeep)
    }

    func testDeepFocusOfALosingTimerIsIgnored() {
        var planner = FocusTimer()
        planner.start(at: t0)
        let idleStudy = ModuleProvision(focus: nil, focusIsDeep: true)
        let snapshot = ProviderSnapshot([(.planner, ModuleProvision(focus: planner)), (.study, idleStudy)])
        XCTAssertEqual(snapshot.focusSource, .planner)
        XCTAssertFalse(snapshot.focusIsDeep)

        // An idle deep-focus timer listed first still gives way to a running one.
        let idleDeep = ModuleProvision(focus: FocusTimer(), focusIsDeep: true)
        let merged = ProviderSnapshot([(.study, idleDeep), (.planner, ModuleProvision(focus: planner))])
        XCTAssertEqual(merged.focusSource, .planner)
        XCTAssertFalse(merged.focusIsDeep)
    }
}
