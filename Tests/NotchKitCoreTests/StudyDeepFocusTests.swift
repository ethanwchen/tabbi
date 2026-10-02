import XCTest
import NotchKitCore

final class StudyDeepFocusTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testDeepFocusOffNeverDrivesFocusMode() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        XCTAssertEqual(FocusActivity(session, deepFocus: false), .idle)
    }

    func testRunningFocusIsFocusingAndPauseInterrupts() {
        var session = StudySession(method: .pomodoro)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .idle)
        session.start(at: t0)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .focusing)
        session.pause(at: at(5))
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .interrupted)
    }

    func testBreakInterruptsAndFinishedBreakEndsFocus() {
        var session = StudySession(method: .pomodoro)
        session.start(at: t0)
        session.advance(to: at(26))
        XCTAssertEqual(session.phase, .shortBreak)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .interrupted)
        session.advance(to: at(31))
        XCTAssertEqual(session.runState, .idle)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .idle)
    }

    func testQuestionReviewKeepsFocusing() {
        var session = StudySession(method: .questionBlock)
        session.start(at: t0)
        session.advance(to: at(61))
        XCTAssertEqual(session.phase, .review)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .focusing)
    }

    func testOpenEndedFlowtimeFocusesUntilStopped() {
        var session = StudySession(method: .flowtime)
        session.start(at: t0)
        XCTAssertEqual(FocusActivity(session, deepFocus: true), .focusing)
        session.stopFocus(at: at(40))
        XCTAssertNotEqual(FocusActivity(session, deepFocus: true), .focusing)
    }

    func testCombinedPrefersTheStrongestActivity() {
        XCTAssertEqual(FocusActivity.combined([]), .idle)
        XCTAssertEqual(FocusActivity.combined([.idle, .idle]), .idle)
        XCTAssertEqual(FocusActivity.combined([.idle, .interrupted]), .interrupted)
        XCTAssertEqual(FocusActivity.combined([.interrupted, .focusing, .idle]), .focusing)
    }
}
