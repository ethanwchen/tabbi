import AppKit
import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Mac sleeping or Tabbi quitting mid-session ends the Pomodoro there:
/// the minutes focused go to the activity log, the pet is paid for them
/// once, and the stopped timer is saved, so nothing runs on or is paid in
/// full on the next launch.
@MainActor
final class FocusSessionInterruptionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    private let workspace = NotificationCenter()
    private let app = NotificationCenter()

    override func setUp() async throws {
        suite = "FocusSessionInterruptionTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusSessionInterruptionTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A focus or break phase that started `minutesAgo`, optionally paused now.
    private func saveTimer(minutesAgo: Double, paused: Bool = false, onBreak: Bool = false) {
        var timer = FocusTimer()
        let started = Date().addingTimeInterval(-minutesAgo * 60)
        timer.start(at: started)
        if onBreak { timer.skip(at: started) }
        if paused { timer.pause(at: Date()) }
        FocusTimerStorage(defaults: defaults).save(timer)
    }

    /// The Pomodoro, its activity log and the pet following its clock, as
    /// the app wires them through the provider snapshot.
    private func launch() -> (FocusStore, ActivityLog, ClosetStore) {
        let log = ActivityLog(repository: nil)
        let store = FocusStore(activity: log, runMode: .live, defaults: defaults, interruptions: (workspace, app))
        let closet = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        closet.follow(focus: store.$timer.map { $0.provided(by: FocusModule.descriptor.id) }.eraseToAnyPublisher())
        return (store, log, closet)
    }

    private var today: PlannerDayKey { PlannerDayKey(date: Date()) }

    func testSleepingMidFocusEndsTheSessionAndCreditsTheMinutesOnce() throws {
        saveTimer(minutesAgo: 10)
        let (store, log, closet) = launch()
        let balance = closet.closet.balance

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(store.timer.runState, .idle)
        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(FocusTimerStorage(defaults: defaults).loadTimer().runState, .idle, "the stop is saved")
        let logged = log.records(on: today)
        XCTAssertEqual(logged.map(\.kind), [.focusCompleted])
        XCTAssertEqual(try XCTUnwrap(logged.first?.quantity), 10, accuracy: 0.1)
        let paid = closet.closet.balance
        XCTAssertGreaterThan(paid, balance, "the pet is paid for the minutes focused")
        let save = try XCTUnwrap(PetSave.load(from: ClosetStore.saveURL(in: EditionStorage(root: folder))))
        XCTAssertEqual(save.ledger.balance, paid, "the points are on disk before the Mac sleeps")

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        app.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(log.records(on: today).count, 1, "another sleep or the quit after it credits nothing")
        XCTAssertEqual(closet.closet.balance, paid)
    }

    func testQuittingWhilePausedCreditsTheTimeFocusedBeforeThePause() throws {
        saveTimer(minutesAgo: 12, paused: true)
        let (store, log, closet) = launch()
        let balance = closet.closet.balance

        app.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertEqual(store.timer.runState, .idle)
        XCTAssertEqual(try XCTUnwrap(log.records(on: today).first?.quantity), 12, accuracy: 0.1)
        XCTAssertGreaterThan(closet.closet.balance, balance)

        let (relaunched, relaunchedLog, _) = launch()
        XCTAssertEqual(relaunched.timer.runState, .idle, "the next launch starts fresh")
        XCTAssertTrue(relaunchedLog.records(on: today).isEmpty, "and credits nothing again")
    }

    func testSleepingOnABreakEarnsNothingAndEndsTheBreak() {
        saveTimer(minutesAgo: 2, onBreak: true)
        let (store, log, closet) = launch()
        let balance = closet.closet.balance

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(store.timer.runState, .idle)
        XCTAssertEqual(store.timer.phase, .focus, "back to a fresh focus phase")
        XCTAssertTrue(log.records(on: today).isEmpty)
        XCTAssertEqual(closet.closet.balance, balance)
    }

    func testAnIdleTimerIsLeftAloneOnSleep() {
        let (store, log, _) = launch()
        let before = store.timer

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(store.timer, before)
        XCTAssertTrue(log.records(on: today).isEmpty)
    }
}
