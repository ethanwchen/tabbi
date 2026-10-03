import Combine
import XCTest
import NotchKitCore
@testable import NotchDeck

@MainActor
final class ActivityLogServiceTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityLogServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        unsetenv("NOTCHDECK_DEMO")
    }

    private var today: PlannerDayKey { PlannerDayKey(date: Date()) }

    private func record(_ kind: ActivityKind, source: ModuleID = .focus) -> ActivityRecord {
        ActivityRecord(source: source, kind: kind, start: Date(), quantity: 1)
    }

    func testFollowersHearEachRecordAndReadersSeeIt() {
        let log = ActivityLog(repository: nil)
        var heard: [ActivityKind] = []
        let subscription = log.recorded.sink { heard.append($0.kind) }
        log.record([record(.focusCompleted), record(.breakTaken)])
        XCTAssertEqual(heard, [.focusCompleted, .breakTaken])
        XCTAssertEqual(log.records(on: today).map(\.kind), [.focusCompleted, .breakTaken])
        subscription.cancel()
    }

    func testRecordsOutliveTheRun() {
        let first = ActivityLog(repository: ActivityLogRepository(directory: folder))
        let done = record(.taskCompleted, source: .planner)
        first.record(done)
        let relaunched = ActivityLog(repository: ActivityLogRepository(directory: folder))
        XCTAssertEqual(relaunched.records(on: today), [done])
    }

    func testRecordsADayFileRefusesStillReadBackThisRun() throws {
        let repository = ActivityLogRepository(directory: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: repository.fileURL(for: today))
        let log = ActivityLog(repository: repository)
        let done = record(.taskCompleted, source: .planner)
        log.record(done)
        XCTAssertEqual(log.records(on: today), [done])
    }

    func testEveryModuleSharesOneLog() {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        let shared = SharedServices()
        func context(_ id: ModuleID) -> ModuleContext {
            ModuleContext(id: id, edition: .notchDeck, settings: settings, providers: ProviderHub(), shared: shared,
                          runMode: .demo)
        }
        XCTAssertTrue(context(.focus).activityLog === context(.study).activityLog)
    }

    func testCheckingATaskOffLogsIt() throws {
        setenv("NOTCHDECK_DEMO", "1", 1)
        let log = ActivityLog(repository: nil)
        let store = PlannerStore(focus: FocusStore(runMode: .demo), storage: EditionStorage(root: folder), activity: log,
                                 runMode: .demo)
        let open = try XCTUnwrap(store.day.items.first { !$0.isDone })

        store.toggle(open.id)
        let logged = log.records(on: today)
        XCTAssertEqual(logged.map(\.kind), [.taskCompleted])
        XCTAssertEqual(logged.first?.source, .planner)
        XCTAssertEqual(logged.first?.subject, open.id.uuidString)

        // Unchecking logs nothing; checking it again logs the same subject.
        store.toggle(open.id)
        XCTAssertEqual(log.records(on: today).count, 1)
        store.toggle(open.id)
        XCTAssertEqual(log.records(on: today).map(\.subject), [open.id.uuidString, open.id.uuidString])
    }
}
