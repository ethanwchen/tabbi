import XCTest
import TabbiKitCore
@testable import Tabbi

/// A snapshot run must leave no trace, so rendering Today shows the saved
/// list (with yesterday's unfinished tasks carried over) without creating
/// today's file in the user's data folder.
@MainActor
final class PlannerSnapshotTraceTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("PlannerSnapshotTraceTests-\(UUID().uuidString)", isDirectory: true)
    private let today = PlannerDayKey(date: Date())
    private var repository: PlannerRepository { PlannerRepository(storage: EditionStorage(root: folder)) }

    /// Yesterday's list has one unfinished task, and today has no file yet.
    private func saveYesterday() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        var day = PlannerDay(date: PlannerDayKey(date: yesterday))
        day.add("Carry me", now: yesterday)
        try repository.save(day)
        addTeardownBlock { [folder] in try? FileManager.default.removeItem(at: folder) }
    }

    func testASnapshotRunShowsTodayWithoutSavingIt() throws {
        try saveYesterday()
        let store = PlannerStore(focus: FocusStore(runMode: .demo), storage: EditionStorage(root: folder),
                                 runMode: RunMode(isSnapshot: true))
        XCTAssertEqual(store.day.items.map(\.title), ["Carry me"])
        XCTAssertNil(try repository.load(today))

        store.add("Not saved")
        XCTAssertNil(try repository.load(today))
    }

    func testALiveRunCreatesToday() throws {
        try saveYesterday()
        _ = PlannerStore(focus: FocusStore(runMode: .demo), storage: EditionStorage(root: folder), runMode: .live)
        XCTAssertEqual(try repository.load(today)?.items.map(\.title), ["Carry me"])
    }
}
