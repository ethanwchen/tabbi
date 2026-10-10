import AppKit
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Pomodoro controls the Focus tab and Today's card call (play and
/// pause, "Focus on this", linking a task), what a launch makes of a
/// session the last run left behind, and the demo's sample session.
@MainActor
final class FocusStoreControlTests: XCTestCase {
    private var defaults: UserDefaults!
    private let workspace = NotificationCenter()
    private let app = NotificationCenter()

    override func setUp() async throws {
        defaults = InMemoryDefaults()
    }

    private func launch(log: ActivityLog = ActivityLog(repository: nil)) -> FocusStore {
        FocusStore(activity: log, runMode: .live, defaults: defaults, interruptions: (workspace, app))
    }

    private var saved: FocusTimer { FocusTimerStorage(defaults: defaults).loadTimer() }

    /// Saves a timer the way the last run left it, with an optional heartbeat.
    private func save(_ timer: FocusTimer, lastAlive: Date? = nil) {
        let storage = FocusTimerStorage(defaults: defaults)
        storage.save(timer)
        if let lastAlive { storage.saveLastAlive(lastAlive) }
    }

    /// Waits for the records a launch logs on the next main-queue turn.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    /// Records from yesterday and today, so a test run just after midnight
    /// still finds a phase that ended before it.
    private func logged(in log: ActivityLog) -> [ActivityRecord] {
        let today = PlannerDayKey(date: Date())
        return log.records(on: today.adding(days: -1)) + log.records(on: today)
    }

    // MARK: Controls

    func testPlayAndPauseKeepTheTimeLeftAndSaveEachStep() throws {
        let log = ActivityLog(repository: nil)
        let store = launch(log: log)

        store.toggleRunning()
        XCTAssertTrue(store.timer.isRunning)
        XCTAssertTrue(saved.isRunning, "the running timer is saved")
        XCTAssertNotNil(FocusTimerStorage(defaults: defaults).lastAlive, "a running session keeps a heartbeat")

        store.toggleRunning()
        XCTAssertTrue(store.timer.isPaused)
        XCTAssertEqual(store.timer.phase, .focus)
        let left = store.timer.remaining(at: Date().addingTimeInterval(3600))
        XCTAssertEqual(left, FocusTimerConfig().focusDuration, accuracy: 2, "a paused clock stands still")
        XCTAssertEqual(saved, store.timer, "the pause is saved")

        store.toggleRunning()
        XCTAssertTrue(store.timer.isRunning, "play resumes")
        XCTAssertEqual(try XCTUnwrap(store.timer.endsAt).timeIntervalSinceNow, left, accuracy: 2,
                       "and picks up where the pause left off")
        XCTAssertTrue(logged(in: log).isEmpty, "playing and pausing earns nothing on its own")
    }

    func testPausingAnIdleTimerChangesNothing() {
        let store = launch()
        let before = store.timer

        store.pause()

        XCTAssertEqual(store.timer, before)
        XCTAssertNil(FocusTimerStorage(defaults: defaults).lastAlive, "no session, no heartbeat")
    }

    func testFocusOnATaskLinksItAndStartsAFocusSession() {
        let store = launch()
        let task = UUID()

        store.focus(on: task)

        XCTAssertEqual(store.timer.linkedItemID, task)
        XCTAssertTrue(store.timer.isRunning)
        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(saved.linkedItemID, task, "the link is saved")
    }

    func testFocusOnAnotherTaskSwitchesTheLinkWithoutTouchingTheClock() {
        let store = launch()
        store.focus(on: UUID())
        store.pause()
        let paused = store.timer.runState
        let next = UUID()

        store.focus(on: next)

        XCTAssertEqual(store.timer.linkedItemID, next)
        XCTAssertEqual(store.timer.runState, paused, "a paused session stays paused")
    }

    func testFocusOnATaskDuringAnIdleBreakDoesNotStartTheBreak() {
        let store = launch()
        store.skip()
        XCTAssertEqual(store.timer.phase, .rest, "skipping an idle focus phase lands on an idle break")
        let task = UUID()

        store.focus(on: task)

        XCTAssertEqual(store.timer.linkedItemID, task)
        XCTAssertEqual(store.timer.runState, .idle)
    }

    func testUnlinkingClearsTheTaskAndStoppingKeepsIt() {
        let store = launch()
        let task = UUID()
        store.focus(on: task)

        store.stop()
        XCTAssertEqual(store.timer.linkedItemID, task, "stopping ends the session, not the link")

        store.link(nil)
        XCTAssertNil(store.timer.linkedItemID)
        XCTAssertNil(saved.linkedItemID, "the cleared link is saved")
    }

    // MARK: Launch

    /// Builds before the heartbeat left no last-alive time: a phase that ran
    /// out while Tabbi was gone counts as finished, and the break it started
    /// on its own too, once each.
    func testLaunchingAfterAnOldBuildCountsThePhasesThatRanOut() throws {
        var timer = FocusTimer()
        timer.start(at: Date().addingTimeInterval(-2 * 3600))
        save(timer)
        let log = ActivityLog(repository: nil)

        let store = launch(log: log)
        drainMainQueue()

        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(store.timer.runState, .idle, "the next focus waits for the user")
        XCTAssertEqual(store.timer.completedFocusCount, 1)
        XCTAssertEqual(saved, store.timer, "the caught-up timer is saved")
        let records = logged(in: log)
        XCTAssertEqual(records.map(\.kind), [.focusCompleted, .breakTaken])
        XCTAssertEqual(try XCTUnwrap(records.first?.quantity), 25, accuracy: 0.01, "a full Pomodoro")

        _ = launch(log: log)
        drainMainQueue()
        XCTAssertEqual(logged(in: log).count, 2, "the next launch counts nothing again")
    }

    /// A crash on the break that followed a full focus phase: the focus
    /// counts as finished and the break, which earns nothing, just ends.
    func testACrashDuringTheBreakCountsTheFinishedFocusAndEndsTheBreak() throws {
        var timer = FocusTimer()
        let started = Date().addingTimeInterval(-40 * 60)
        timer.start(at: started)
        save(timer, lastAlive: started.addingTimeInterval(27 * 60))
        let log = ActivityLog(repository: nil)

        let store = launch(log: log)
        drainMainQueue()

        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(store.timer.runState, .idle)
        let records = logged(in: log)
        XCTAssertEqual(records.map(\.kind), [.focusCompleted], "no break and no extra focus minutes")
        XCTAssertEqual(records.first?.metadata[ActivityMetadata.outcome], "completed")
        XCTAssertEqual(try XCTUnwrap(records.first?.end).timeIntervalSince(started), 25 * 60, accuracy: 1,
                       "the focus ended when it ran out (records keep whole seconds)")
    }

    /// A heartbeat from the future (the clock was set back since) never
    /// credits time that has not happened yet.
    func testAHeartbeatAfterNowCreditsOnlyUpToNow() throws {
        var timer = FocusTimer()
        timer.start(at: Date().addingTimeInterval(-10 * 60))
        save(timer, lastAlive: Date().addingTimeInterval(3600))
        let log = ActivityLog(repository: nil)

        _ = launch(log: log)
        drainMainQueue()

        let records = logged(in: log)
        XCTAssertEqual(records.map(\.kind), [.focusCompleted])
        XCTAssertEqual(try XCTUnwrap(records.first?.quantity), 10, accuracy: 0.1)
        XCTAssertEqual(records.first?.metadata[ActivityMetadata.outcome], "abandoned")
    }

    // MARK: Demo

    func testTheDemoShowsARunningSessionAndSavesNothing() {
        let log = ActivityLog(repository: nil)
        let store = FocusStore(activity: log, runMode: RunMode(isDemo: true), defaults: defaults,
                               interruptions: (workspace, app))

        XCTAssertTrue(store.timer.isRunning)
        XCTAssertNotNil(store.timer.linkedItemID, "focusing on a sample task")
        XCTAssertEqual(store.sessionsToday, 2)

        store.toggleRunning()
        store.stop()
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertNil(defaults.data(forKey: FocusTimerStorage.timerKey), "nothing is saved")
        XCTAssertTrue(logged(in: log).isEmpty, "nothing is logged")
    }
}
