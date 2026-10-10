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

    /// A live run as the user lives it: the card shows on the first open of
    /// the new week, and no close, reopen, dismiss or relaunch brings it back.
    func testTheRecapShowsOncePerWeekAcrossClosesAndRelaunches() throws {
        let log = ActivityLog(repository: nil)
        log.record([focus(day: 6, minutes: 25)])
        let monday = date(day: 12, 9)
        let moment = RecapMoment(store: store(log, at: monday))
        moment.start()
        defer { moment.stop() }

        moment.notchOpened()
        XCTAssertEqual(moment.shown?.recap.week, week)
        let saved = try XCTUnwrap(RecapArchive.load(from: RecapStore.saveURL(in: storage)))
        XCTAssertEqual(saved.seenWeek, week, "Seen is on disk the moment it shows, not on quit")

        moment.notchClosed()
        XCTAssertNil(moment.shown, "Closing counts as done")
        moment.notchOpened()
        XCTAssertNil(moment.shown, "Reopening shows the tabs")
        moment.notchClosed()

        let relaunched = RecapMoment(store: store(log, at: date(day: 14, 9)))
        relaunched.start()
        defer { relaunched.stop() }
        relaunched.notchOpened()
        XCTAssertNil(relaunched.shown, "Nor after a relaunch later that week")

        log.record([focus(day: 13, minutes: 30)])
        let nextWeek = RecapMoment(store: store(log, at: date(day: 19, 9)))
        nextWeek.start()
        defer { nextWeek.stop() }
        nextWeek.notchOpened()
        XCTAssertEqual(nextWeek.shown?.recap.focusMinutes, 30, "A newer week shows once")
        nextWeek.dismiss()
        nextWeek.notchOpened()
        XCTAssertNil(nextWeek.shown)
    }

    func testAfterWeeksAwayOnlyTheLatestWeekShowsAndNothingQueues() throws {
        let log = ActivityLog(repository: nil)
        log.record([focus(day: 6, minutes: 25)])
        let first = store(log, at: date(day: 12, 9))
        first.refresh() // built, never opened

        // Monday November 2, with activity only in the week before last.
        log.record([focus(day: 21, minutes: 40)])
        let moment = RecapMoment(store: store(log, at: calendar.date(byAdding: .day, value: 22, to: date(day: 11, 9))!))
        moment.notchOpened()
        XCTAssertNil(moment.shown, "Last week was empty, so no old card shows")
        XCTAssertNil(moment.store.unnotified)
        XCTAssertEqual(moment.store.archive.recaps.count, 2, "The skipped weeks stay in the list")
    }

    /// Two copies of the app on one edition (an installed build and a dev
    /// run): the one with an older copy in memory never unmarks a seen week.
    func testAStaleCopySavingNeverBringsBackASeenWeek() throws {
        let log = ActivityLog(repository: nil)
        log.record([focus(day: 6, minutes: 25)])
        let monday = date(day: 12, 9)
        let first = store(log, at: monday)
        first.refresh()
        let stale = store(log, at: monday)

        first.markSeen(week)
        stale.markNotified(week) // saves from a copy that never saw the mark

        let saved = try XCTUnwrap(RecapArchive.load(from: RecapStore.saveURL(in: storage)))
        XCTAssertEqual(saved.seenWeek, week)
        XCTAssertNil(stale.unseen, "The stale copy took in the mark too")
        XCTAssertNil(store(log, at: monday).unseen, "Nor does a relaunch show it")
    }

    func testTheNotificationGoesOutOnceWhenTheRecapIsBuilt() throws {
        let log = ActivityLog(repository: nil)
        log.record([focus(day: 6, minutes: 25), focus(day: 8, minutes: 50)])
        var notices: [RecapNotice] = []
        let moment = RecapMoment(store: store(log, at: date(day: 11, 19)), notify: { notices.append($0) })
        defer { moment.stop() }

        moment.start() // the Sunday evening build
        XCTAssertEqual(notices.map(\.body),
                       ["A lovely first week together. 1h 15m of focus. Open the notch to see your recap."])
        XCTAssertNotNil(moment.store.unseen, "The card still waits for the notch")

        moment.stop()
        moment.start()
        XCTAssertEqual(notices.count, 1, "Once per week")
        let relaunched = RecapMoment(store: store(log, at: date(day: 12, 9)), notify: { notices.append($0) })
        defer { relaunched.stop() }
        relaunched.start()
        XCTAssertEqual(notices.count, 1, "Not again after a relaunch")
    }

    func testNoNotificationForACardAlreadySeenOrWithRecapsOff() {
        let log = ActivityLog(repository: nil)
        log.record(focus(day: 6, minutes: 25))
        var notices: [RecapNotice] = []
        let moment = RecapMoment(store: store(log, at: date(day: 11, 19)), notify: { notices.append($0) })
        defer { moment.stop() }

        moment.setEnabled(false)
        moment.start()
        XCTAssertTrue(notices.isEmpty, "Recaps off posts nothing")

        moment.setEnabled(true)
        moment.notchOpened()
        XCTAssertNotNil(moment.shown)
        XCTAssertTrue(notices.isEmpty, "Opening the notch shows the card instead")
        moment.dismiss()
        moment.stop()
        moment.start()
        XCTAssertTrue(notices.isEmpty, "A seen card needs no notification")
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
