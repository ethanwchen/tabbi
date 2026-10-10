import XCTest
import TabbiKitCore
@testable import Tabbi

@MainActor
final class RecapStoreTests: XCTestCase {
    private var folder: URL!
    private var storage: EditionStorage { EditionStorage(root: folder) }
    /// The activity log files days by the Mac's own calendar, so the tests do too.
    private let calendar = Calendar.current

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecapStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// October `day`, 2026 at `hour` o'clock. October 5 is a Monday.
    private func date(day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private var week: RecapWeek { RecapWeek(containing: date(day: 5, 12), calendar: calendar) }

    private func focus(day: Int, minutes: Double) -> ActivityRecord {
        let end = date(day: day, 10)
        return ActivityRecord(source: .focus, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes,
                              metadata: [ActivityMetadata.outcome: StudyPhaseOutcome.completed.rawValue])
    }

    private func store(_ log: ActivityLog, at now: Date, runMode: RunMode = .live) -> RecapStore {
        RecapStore(storage: storage, runMode: runMode, activity: log, calendar: calendar, now: { now })
    }

    func testSundayEveningBuildsTheWeekFromTheLogAndShowsItOnce() throws {
        let log = ActivityLog(repository: ActivityLogRepository(directory: folder.appendingPathComponent("Activity")))
        log.record([focus(day: 6, minutes: 25), focus(day: 8, minutes: 50)])

        let early = store(log, at: date(day: 11, 17))
        early.refresh()
        XCTAssertNil(early.unseen, "Not ready before Sunday 6 pm")

        let ready = store(log, at: date(day: 11, 19))
        ready.refresh()
        let recap = try XCTUnwrap(ready.unseen)
        XCTAssertEqual(recap.week, week)
        XCTAssertEqual(recap.focusMinutes, 75)
        XCTAssertEqual(recap.sessions, 2)
        XCTAssertEqual(ready.cheer(for: recap), .firstWeek)
        XCTAssertEqual(ready.unnotified?.week, week)

        ready.markSeen(recap.week)
        XCTAssertNil(ready.unseen)
        let relaunched = store(log, at: date(day: 12, 9))
        XCTAssertEqual(relaunched.archive.recaps.map(\.week), [week], "Saved for the list of past recaps")
        XCTAssertNil(relaunched.unseen, "Seen stays seen after a relaunch")
        XCTAssertNil(relaunched.unnotified)
    }

    func testSundayNightFocusStillCountsUntilTheWeekIsOver() {
        let log = ActivityLog(repository: nil)
        log.record(focus(day: 6, minutes: 25))
        let evening = store(log, at: date(day: 11, 19))
        evening.refresh()
        XCTAssertEqual(evening.nextBuildDate, date(day: 12, 0), "Wakes at midnight to settle the week")

        log.record(ActivityRecord(source: .focus, kind: .focusCompleted, start: date(day: 11, 21),
                                  end: date(day: 11, 22), quantity: 60, unit: .minutes))
        let night = store(log, at: date(day: 12, 0))
        night.refresh()
        XCTAssertEqual(night.archive.recap(for: week)?.focusMinutes, 85)
        XCTAssertEqual(night.nextBuildDate, date(day: 18, 18), "Then next Sunday evening")
    }

    func testAnEmptyWeekLeavesNoCard() {
        let empty = store(ActivityLog(repository: nil), at: date(day: 11, 19))
        empty.refresh()
        XCTAssertTrue(empty.archive.recaps.isEmpty)
        XCTAssertNil(empty.unseen)
    }

    func testSnapshotRunsNeitherReadNorWriteTheFile() throws {
        let url = RecapStore.saveURL(in: storage)
        try RecapArchive(recaps: [WeeklyRecap(week: week, minutesByDay: [30], sessions: 1, cardsReviewed: 0,
                                              tasksDone: 0, points: 3, longestStreak: 1)]).write(to: url)
        let before = try Data(contentsOf: url)

        let log = ActivityLog(repository: nil)
        log.record(focus(day: 6, minutes: 25))
        let snapshot = store(log, at: date(day: 18, 19), runMode: RunMode(isSnapshot: true))
        XCTAssertTrue(snapshot.archive.recaps.isEmpty)
        snapshot.refresh()
        snapshot.markSeen(week)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testDemoShowsSampleRecapsAndBuildsNothing() throws {
        let demo = store(ActivityLog(repository: nil), at: date(day: 11, 19), runMode: .demo)
        demo.refresh()
        let newest = try XCTUnwrap(demo.unseen)
        XCTAssertEqual(newest.week, week)
        XCTAssertEqual(demo.cheer(for: newest), .bestYet)
        XCTAssertGreaterThan(demo.archive.recaps.count, 1)
        demo.markSeen(newest.week)
        XCTAssertFalse(FileManager.default.fileExists(atPath: RecapStore.saveURL(in: storage).path))
    }

    func testAnUnreadableFileIsNeverOverwritten() throws {
        let url = RecapStore.saveURL(in: storage)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: url)

        let log = ActivityLog(repository: nil)
        log.record(focus(day: 6, minutes: 25))
        let recaps = store(log, at: date(day: 11, 19))
        recaps.refresh()
        XCTAssertEqual(recaps.unseen?.focusMinutes, 25, "Still shows this run's recap")
        XCTAssertEqual(try Data(contentsOf: url), Data("garbage".utf8))
    }

    func testEveryModuleSharesOneRecapStore() {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        let shared = SharedServices()
        func context(_ id: ModuleID) -> ModuleContext {
            ModuleContext(id: id, edition: .tabbi, settings: settings, providers: ProviderHub(), shared: shared,
                          runMode: .demo)
        }
        XCTAssertTrue(context(.closet).weeklyRecaps === context(.planner).weeklyRecaps)
    }
}
