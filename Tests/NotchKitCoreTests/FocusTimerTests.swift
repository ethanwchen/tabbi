import XCTest
import NotchKitCore

final class FocusTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testDefaultsToIdleTwentyFiveMinuteFocus() {
        let timer = FocusTimer()
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.runState, .idle)
        XCTAssertEqual(timer.remaining(at: t0), 1500)
        XCTAssertEqual(timer.config.restDuration, 300)
        XCTAssertEqual(timer.progress(at: t0), 0)
        XCTAssertNil(timer.endsAt)
    }

    func testRunningTimeComesFromWallClockEndDate() {
        var timer = FocusTimer()
        timer.start(at: t0)
        XCTAssertEqual(timer.endsAt, at(1500))
        XCTAssertEqual(timer.remaining(at: at(600)), 900)
        XCTAssertEqual(timer.progress(at: at(750)), 0.5, accuracy: 0.0001)
        // Starting again while running must not push the end date out.
        timer.start(at: at(100))
        XCTAssertEqual(timer.endsAt, at(1500))
    }

    func testPauseFreezesAndResumeShiftsEndDate() {
        var timer = FocusTimer()
        timer.start(at: t0)
        timer.pause(at: at(600))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: at(5000)), 900)
        timer.start(at: at(5000))
        XCTAssertEqual(timer.endsAt, at(5900))
        timer.pause(at: at(5000))
        timer.pause(at: at(5100))
        XCTAssertEqual(timer.remaining(at: at(9999)), 900)
    }

    func testFocusEndAutoStartsBreakFromExactEndTime() {
        var timer = FocusTimer()
        timer.start(at: t0)
        XCTAssertEqual(timer.advance(to: at(1499)), [])
        let completions = timer.advance(to: at(1510))
        XCTAssertEqual(completions, [FocusPhaseCompletion(phase: .focus, endedAt: at(1500))])
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.endsAt, at(1800))
        XCTAssertEqual(timer.remaining(at: at(1510)), 290)
        XCTAssertEqual(timer.completedFocusCount, 1)
    }

    func testBreakEndWaitsIdleForNextFocus() {
        var timer = FocusTimer()
        timer.start(at: t0)
        timer.advance(to: at(1500))
        let completions = timer.advance(to: at(1800))
        XCTAssertEqual(completions.map(\.phase), [.rest])
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.runState, .idle)
        XCTAssertEqual(timer.remaining(at: at(9000)), 1500)
    }

    func testAdvanceAfterLongSleepReportsBothPhasesOnce() {
        var timer = FocusTimer()
        timer.start(at: t0)
        let completions = timer.advance(to: at(10_000))
        XCTAssertEqual(completions, [
            FocusPhaseCompletion(phase: .focus, endedAt: at(1500)),
            FocusPhaseCompletion(phase: .rest, endedAt: at(1800)),
        ])
        XCTAssertEqual(timer.advance(to: at(20_000)), [])
        XCTAssertEqual(timer.completedFocusCount, 1)
    }

    func testAdvanceIgnoresPausedAndIdleTimers() {
        var timer = FocusTimer()
        XCTAssertEqual(timer.advance(to: at(99_999)), [])
        timer.start(at: t0)
        timer.pause(at: at(10))
        XCTAssertEqual(timer.advance(to: at(99_999)), [])
    }

    func testSkipKeepsRunningStateAndDoesNotCount() {
        var running = FocusTimer()
        running.start(at: t0)
        running.skip(at: at(60))
        XCTAssertEqual(running.phase, .rest)
        XCTAssertEqual(running.endsAt, at(360))
        running.skip(at: at(120))
        XCTAssertEqual(running.phase, .focus)
        XCTAssertEqual(running.endsAt, at(1620))
        XCTAssertEqual(running.completedFocusCount, 0)

        var idle = FocusTimer()
        idle.skip(at: t0)
        XCTAssertEqual(idle.phase, .rest)
        XCTAssertEqual(idle.runState, .idle)
        XCTAssertEqual(idle.remaining(at: t0), 300)
    }

    func testResetReturnsToIdleFocusAndKeepsLinkedItem() {
        let item = UUID()
        var timer = FocusTimer(linkedItemID: item)
        timer.start(at: t0)
        timer.advance(to: at(1600))
        timer.reset()
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.runState, .idle)
        XCTAssertEqual(timer.linkedItemID, item)
    }

    func testCustomConfigClampsToPositiveDurations() {
        let config = FocusTimerConfig(focusDuration: 50 * 60, restDuration: 0)
        XCTAssertEqual(config.focusDuration, 3000)
        XCTAssertEqual(config.restDuration, 1)
        var timer = FocusTimer(config: config)
        timer.start(at: t0)
        XCTAssertEqual(timer.endsAt, at(3000))
    }

    func testStateRoundTripsThroughCodable() throws {
        var timer = FocusTimer(linkedItemID: UUID())
        timer.start(at: t0)
        timer.advance(to: at(1600))
        let decoded = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(decoded, timer)
    }

    func testClockFormatRoundsSecondsUp() {
        XCTAssertEqual(FocusTimerFormat.clock(1500), "25:00")
        XCTAssertEqual(FocusTimerFormat.clock(1499.2), "25:00")
        XCTAssertEqual(FocusTimerFormat.clock(299), "4:59")
        XCTAssertEqual(FocusTimerFormat.clock(0.4), "0:01")
        XCTAssertEqual(FocusTimerFormat.clock(0), "0:00")
        XCTAssertEqual(FocusTimerFormat.clock(-5), "0:00")
        XCTAssertEqual(FocusTimerFormat.clock(3600), "60:00")
    }

    func testPhaseNamesAndCompletionMessages() {
        let config = FocusTimerConfig()
        XCTAssertEqual(FocusTimerFormat.phaseName(.focus), "Focus")
        XCTAssertEqual(FocusTimerFormat.phaseName(.rest), "Break")
        let focusDone = FocusTimerFormat.completionMessage(.init(phase: .focus, endedAt: t0), config: config)
        XCTAssertEqual(focusDone.title, "Focus session done")
        XCTAssertEqual(focusDone.body, "Time for a 5-minute break.")
        let breakDone = FocusTimerFormat.completionMessage(.init(phase: .rest, endedAt: t0), config: config)
        XCTAssertEqual(breakDone.body, "Ready for another 25-minute focus session?")
    }
}
