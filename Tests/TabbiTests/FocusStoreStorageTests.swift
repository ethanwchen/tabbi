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
}
