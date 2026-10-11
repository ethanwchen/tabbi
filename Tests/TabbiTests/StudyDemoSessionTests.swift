import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The demo Pomodoro is what the App Store shots and preview show: a quarter
/// into round two by default, or a few seconds from the end, so the session
/// can finish on camera.
@MainActor
final class StudyDemoSessionTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testTheDemoPomodoroIsAQuarterIntoItsSecondRound() {
        let session = StudyStore.demoSession(nil, now: now)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.phase, .focus)
        XCTAssertEqual(session.completedFocusCount, 1)
        XCTAssertEqual(session.remaining(at: now), 18 * 60 + 42)
        XCTAssertEqual(session.progress(at: now) ?? 0, 0.25, accuracy: 0.01)
    }

    func testTheDemoPomodoroCanStartSecondsBeforeItEnds() {
        let session = StudyStore.demoSession(nil, now: now, focusLeft: 4)
        XCTAssertEqual(session.remaining(at: now), 4)
        var later = session
        later.advance(to: now.addingTimeInterval(5))
        XCTAssertEqual(later.phase, .shortBreak)
        XCTAssertEqual(later.completedFocusCount, 2)
    }
}
