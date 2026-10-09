import XCTest
import TabbiKitCore
@testable import Tabbi

/// What the Pomodoro store does to saved state at launch: a snapshot run
/// leaves it untouched, and the session log older builds kept is dropped
/// only once the activity log has it on disk.
@MainActor
final class FocusStoreStorageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUp() async throws {
        defaults = InMemoryDefaults()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusStoreStorageTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let legacy = FocusSessionLog(sessions: [.init(endedAt: Date().addingTimeInterval(-3600), duration: 1500)])

    private func saveLegacyLog() throws {
        defaults.set(try FocusTimerStorage.sessionLogSchema.encode(legacy), forKey: FocusTimerStorage.sessionLogKey)
    }

    /// A focus phase that ended an hour ago, so launching rolls it over.
    private func saveFinishedTimer() -> Data? {
        var timer = FocusTimer()
        timer.start(at: Date().addingTimeInterval(-2 * 3600))
        FocusTimerStorage(defaults: defaults).save(timer)
        return defaults.data(forKey: FocusTimerStorage.timerKey)
    }

    func testASnapshotRunLeavesSavedFocusStateAlone() throws {
        try saveLegacyLog()
        let saved = saveFinishedTimer()
        let log = ActivityLog(repository: nil)

        let store = FocusStore(activity: log, runMode: RunMode(isSnapshot: true), defaults: defaults)

        XCTAssertNotNil(defaults.data(forKey: FocusTimerStorage.sessionLogKey), "the legacy log survives")
        XCTAssertEqual(defaults.data(forKey: FocusTimerStorage.timerKey), saved, "the timer is not rewritten")
        XCTAssertTrue(log.records(on: PlannerDayKey(date: Date())).isEmpty, "nothing is logged")
        XCTAssertNotEqual(store.timer, FocusTimer(), "the snapshot still shows the saved timer")
    }

    func testTheLegacyLogStaysWhenTheActivityLogCannotSaveIt() throws {
        try saveLegacyLog()

        _ = FocusStore(activity: ActivityLog(repository: nil), runMode: .live, defaults: defaults)

        XCTAssertNotNil(defaults.data(forKey: FocusTimerStorage.sessionLogKey))
    }

    func testTheLegacyLogMovesIntoTheActivityLogOnDisk() throws {
        try saveLegacyLog()
        let repository = ActivityLogRepository(directory: folder)

        _ = FocusStore(activity: ActivityLog(repository: repository), runMode: .live, defaults: defaults)

        XCTAssertNil(defaults.data(forKey: FocusTimerStorage.sessionLogKey))
        let day = PlannerDayKey(date: legacy.sessions[0].endedAt)
        XCTAssertEqual(try repository.records(on: day).map(\.kind), [.focusCompleted])
    }

    /// The Focus tab's tally counts today's finished focus stretches, not
    /// the saved timer's all-time count, which never starts over, nor a
    /// focus stopped early, which earns minutes but is no finished session.
    func testTheSessionTallyCountsOnlyTodaysPomodoros() throws {
        FocusTimerStorage(defaults: defaults)
            .save(FocusTimer(phase: .focus, runState: .idle, config: FocusTimerConfig(), completedFocusCount: 41))
        let log = ActivityLog(repository: ActivityLogRepository(directory: folder))
        let now = Date()
        func focus(_ source: ModuleID, endingAt end: Date) -> ActivityRecord {
            ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-1500), end: end)
        }
        let stopped = try XCTUnwrap(FocusStop(focused: 600, endedAt: now, outcome: .abandoned)
            .activityRecord(source: FocusModule.descriptor.id))
        log.record([
            focus(FocusModule.descriptor.id, endingAt: now.addingTimeInterval(-86_400)),
            focus(FocusModule.descriptor.id, endingAt: now),
            focus(.study, endingAt: now),
            stopped,
            ActivityRecord(source: FocusModule.descriptor.id, kind: .breakTaken, start: now.addingTimeInterval(-300), end: now),
        ])

        let store = FocusStore(activity: log, runMode: .live, defaults: defaults)
        store.setVisible(true, viewer: .focus)

        XCTAssertEqual(store.sessionsToday, 1)
        XCTAssertEqual(store.timer.completedFocusCount, 41, "the saved count is left as it is")
    }

    func testStoppingMidFocusLogsTheMinutesFocusedAndEndsTheSession() throws {
        var timer = FocusTimer()
        timer.start(at: Date().addingTimeInterval(-10 * 60))
        FocusTimerStorage(defaults: defaults).save(timer)
        let log = ActivityLog(repository: nil)
        let store = FocusStore(activity: log, runMode: .live, defaults: defaults)

        store.stop()

        XCTAssertEqual(store.timer.runState, .idle)
        XCTAssertEqual(store.timer.phase, .focus)
        XCTAssertEqual(FocusTimerStorage(defaults: defaults).loadTimer().runState, .idle, "the stop is saved")
        let logged = log.records(on: PlannerDayKey(date: Date()))
        XCTAssertEqual(logged.map(\.kind), [.focusCompleted])
        XCTAssertEqual(try XCTUnwrap(logged.first?.quantity), 10, accuracy: 0.1)
        XCTAssertEqual(store.sessionsToday, 0, "a stopped focus is no finished session")

        store.stop()
        XCTAssertEqual(log.records(on: PlannerDayKey(date: Date())).count, 1, "a second stop credits nothing")
    }
}
