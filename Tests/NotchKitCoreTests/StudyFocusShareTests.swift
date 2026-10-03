import XCTest
import NotchKitCore

final class StudyFocusShareTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func shared(_ session: StudySession, at minutes: Double, isDeep: Bool = false) throws -> ProvidedFocus {
        try XCTUnwrap(session.sharedFocus(by: .study, isDeep: isDeep, at: at(minutes)))
    }

    func testIdleSessionSharesNothing() {
        XCTAssertNil(StudySession(method: .pomodoro).sharedFocus(by: .study, at: t0))
    }

    func testRunningBlockCountsDownToTheSameEnd() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let focus = try shared(session, at: 10)
        XCTAssertEqual(focus.source, .study)
        XCTAssertEqual(focus.phase, .focus)
        XCTAssertEqual(focus.label, "Focus")
        XCTAssertTrue(focus.isRunning)
        XCTAssertEqual(focus.endsAt, at(25))
        XCTAssertEqual(focus.remaining(at: at(10)), 15 * 60)
        XCTAssertEqual(focus.elapsed(at: at(10)), 10 * 60)
        XCTAssertEqual(focus.focusLength, 25 * 60)
    }

    func testPausedBlockKeepsItsRemainingTime() throws {
        var session = StudySession(method: .fiftyTwoSeventeen)
        session.start(at: t0)
        session.pause(at: at(12))
        let focus = try shared(session, at: 40)
        XCTAssertTrue(focus.isPaused)
        XCTAssertEqual(focus.remaining(at: at(40)), 40 * 60)
        XCTAssertEqual(focus.elapsed(at: at(40)), 12 * 60)
        // The value doesn't depend on the clock, so it isn't republished every second.
        XCTAssertEqual(try shared(session, at: 50), focus)
    }

    func testBreakReadsAsRestAndCountsFinishedBlocks() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(26))
        let focus = try shared(session, at: 26)
        XCTAssertEqual(focus.phase, .rest)
        XCTAssertEqual(focus.label, "Break")
        XCTAssertEqual(focus.completedFocusCount, 1)
        XCTAssertEqual(focus.phaseLength, 5 * 60)
        XCTAssertEqual(focus.focusLength, 25 * 60)
        XCTAssertEqual(focus.endsAt, at(30))
    }

    func testQuestionReviewReadsAsFocusWithItsOwnLabel() throws {
        var session = StudySession(method: .questionBlock)
        session.start(at: t0)
        let block = try XCTUnwrap(StudyMethod.questionBlock.duration(of: .focus))
        session.advance(to: t0.addingTimeInterval(block + 60))
        XCTAssertEqual(session.phase, .review)
        let focus = try XCTUnwrap(session.sharedFocus(by: .study, at: t0.addingTimeInterval(block + 60)))
        XCTAssertEqual(focus.phase, .focus)
        XCTAssertEqual(focus.label, "Review")
        XCTAssertTrue(focus.isRunning)
    }

    func testOpenEndedStretchCountsUpAndItsBreakCountsDown() throws {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        session.pause(at: at(10))
        session.start(at: at(15))
        let stretch = try shared(session, at: 30)
        XCTAssertEqual(stretch.phase, .focus)
        XCTAssertTrue(stretch.countsUp)
        XCTAssertNil(stretch.remaining(at: at(30)))
        // Counting from a start that leaves the pause out, so the clock reads 25 minutes worked.
        XCTAssertEqual(stretch.clock, .countUp(since: at(5)))
        XCTAssertEqual(stretch.shownTime(at: at(30)), 25 * 60)
        XCTAssertEqual(try shared(session, at: 45), stretch)

        session.stopFocus(at: at(40))
        let rest = try shared(session, at: 40)
        XCTAssertEqual(rest.phase, .rest)
        XCTAssertEqual(rest.phaseLength, 8 * 60)
        // The stretch actually worked stands in for a focus length.
        XCTAssertEqual(rest.focusLength, 35 * 60)
        XCTAssertEqual(rest.completedFocusCount, 1)
    }

    func testPausedOpenEndedStretchShowsTimeWorked() throws {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        session.pause(at: at(20))
        let focus = try shared(session, at: 30)
        XCTAssertEqual(focus.clock, .paused(shown: 20 * 60))
        XCTAssertEqual(focus.elapsed(at: at(30)), 20 * 60)
    }

    func testCardSprintCountsUpAsASprint() throws {
        var session = StudySession(method: .ankiSprint())
        session.start(at: t0)
        let focus = try shared(session, at: 5)
        XCTAssertEqual(focus.label, "Sprint")
        XCTAssertEqual(focus.clock, .countUp(since: t0))
    }

    func testSharedClockFeedsTheClosedNotchAndOpensStudy() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(focus: FocusTimer().shared)),
            (.study, ModuleProvision(focus: session.sharedFocus(by: .study, at: at(5)))),
        ])
        XCTAssertEqual(snapshot.focus?.source, .study)
        let items = TickerSources(focus: snapshot.focus).items(at: at(5))
        XCTAssertEqual(items, [.focus(TickerFocus(phase: .focus, time: 20 * 60, isRunning: true, source: .study))])
        XCTAssertEqual(items.first?.module, .study)
    }

    func testFlowtimeShowsInTheClosedNotchCountingUp() throws {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        let items = TickerSources(focus: session.sharedFocus(by: .study, at: at(12))).items(at: at(12))
        let expected = TickerFocus(phase: .focus, time: 12 * 60, countsUp: true, isRunning: true, source: .study)
        XCTAssertEqual(items, [.focus(expected)])
        XCTAssertEqual(TickerFormat.focusSummary(expected), "Focus 12:00 so far")
    }

    func testDeepFocusTravelsWithTheWinningClock() throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let study = ModuleProvision(focus: try shared(session, at: 5, isDeep: true))
        let snapshot = ProviderSnapshot([(.planner, ModuleProvision(focus: FocusTimer().shared)), (.study, study)])
        XCTAssertEqual(snapshot.focus?.source, .study)
        XCTAssertEqual(snapshot.focus?.isDeep, true)
    }

    func testDeepFocusOfALosingClockIsIgnored() {
        var planner = FocusTimer()
        planner.start(at: t0)
        let snapshot = ProviderSnapshot([(.planner, ModuleProvision(focus: planner.shared)), (.study, ModuleProvision())])
        XCTAssertEqual(snapshot.focus?.source, .planner)
        XCTAssertEqual(snapshot.focus?.isDeep, false)

        // An idle deep-focus clock listed first still gives way to a running one.
        var idleDeep = FocusTimer().provided(by: .study)
        idleDeep.isDeep = true
        let merged = ProviderSnapshot([(.study, ModuleProvision(focus: idleDeep)), (.planner, ModuleProvision(focus: planner.shared))])
        XCTAssertEqual(merged.focus?.source, .planner)
        XCTAssertEqual(merged.focus?.isDeep, false)
    }
}
