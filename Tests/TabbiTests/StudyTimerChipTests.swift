import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Timer's length chips start a countdown in one click, and only
/// change the length of one that is already counting.
@MainActor
final class StudyTimerChipTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("study-timer-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A store on a fresh, idle Timer. Snapshot mode saves nothing.
    private func idleTimer() -> StudyStore {
        let store = StudyStore(storage: EditionStorage(root: folder), runMode: RunMode(isDemo: false, isSnapshot: true))
        store.choose(.timer)
        store.stop()
        return store
    }

    func testAChipStartsAnIdleTimer() {
        let store = idleTimer()
        store.startTimer(StudyTimerLength(minutes: 5))
        XCTAssertTrue(store.session.isRunning)
        XCTAssertEqual(store.timer.minutes, 5)
        XCTAssertEqual(store.session.method.kind, .timer)
    }

    func testAChipOnTheCurrentLengthStillStarts() {
        let store = idleTimer()
        store.startTimer(store.timer)
        XCTAssertTrue(store.session.isRunning)
    }

    func testAChipOnAPausedTimerChangesTheLengthWithoutResuming() {
        let store = idleTimer()
        store.startTimer(StudyTimerLength(minutes: 25))
        store.pause()
        store.startTimer(StudyTimerLength(minutes: 10))
        XCTAssertEqual(store.session.runState, .paused)
        XCTAssertEqual(store.timer.minutes, 10)
    }

    func testTheStepperOnlySetsTheLength() {
        let store = idleTimer()
        store.setTimer(store.timer.stepped(up: true))
        XCTAssertEqual(store.session.runState, .idle)
    }
}
