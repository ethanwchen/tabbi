import AppKit
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A Study session still under way at launch means Tabbi crashed or the
/// Mac lost power: it ends at the last heartbeat, its minutes reach the
/// activity log and the pet once, and the next launch starts fresh.
@MainActor
final class StudySessionRecoveryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!
    private let workspace = NotificationCenter()
    private let app = NotificationCenter()

    override func setUp() async throws {
        suite = "StudySessionRecoveryTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudySessionRecoveryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A Pomodoro focus block that started `minutesAgo`, saved as the app saves it.
    private func saveSession(minutesAgo: Double) throws {
        var session = StudySession(method: .pomodoro)
        session.start(at: Date().addingTimeInterval(-minutesAgo * 60))
        defaults.set(try JSONEncoder().encode(session), forKey: "study.session")
    }

    /// The Study timer, its activity log and the pet paying from the log.
    private func launch() -> (StudyStore, ActivityLog, ClosetStore) {
        let log = ActivityLog(repository: nil)
        let store = StudyStore(storage: EditionStorage(root: folder), activity: log, runMode: .live,
                               defaults: defaults, interruptions: (workspace, app))
        let closet = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        closet.follow(activity: log.recorded)
        return (store, log, closet)
    }

    /// Waits for the records the store logs on the next main-queue turn.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private var today: PlannerDayKey { PlannerDayKey(date: Date()) }

    func testRelaunchingAfterACrashCreditsTheBlockUpToTheLastHeartbeatOnce() throws {
        try saveSession(minutesAgo: 20)
        defaults.set(Date().addingTimeInterval(-6 * 60), forKey: StudyStore.lastAliveKey)
        let (store, log, closet) = launch()
        let balance = closet.closet.balance
        drainMainQueue()

        XCTAssertEqual(store.session.runState, .idle, "the crashed block is not resumed")
        let logged = log.records(on: today)
        XCTAssertEqual(logged.map(\.kind), [.focusCompleted])
        XCTAssertEqual(try XCTUnwrap(logged.first?.quantity), 14, accuracy: 0.1, "credited up to the heartbeat")
        XCTAssertEqual(store.today.minutes, 14, "and counted as study time today")
        let paid = closet.closet.balance
        XCTAssertEqual(paid, balance + 14)

        // Crashing again before anything else happens credits nothing more.
        let (relaunched, relaunchedLog, relaunchedCloset) = launch()
        drainMainQueue()
        XCTAssertEqual(relaunched.session.runState, .idle)
        XCTAssertTrue(relaunchedLog.records(on: today).isEmpty)
        XCTAssertEqual(relaunchedCloset.closet.balance, paid)
    }

    func testSleepingMidBlockCreditsItAndTheNextLaunchStartsFresh() throws {
        try saveSession(minutesAgo: 10)
        let (store, log, closet) = launch()
        let balance = closet.closet.balance
        drainMainQueue()

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(store.session.runState, .idle)
        XCTAssertEqual(try XCTUnwrap(log.records(on: today).first?.quantity), 10, accuracy: 0.1)
        XCTAssertEqual(closet.closet.balance, balance + 10)
        let (relaunched, relaunchedLog, _) = launch()
        drainMainQueue()
        XCTAssertEqual(relaunched.session.runState, .idle)
        XCTAssertTrue(relaunchedLog.records(on: today).isEmpty, "the stop is saved, so nothing is credited again")
    }

    func testRunningBlocksSaveAHeartbeat() throws {
        let (store, _, _) = launch()
        let before = Date()
        store.primaryAction()
        XCTAssertEqual(store.session.runState, .running)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(defaults.object(forKey: StudyStore.lastAliveKey) as? Date), before)
    }
}
