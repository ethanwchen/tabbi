import XCTest
import Combine
import UserNotifications
import TabbiKitCore
@testable import Tabbi

/// The daily study reminder through `StudyReminderScheduler`: what it asks
/// the notification center for when the user turns it on, moves its time or
/// meets the day's goal, what it saves so a relaunch never sends a second
/// reminder the same day, and what demo and snapshot runs leave alone.
///
/// A fake center stands in for `UNUserNotificationCenter`, and the clock is
/// fixed at 10:00 two days from now, so every planned moment (and the
/// scheduler's own wall-clock alarm) lies in the future.
@MainActor
final class StudyReminderSchedulerTests: XCTestCase {
    private var folder: URL!
    private var storage: EditionStorage { EditionStorage(root: folder) }
    private var saveURL: URL { StudyReminderScheduler.saveURL(in: storage) }
    private var center: FakeReminderCenter!
    private var progress: CurrentValueSubject<[ProgressItem], Never>!
    private var now = Date()
    private var schedulers: [StudyReminderScheduler] = []
    private let calendar = Calendar.current

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyReminderSchedulerTests-\(UUID().uuidString)", isDirectory: true)
        center = FakeReminderCenter()
        progress = CurrentValueSubject([])
        now = at(hour: 10, minute: 0, daysAhead: 2)
    }

    override func tearDown() async throws {
        schedulers.forEach { $0.stop() }
        schedulers = []
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Helpers

    private func at(hour: Int, minute: Int, daysAhead: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func makeScheduler(_ runMode: RunMode = .live) -> StudyReminderScheduler {
        let pet = ClosetStore(storage: storage, runMode: runMode, starter: .starter(.cat))
        let scheduler = StudyReminderScheduler(
            storage: storage, runMode: runMode, pet: pet,
            progress: progress.eraseToAnyPublisher(),
            notifications: center,
            clock: { [unowned self] in now }
        )
        schedulers.append(scheduler)
        return scheduler
    }

    private func goal(met: Bool) -> ProgressItem {
        ProgressItem(id: StudyDailyGoal.progressID, source: "study", title: "Focus time",
                     completed: met ? 60 : 20, target: 60, unit: "min")
    }

    /// Waits past the scheduler's 200 ms debounce until `condition` holds.
    private func waitUntil(_ message: String, timeout: TimeInterval = 3,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("Timed out waiting: \(message)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Lets any debounced plan run, for checks that nothing happened.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(450))
    }

    private func pendingFireDate() -> DateComponents? {
        (center.pending[StudyReminderScheduler.requestID]?.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }

    private func components(of date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func savedOnDisk() throws -> StudyReminderSave? {
        try StudyReminderSave.load(from: saveURL)
    }

    // MARK: Tests

    func testFreshInstallIsOffPostsNothingAndWritesNothing() async throws {
        let reminder = makeScheduler()
        reminder.start()
        try await waitUntil("the first plan withdraws any stale reminder") { center.withdrawn > 0 }

        XCTAssertFalse(reminder.isEnabled)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.authorizationRequests, 0, "Permission is asked only when the user turns the reminder on")
        XCTAssertFalse(reminder.isBlocked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path))
    }

    func testTurningOnAsksPermissionOnceAndSetsOneReminderTodayAtSeven() async throws {
        center.status = .notDetermined
        center.grantsOnRequest = true
        let reminder = makeScheduler()
        reminder.start()

        reminder.setEnabled(true)
        try await waitUntil("a reminder is pending") { pendingFireDate() != nil }
        try await settle()

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertEqual(pendingFireDate(), components(of: at(hour: 19, minute: 0, daysAhead: 2)))
        XCTAssertEqual(center.pending.count, 1)
        let content = try XCTUnwrap(center.pending[StudyReminderScheduler.requestID]?.content)
        XCTAssertEqual(content.title, "Your cat misses you", "A cat still named after its breed speaks as 'Your cat'")
        XCTAssertEqual(content.body, "10 minutes?")
        XCTAssertFalse(reminder.isBlocked)

        let saved = try XCTUnwrap(try savedOnDisk())
        XCTAssertTrue(saved.settings.isEnabled)
        XCTAssertEqual(saved.scheduledFor, at(hour: 19, minute: 0, daysAhead: 2))
        XCTAssertNil(saved.lastDelivered)
    }

    func testAlreadyDecidedPermissionIsNeverAskedAgain() async throws {
        center.status = .authorized
        let reminder = makeScheduler()
        reminder.start()

        reminder.setEnabled(true)
        try await waitUntil("a reminder is pending") { pendingFireDate() != nil }
        try await settle()

        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertFalse(reminder.isBlocked)
    }

    func testDeniedNotificationsShowAsBlockedUntilTheReminderIsTurnedOff() async throws {
        center.status = .denied
        let reminder = makeScheduler()
        reminder.start()

        reminder.setEnabled(true)
        try await waitUntil("the blocked row shows") { reminder.isBlocked }
        XCTAssertEqual(center.authorizationRequests, 0, "A user who said no is pointed to System Settings, not asked again")

        reminder.setEnabled(false)
        XCTAssertFalse(reminder.isBlocked)
        try await waitUntil("the pending reminder is withdrawn") { center.pending.isEmpty }
        XCTAssertEqual(try savedOnDisk()?.settings.isEnabled, false)
        XCTAssertNil(try savedOnDisk()?.scheduledFor)
    }

    func testMovingTheTimeReplacesThePendingReminder() async throws {
        center.status = .authorized
        let reminder = makeScheduler()
        reminder.start()
        reminder.setEnabled(true)
        try await waitUntil("the 7 pm reminder is pending") { pendingFireDate()?.hour == 19 }

        reminder.time = at(hour: 21, minute: 30, daysAhead: 0)
        try await waitUntil("the reminder moves to 9:30 pm") { pendingFireDate()?.hour == 21 }

        XCTAssertEqual(pendingFireDate(), components(of: at(hour: 21, minute: 30, daysAhead: 2)))
        XCTAssertEqual(center.pending.count, 1, "The day never gets two reminders")
        XCTAssertEqual(center.scheduled, 2)
        XCTAssertEqual(reminder.time, at(hour: 21, minute: 30, daysAhead: 2), "The picker shows the time on the clock's day")
        XCTAssertEqual(try savedOnDisk()?.settings.minuteOfDay, 21 * 60 + 30)
    }

    func testMeetingTheDaysGoalMovesTheReminderToTomorrow() async throws {
        center.status = .authorized
        progress.send([goal(met: false)])
        let reminder = makeScheduler()
        reminder.start()
        reminder.setEnabled(true)
        try await waitUntil("today's reminder is pending") {
            pendingFireDate() == components(of: at(hour: 19, minute: 0, daysAhead: 2))
        }

        progress.send([goal(met: true)])
        try await waitUntil("the reminder skips to tomorrow") {
            pendingFireDate() == components(of: at(hour: 19, minute: 0, daysAhead: 3))
        }
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertEqual(try savedOnDisk()?.scheduledFor, at(hour: 19, minute: 0, daysAhead: 3))
    }

    func testARelaunchAfterTheReminderFiredCountsItAsDeliveredAndNeverSendsASecond() async throws {
        let fired = at(hour: 19, minute: 0, daysAhead: 2)
        try StudyReminderSave(settings: StudyReminderSettings(isEnabled: true), scheduledFor: fired).write(to: saveURL)
        center.status = .authorized
        now = at(hour: 20, minute: 0, daysAhead: 2)

        let reminder = makeScheduler()
        reminder.start()
        try await waitUntil("tomorrow's reminder is pending") {
            pendingFireDate() == components(of: at(hour: 19, minute: 0, daysAhead: 3))
        }
        XCTAssertEqual(try savedOnDisk()?.lastDelivered, fired)

        // Moving the time later the same evening still waits for tomorrow.
        reminder.time = at(hour: 22, minute: 0, daysAhead: 0)
        try await waitUntil("the new time applies tomorrow") {
            pendingFireDate() == components(of: at(hour: 22, minute: 0, daysAhead: 3))
        }
    }

    func testStoppingKeepsThePendingReminderAndStopsFollowingChanges() async throws {
        center.status = .authorized
        let reminder = makeScheduler()
        reminder.start()
        reminder.setEnabled(true)
        try await waitUntil("a reminder is pending") { pendingFireDate() != nil }
        try await settle()
        let withdrawn = center.withdrawn

        reminder.stop()
        progress.send([goal(met: true)])
        reminder.time = at(hour: 8, minute: 0, daysAhead: 0)
        try await settle()

        XCTAssertEqual(center.withdrawn, withdrawn, "Quitting Tabbi must not withdraw the reminder the system delivers")
        XCTAssertEqual(pendingFireDate()?.hour, 19)
        XCTAssertEqual(try savedOnDisk()?.settings.minuteOfDay, 8 * 60, "Settings still save while stopped")
    }

    func testAnUnreadableSaveRunsOnDefaultsAndIsNeverOverwritten() async throws {
        try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("not a reminder save".utf8)
        try garbage.write(to: saveURL)
        center.status = .authorized
        let reminder = makeScheduler()
        reminder.start()

        XCTAssertFalse(reminder.isEnabled)
        reminder.setEnabled(true)
        reminder.time = at(hour: 18, minute: 0, daysAhead: 0)
        try await waitUntil("the reminder still works this session") { pendingFireDate()?.hour == 18 }

        XCTAssertEqual(try Data(contentsOf: saveURL), garbage)
    }

    func testDemoAndSnapshotRunsNeverTouchNotificationsOrTheSave() async throws {
        try StudyReminderSave(settings: StudyReminderSettings(isEnabled: false, hour: 6, minute: 0)).write(to: saveURL)
        let before = try Data(contentsOf: saveURL)

        let demo = makeScheduler(.demo)
        XCTAssertTrue(demo.isEnabled, "Demo shows the reminder on")
        XCTAssertEqual(demo.time, at(hour: 19, minute: 0, daysAhead: 2), "Demo never reads the user's save")
        let snapshot = makeScheduler(RunMode(isSnapshot: true))
        XCTAssertFalse(snapshot.isEnabled)

        for reminder in [demo, snapshot] {
            reminder.start()
            reminder.setEnabled(true)
            reminder.time = at(hour: 7, minute: 15, daysAhead: 0)
            XCTAssertFalse(reminder.isBlocked)
        }
        try await settle()

        XCTAssertEqual(center.calls, 0)
        XCTAssertEqual(try Data(contentsOf: saveURL), before)
    }
}

/// Records what the scheduler asks of the notification center, keeping
/// pending requests by id as the real one does.
@MainActor
private final class FakeReminderCenter: StudyReminderNotifying {
    var status: UNAuthorizationStatus = .authorized
    var grantsOnRequest = false
    private(set) var pending: [String: UNNotificationRequest] = [:]
    private(set) var authorizationRequests = 0
    private(set) var withdrawn = 0
    private(set) var scheduled = 0
    private(set) var statusChecks = 0
    var calls: Int { authorizationRequests + withdrawn + scheduled + statusChecks }

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusChecks += 1
        return status
    }

    func requestAuthorization() async {
        authorizationRequests += 1
        status = grantsOnRequest ? .authorized : .denied
    }

    func withdraw(id: String) {
        withdrawn += 1
        pending[id] = nil
    }

    func schedule(_ request: UNNotificationRequest) {
        scheduled += 1
        pending[request.identifier] = request
    }
}
