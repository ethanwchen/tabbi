import XCTest
import NotchKitCore

final class StudyPetCueTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testPetDozesUntilTheClockRuns() {
        var session = StudySession(method: .pomodoro)
        XCTAssertTrue(StudyPetCue.isDozing(session))
        session.start(at: t0)
        XCTAssertFalse(StudyPetCue.isDozing(session))
        session.pause(at: at(3))
        XCTAssertTrue(StudyPetCue.isDozing(session))
    }

    func testStartingWakesAndPausingSleeps() {
        let idle = StudySession(method: .pomodoro)
        var running = idle
        running.start(at: t0)
        XCTAssertEqual(StudyPetCue.events(from: idle, to: running), [.wake])
        var paused = running
        paused.pause(at: at(4))
        XCTAssertEqual(StudyPetCue.events(from: running, to: paused), [.sleep])
        XCTAssertEqual(StudyPetCue.events(from: paused, to: paused), [])
    }

    func testFinishedBlockCelebratesAndTheBreakKeepsThePetAwake() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let studying = session
        session.advance(to: at(26))
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(StudyPetCue.events(from: studying, to: session), [.celebrate])
    }

    func testFinishedBreakDozesOffWithoutCelebrating() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(26))
        let onBreak = session
        session.advance(to: at(31))
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(StudyPetCue.events(from: onBreak, to: session), [.sleep])
    }

    func testBlockAndBreakEndingTogetherCelebrateThenDoze() {
        // The Mac slept through a whole block and its break.
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let studying = session
        session.advance(to: at(45))
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(StudyPetCue.events(from: studying, to: session), [.celebrate, .sleep])
    }

    func testEndingAFlowtimeStretchCelebrates() {
        var session = StudySession(method: .preset(.flowtime))
        session.start(at: t0)
        let flowing = session
        session.stopFocus(at: at(40))
        XCTAssertEqual(StudyPetCue.events(from: flowing, to: session), [.celebrate])
    }

    func testSkippingResettingOrSwitchingNeverCelebrates() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        let studying = session

        var skipped = studying
        skipped.skip(at: at(5))
        XCTAssertEqual(StudyPetCue.events(from: studying, to: skipped), [])

        var reset = studying
        reset.reset(at: at(5))
        XCTAssertEqual(StudyPetCue.events(from: studying, to: reset), [.sleep])

        var switched = studying
        switched.switchMethod(to: .preset(.ultradian), at: at(5))
        XCTAssertEqual(StudyPetCue.events(from: studying, to: switched), [.sleep])
    }
}
