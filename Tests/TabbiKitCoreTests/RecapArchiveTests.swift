import XCTest
@testable import TabbiKitCore

final class RecapArchiveTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// October `day`, 2026 at `hour` o'clock in New York. October 5 is a Monday.
    private func date(day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func week(_ raw: String) -> RecapWeek { RecapWeek(start: PlannerDayKey(rawValue: raw)!, calendar: calendar)! }

    private func recap(_ week: RecapWeek, minutes: Int) -> WeeklyRecap {
        WeeklyRecap(week: week, minutesByDay: [minutes], sessions: minutes > 0 ? 1 : 0, cardsReviewed: 0,
                    tasksDone: 0, points: minutes, longestStreak: minutes > 0 ? 1 : 0)
    }

    // MARK: Which weeks to build

    func testFirstCheckCatchesUpOnRecentWeeksOldestFirst() {
        let weeks = RecapArchive().weeksToBuild(at: date(day: 11, 19), calendar: calendar)
        XCTAssertEqual(weeks, [week("2026-09-14"), week("2026-09-21"), week("2026-09-28"), week("2026-10-05")])
    }

    func testBeforeSundayEveningTheNewestWeekIsLastWeek() {
        XCTAssertEqual(RecapArchive().weeksToBuild(at: date(day: 11, 17), calendar: calendar).last, week("2026-09-28"))
    }

    func testAWeekBuiltOnSundayEveningIsBuiltAgainUntilItIsOver() {
        var archive = RecapArchive()
        let current = week("2026-10-05")
        archive.record(recap(current, minutes: 30), builtAt: date(day: 11, 19), calendar: calendar)
        XCTAssertEqual(archive.weeksToBuild(at: date(day: 11, 22), calendar: calendar).last, current,
                       "Sunday night focus still counts")

        archive.record(recap(current, minutes: 90), builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertEqual(archive.settledWeek, current)
        XCTAssertEqual(archive.weeksToBuild(at: date(day: 12, 10), calendar: calendar), [])
        XCTAssertEqual(archive.recaps.map(\.focusMinutes), [90], "The rebuild replaced the first build")
        XCTAssertEqual(archive.weeksToBuild(at: date(day: 18, 18), calendar: calendar), [week("2026-10-12")])
    }

    // MARK: Recording

    func testEmptyWeeksAreNeverKeptButStillSettle() {
        var archive = RecapArchive()
        let changed = archive.record(recap(week("2026-09-28"), minutes: 0), builtAt: date(day: 6, 9), calendar: calendar)
        XCTAssertTrue(changed)
        XCTAssertEqual(archive.recaps, [])
        XCTAssertNil(archive.unseen)
        XCTAssertEqual(archive.settledWeek, week("2026-09-28"))
        XCTAssertFalse(archive.record(recap(week("2026-09-28"), minutes: 0), builtAt: date(day: 6, 10),
                                      calendar: calendar), "Nothing changed, so nothing to save")
    }

    func testRecapsStayNewestFirstAndCatchUpDoesNotUnsettleNewerWeeks() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-10-05"), minutes: 50), builtAt: date(day: 12, 9), calendar: calendar)
        archive.record(recap(week("2026-09-21"), minutes: 70), builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertEqual(archive.recaps.map(\.week), [week("2026-10-05"), week("2026-09-21")])
        XCTAssertEqual(archive.settledWeek, week("2026-10-05"))
        XCTAssertEqual(archive.recap(for: week("2026-09-21"))?.focusMinutes, 70)
    }

    func testKeepsAtMostTwoYearsOfWeeks() {
        var archive = RecapArchive()
        var current = week("2026-10-05")
        for _ in 0..<(RecapArchive.capacity + 3) {
            archive.record(recap(current, minutes: 30), builtAt: date(day: 12, 9), calendar: calendar)
            current = current.adding(weeks: -1, calendar: calendar)
        }
        XCTAssertEqual(archive.recaps.count, RecapArchive.capacity)
        XCTAssertEqual(archive.recaps.first?.week, week("2026-10-05"), "The oldest fall off first")
    }

    // MARK: Showing and notifying once

    func testOnlyTheNewestRecapIsShownAndOnlyOnce() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-09-21"), minutes: 40), builtAt: date(day: 12, 9), calendar: calendar)
        archive.record(recap(week("2026-09-28"), minutes: 40), builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertEqual(archive.unseen?.week, week("2026-09-28"))

        XCTAssertTrue(archive.markSeen(week("2026-09-28")))
        XCTAssertNil(archive.unseen)
        XCTAssertFalse(archive.markSeen(week("2026-09-21")), "Seeing an older week changes nothing")

        archive.record(recap(week("2026-09-28"), minutes: 80), builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertNil(archive.unseen, "A rebuild of a seen week is not shown again")

        archive.record(recap(week("2026-10-05"), minutes: 10), builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertEqual(archive.unseen?.week, week("2026-10-05"))
    }

    func testAfterWeeksAwayOnlyTheWeekThatJustEndedShows() {
        var archive = RecapArchive(seenWeek: week("2026-09-07"))
        for start in ["2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"] {
            archive.record(recap(week(start), minutes: 30), builtAt: date(day: 13, 9), calendar: calendar)
        }
        XCTAssertTrue(archive.skipStaleWeeks(at: date(day: 13, 9), calendar: calendar))
        XCTAssertEqual(archive.unseen?.week, week("2026-10-05"), "One card, the newest week")
        XCTAssertEqual(archive.seenWeek, week("2026-09-28"), "Older weeks count as seen")
        XCTAssertEqual(archive.recaps.count, 4, "And stay in the list")
        XCTAssertFalse(archive.skipStaleWeeks(at: date(day: 14, 9), calendar: calendar), "Once per week")

        archive.markSeen(week("2026-10-05"))
        XCTAssertNil(archive.unseen, "Nothing queued behind it")
    }

    func testAnOldUnseenWeekDoesNotShowWhenTheLatestWeekWasEmpty() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-09-14"), minutes: 30), builtAt: date(day: 21, 9), calendar: calendar)
        archive.record(recap(week("2026-10-05"), minutes: 0), builtAt: date(day: 13, 9), calendar: calendar)
        archive.skipStaleWeeks(at: date(day: 13, 9), calendar: calendar)
        XCTAssertNil(archive.unseen, "A recap from a month ago never shows")
        XCTAssertNil(archive.unnotified)
        XCTAssertEqual(archive.recaps.map(\.week), [week("2026-09-14")])
    }

    func testOnSundayEveningLastWeekIsStaleAndThisWeekCanShow() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-09-28"), minutes: 30), builtAt: date(day: 11, 19), calendar: calendar)
        archive.record(recap(week("2026-10-05"), minutes: 30), builtAt: date(day: 11, 19), calendar: calendar)
        archive.skipStaleWeeks(at: date(day: 11, 19), calendar: calendar)
        XCTAssertEqual(archive.unseen?.week, week("2026-10-05"))
        XCTAssertEqual(archive.seenWeek, week("2026-09-28"))
    }

    func testMergingKeepsTheNewerMarkersSoASeenWeekNeverShowsAgain() {
        var here = RecapArchive(recaps: [recap(week("2026-10-05"), minutes: 30)],
                                settledWeek: week("2026-10-05"), seenWeek: week("2026-09-28"))
        let there = RecapArchive(recaps: [recap(week("2026-10-05"), minutes: 90), recap(week("2026-09-28"), minutes: 20)],
                                 settledWeek: week("2026-09-28"), seenWeek: week("2026-10-05"),
                                 notifiedWeek: week("2026-10-05"))
        XCTAssertTrue(here.merge(there))
        XCTAssertEqual(here.seenWeek, week("2026-10-05"))
        XCTAssertEqual(here.notifiedWeek, week("2026-10-05"))
        XCTAssertEqual(here.settledWeek, week("2026-10-05"))
        XCTAssertNil(here.unseen)
        XCTAssertEqual(here.recaps.map(\.week), [week("2026-10-05"), week("2026-09-28")])
        XCTAssertEqual(here.recap(for: week("2026-10-05"))?.focusMinutes, 30, "A week both have keeps this Mac's")

        let older = RecapArchive(seenWeek: week("2026-09-21"))
        XCTAssertFalse(here.merge(older), "An older marker never rolls seen back")
        XCTAssertEqual(here.seenWeek, week("2026-10-05"))
    }

    func testNotifiesOncePerWeekAndNotAfterItWasSeen() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-10-05"), minutes: 40), builtAt: date(day: 11, 19), calendar: calendar)
        XCTAssertEqual(archive.unnotified?.week, week("2026-10-05"))
        archive.markNotified(week("2026-10-05"))
        XCTAssertNil(archive.unnotified)
        XCTAssertEqual(archive.unseen?.week, week("2026-10-05"), "The notification does not count as seeing it")

        archive.record(recap(week("2026-10-12"), minutes: 40), builtAt: date(day: 18, 19), calendar: calendar)
        archive.markSeen(week("2026-10-12"))
        XCTAssertNil(archive.unnotified, "Already seen in the notch, so no notification")
    }

    func testCheerComparesAgainstSavedWeeks() {
        var archive = RecapArchive()
        archive.record(recap(week("2026-09-21"), minutes: 200), builtAt: date(day: 12, 9), calendar: calendar)
        archive.record(recap(week("2026-09-28"), minutes: 120), builtAt: date(day: 12, 9), calendar: calendar)
        let newest = recap(week("2026-10-05"), minutes: 300)
        archive.record(newest, builtAt: date(day: 12, 9), calendar: calendar)
        XCTAssertEqual(archive.cheer(for: newest, calendar: calendar), .bestYet)
        XCTAssertEqual(archive.cheer(for: archive.recap(for: week("2026-09-28"))!, calendar: calendar), .steady)
    }

    // MARK: Persistence

    func testRoundTripsThroughAVersionedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = RecapArchive.fileURL(in: directory)
        XCTAssertNil(try RecapArchive.load(from: url))

        var archive = RecapArchive()
        archive.record(recap(week("2026-10-05"), minutes: 45), builtAt: date(day: 12, 9), calendar: calendar)
        archive.markSeen(week("2026-10-05"))
        archive.markNotified(week("2026-10-05"))
        try archive.write(to: url)

        XCTAssertEqual(VersionedJSON.version(of: try Data(contentsOf: url)), RecapArchive.schema.current)
        XCTAssertEqual(try RecapArchive.load(from: url), archive)
    }

    func testDecodingDropsEmptyAndDuplicateWeeksAndToleratesBadMarkers() throws {
        let json = """
        {"recaps": [
          {"week": "2026-09-28", "minutesByDay": [30], "sessions": 1, "cardsReviewed": 0, "tasksDone": 0,
           "points": 30, "longestStreak": 1},
          {"week": "2026-10-05", "minutesByDay": [0], "sessions": 0, "cardsReviewed": 0, "tasksDone": 0,
           "points": 0, "longestStreak": 0},
          {"week": "2026-09-28", "minutesByDay": [99], "sessions": 1, "cardsReviewed": 0, "tasksDone": 0,
           "points": 99, "longestStreak": 1}
        ], "seenWeek": 12}
        """
        let archive = try RecapArchive.schema.decode(RecapArchive.self, from: Data(json.utf8))
        XCTAssertEqual(archive.recaps.map(\.week), [week("2026-09-28")])
        XCTAssertEqual(archive.recaps.first?.focusMinutes, 30)
        XCTAssertNil(archive.seenWeek)
        XCTAssertEqual(archive.unseen?.week, week("2026-09-28"))
    }

    func testACorruptFileThrowsInsteadOfLookingEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = RecapArchive.fileURL(in: directory)
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try RecapArchive.load(from: url))
    }

    // MARK: Demo

    func testDemoEndsOnAnUnseenBestWeekWithALightWeekAmongThem() throws {
        let archive = RecapArchive.demo(now: date(day: 11, 19), calendar: calendar)
        let newest = try XCTUnwrap(archive.unseen)
        XCTAssertEqual(newest.week, week("2026-10-05"))
        XCTAssertEqual(archive.cheer(for: newest, calendar: calendar), .bestYet)
        XCTAssertTrue(archive.recaps.contains { archive.cheer(for: $0, calendar: calendar) == .light })
    }
}
