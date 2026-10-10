import XCTest
import TabbiKitCore

final class PlannerDayKeyTests: XCTestCase {
    func testFormatsLocalDayInCalendarTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 2026-10-02 03:00 UTC is still Oct 1 in Los Angeles.
        let date = Date(timeIntervalSince1970: 1_790_910_000)
        XCTAssertEqual(PlannerDayKey(date: date, calendar: calendar).rawValue, "2026-10-01")
    }

    func testRejectsMalformedAndImpossibleDates() {
        XCTAssertNotNil(PlannerDayKey(rawValue: "2028-02-29"))
        XCTAssertNil(PlannerDayKey(rawValue: "2026-02-30"))
        XCTAssertNil(PlannerDayKey(rawValue: "2026-1-01"))
        XCTAssertNil(PlannerDayKey(rawValue: "notes"))
    }

    func testStartDateRoundTripsAndSortsChronologically() {
        let key = PlannerDayKey(rawValue: "2026-10-01")!
        XCTAssertEqual(PlannerDayKey(date: key.startDate()), key)
        XCTAssertLessThan(PlannerDayKey(rawValue: "2026-09-30")!, key)
    }
}

final class PlannerDayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var day = PlannerDay(date: PlannerDayKey(rawValue: "2026-10-01")!)

    func testAddTrimsAndRejectsBlankTitles() {
        XCTAssertNil(day.add("   \n"))
        let item = day.add("  Ship   the\nrelease ", now: now)
        XCTAssertEqual(item?.title, "Ship the release")
        XCTAssertEqual(item?.createdAt, now)
        XCTAssertEqual(day.items.map(\.title), ["Ship the release"])
    }

    func testToggleStampsAndClearsCompletion() throws {
        let id = try XCTUnwrap(day.add("Run")).id
        day.toggle(id, now: now)
        XCTAssertTrue(day.items[0].isDone)
        XCTAssertEqual(day.items[0].completedAt, now)
        XCTAssertEqual(day.progress, 1)
        day.toggle(id, now: now)
        XCTAssertFalse(day.items[0].isDone)
        XCTAssertNil(day.items[0].completedAt)
        XCTAssertEqual(day.doneCount, 0)
    }

    func testRenameIgnoresBlankAndUnchangedTitles() throws {
        let id = try XCTUnwrap(day.add("Draft")).id
        XCTAssertFalse(day.rename(id, to: "  "))
        XCTAssertFalse(day.rename(id, to: "Draft"))
        XCTAssertTrue(day.rename(id, to: " Final draft "))
        XCTAssertEqual(day.items[0].title, "Final draft")
    }

    func testDeleteAndClearCompleted() throws {
        let a = try XCTUnwrap(day.add("A")).id
        let b = try XCTUnwrap(day.add("B")).id
        day.add("C")
        day.delete(a)
        day.toggle(b)
        day.clearCompleted()
        XCTAssertEqual(day.items.map(\.title), ["C"])
    }

    func testMoveMatchesArrayMoveSemantics() {
        for title in ["A", "B", "C", "D"] { day.add(title) }
        day.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(day.items.map(\.title), ["B", "C", "A", "D"])
        day.move(fromOffsets: [1, 3], toOffset: 0)
        XCTAssertEqual(day.items.map(\.title), ["C", "D", "B", "A"])
        day.move(fromOffsets: [0], toOffset: 99)
        XCTAssertEqual(day.items.map(\.title), ["D", "B", "A", "C"])
    }

    func testMoveByIDPlacesItemAtTargetIndex() throws {
        for title in ["A", "B", "C"] { day.add(title) }
        day.move(day.items[2].id, to: 0)
        XCTAssertEqual(day.items.map(\.title), ["C", "A", "B"])
        day.move(day.items[0].id, to: 2)
        XCTAssertEqual(day.items.map(\.title), ["A", "B", "C"])
    }

    func testAddingDaysStepsAcrossMonthEndsAndDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let oct31 = try XCTUnwrap(PlannerDayKey(rawValue: "2026-10-31"))
        // Clocks go back on Nov 1, 2026 in Los Angeles, a 25-hour day.
        XCTAssertEqual(oct31.adding(days: 1, calendar: calendar).rawValue, "2026-11-01")
        XCTAssertEqual(oct31.adding(days: 2, calendar: calendar).rawValue, "2026-11-02")
        XCTAssertEqual(oct31.adding(days: 2, calendar: calendar).adding(days: -2, calendar: calendar), oct31)
        XCTAssertEqual(try XCTUnwrap(PlannerDayKey(rawValue: "2026-03-01")).adding(days: -1, calendar: calendar).rawValue,
                       "2026-02-28")
    }

    func testUnfinishedMissingFromListsOnlyOpenItemsTheOtherDayLacks() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var yesterday = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-30")!)
        let carried = try XCTUnwrap(yesterday.add("Carried", now: now))
        let left = try XCTUnwrap(yesterday.add("Left behind", now: now))
        let done = try XCTUnwrap(yesterday.add("Done", now: now))
        yesterday.toggle(done.id, now: now)
        let today = PlannerDay(date: PlannerDayKey(rawValue: "2026-10-01")!, items: [carried])

        XCTAssertEqual(yesterday.unfinished(missingFrom: today), [left])
    }

    func testUnfinishedMissingFromSkipsTitlesTheOtherDayAlreadyHas() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var yesterday = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-30")!)
        yesterday.add("Call the dentist", now: now)
        var today = PlannerDay(date: PlannerDayKey(rawValue: "2026-10-01")!)
        today.add("call the DENTIST", now: now)

        // Exactly what `adopt` would add, so a leftover is never offered and then skipped.
        XCTAssertEqual(yesterday.unfinished(missingFrom: today), [])
        XCTAssertEqual(today.adopt(yesterday.items), [])
    }

    func testAdoptKeepsIdentityAndSkipsDuplicates() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var yesterday = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-30")!)
        let left = try XCTUnwrap(yesterday.add("Left behind", now: now))
        let twin = try XCTUnwrap(yesterday.add("Already there", now: now))
        var today = PlannerDay(date: PlannerDayKey(rawValue: "2026-10-01")!)
        today.add("already THERE", now: now)

        XCTAssertEqual(today.adopt([left, twin, left]), [left])
        XCTAssertEqual(today.items.map(\.title), ["already THERE", "Left behind"])
        XCTAssertEqual(today.items.last?.id, left.id)
        XCTAssertEqual(today.items.last?.createdAt, now)
        XCTAssertEqual(today.adopt([left]), [])
    }

    func testProgressIsZeroWhenEmpty() {
        XCTAssertEqual(day.progress, 0)
    }
}

final class PlannerRepositoryTests: XCTestCase {
    private var directory: URL!
    private var repository: PlannerRepository!
    private let oct1 = PlannerDayKey(rawValue: "2026-10-01")!
    // Whole seconds: the JSON format stores ISO-8601 without fractions.
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlannerTests-\(UUID().uuidString)", isDirectory: true)
        repository = PlannerRepository(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveAndLoadRoundTripsEveryField() throws {
        var day = PlannerDay(date: oct1)
        day.add("Write tests", now: now)
        let id = try XCTUnwrap(day.add("Ship", now: now)).id
        day.toggle(id, now: now.addingTimeInterval(60))
        try repository.save(day)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("2026-10-01.json").path))
        XCTAssertEqual(try PlannerRepository(directory: directory).load(oct1), day)
    }

    func testLoadMissingDayReturnsNil() throws {
        XCTAssertNil(try repository.load(oct1))
    }

    func testOpenNewDayCarriesOverUnfinishedItemsFromMostRecentDay() throws {
        var older = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-20")!)
        older.add("Stale", now: now)
        try repository.save(older)

        var latest = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-29")!)
        let keep = try XCTUnwrap(latest.add("Unfinished", now: now))
        let done = try XCTUnwrap(latest.add("Finished", now: now))
        latest.add("Also open", now: now)
        latest.toggle(done.id, now: now)
        try repository.save(latest)

        let today = try repository.open(oct1)
        XCTAssertEqual(today.items.map(\.title), ["Unfinished", "Also open"])
        XCTAssertEqual(today.items.first?.id, keep.id)
        XCTAssertEqual(today.items.first?.createdAt, now)
        // The previous day stays as a historical record.
        XCTAssertEqual(try repository.load(latest.date), latest)
    }

    func testOpenCarriesOverOnlyOnce() throws {
        var yesterday = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-30")!)
        yesterday.add("Carry me", now: now)
        try repository.save(yesterday)

        var today = try repository.open(oct1)
        today.delete(today.items[0].id)
        try repository.save(today)

        XCTAssertEqual(try repository.open(oct1).items, [])
    }

    func testPreviewShowsTheCarriedOverDayWithoutCreatingItsFile() throws {
        var yesterday = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-30")!)
        yesterday.add("Carry me", now: now)
        try repository.save(yesterday)

        XCTAssertEqual(try repository.preview(oct1).items.map(\.title), ["Carry me"])
        XCTAssertNil(try repository.load(oct1))
        XCTAssertEqual(try repository.savedDays(), [yesterday.date])

        // Once the day exists, preview reads it as saved.
        var today = try repository.open(oct1)
        today.delete(today.items[0].id)
        try repository.save(today)
        XCTAssertEqual(try repository.preview(oct1).items, [])
    }

    func testOpenIgnoresFutureDaysAndUnrelatedFiles() throws {
        var future = PlannerDay(date: PlannerDayKey(rawValue: "2026-10-05")!)
        future.add("From the future", now: now)
        try repository.save(future)
        try Data("hi".utf8).write(to: directory.appendingPathComponent("notes.json"))

        XCTAssertEqual(try repository.open(oct1).items, [])
        XCTAssertEqual(try repository.savedDays().map(\.rawValue), ["2026-10-01", "2026-10-05"])
    }

    func testOpenSkipsCorruptPreviousDay() throws {
        var older = PlannerDay(date: PlannerDayKey(rawValue: "2026-09-28")!)
        older.add("Recovered", now: now)
        try repository.save(older)
        try Data("{".utf8).write(to: directory.appendingPathComponent("2026-09-30.json"))

        XCTAssertEqual(try repository.open(oct1).items.map(\.title), ["Recovered"])
    }

    func testCorruptTodayThrowsInsteadOfBeingOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = repository.fileURL(for: oct1)
        try Data("garbage".utf8).write(to: url)

        XCTAssertThrowsError(try repository.open(oct1))
        XCTAssertEqual(try Data(contentsOf: url), Data("garbage".utf8))
    }

    func testFirstOpenWithNoHistoryCreatesEmptyDayFile() throws {
        XCTAssertEqual(try repository.open(oct1), PlannerDay(date: oct1))
        XCTAssertNotNil(try repository.load(oct1))
    }

    // MARK: Looking back and planning ahead

    func testPeekNeverCreatesAFile() throws {
        let today = try XCTUnwrap(PlannerDayKey(rawValue: "2026-10-01"))
        let tomorrow = today.adding(days: 1)
        let yesterday = today.adding(days: -1)

        XCTAssertEqual(try repository.peek(tomorrow, today: today), PlannerDay(date: tomorrow, isPlannedAhead: true))
        XCTAssertEqual(try repository.peek(yesterday, today: today), PlannerDay(date: yesterday))
        XCTAssertEqual(try repository.savedDays(), [])
    }

    func testPlannedAheadDayTakesInLeftoversWhenItComes() throws {
        let tomorrow = oct1.adding(days: 1)
        var today = try repository.open(oct1)
        let open = try XCTUnwrap(today.add("Write report", now: now))
        let done = try XCTUnwrap(today.add("Inbox zero", now: now))
        today.toggle(done.id, now: now)
        try repository.save(today)

        // In the evening, plan tomorrow; that saves tomorrow's file early.
        var plan = try repository.peek(tomorrow, today: oct1)
        plan.add("Call the dentist", now: now)
        plan.add("write REPORT", now: now)
        try repository.save(plan)

        // The planned "write REPORT" stands in for the leftover of that name.
        let opened = try repository.open(tomorrow)
        XCTAssertEqual(opened.items.map(\.title), ["Call the dentist", "write REPORT"])
        XCTAssertFalse(opened.items.contains { $0.id == open.id })
        XCTAssertFalse(opened.isPlannedAhead)
        XCTAssertEqual(try repository.load(tomorrow), opened)
    }

    func testPlannedTasksKeepTheirStateWhenTheDayComes() throws {
        let tomorrow = oct1.adding(days: 1)
        var today = try repository.open(oct1)
        let leftover = try XCTUnwrap(today.add("Write report", now: now))
        try repository.save(today)

        var plan = try repository.peek(tomorrow, today: oct1)
        let done = try XCTUnwrap(plan.add("Book flights", now: now))
        plan.toggle(done.id, now: now)
        let first = try XCTUnwrap(plan.add("Stretch", now: now))
        let second = try XCTUnwrap(plan.add("Stretch", now: now))
        try repository.save(plan)

        let opened = try repository.open(tomorrow)
        XCTAssertEqual(opened.items.map(\.id), [leftover.id, done.id, first.id, second.id])
        XCTAssertEqual(opened.items.map(\.isDone), [false, true, false, false])
        XCTAssertNotNil(opened.items[1].completedAt)
    }

    func testPlannedAheadDayTakesInLeftoversOnlyOnce() throws {
        var today = try repository.open(oct1)
        today.add("Carry me", now: now)
        try repository.save(today)
        try repository.save(PlannerDay(date: oct1.adding(days: 1), isPlannedAhead: true))

        var opened = try repository.open(oct1.adding(days: 1))
        opened.delete(opened.items[0].id)
        try repository.save(opened)

        XCTAssertEqual(try repository.open(oct1.adding(days: 1)).items, [])
    }

    func testSkippedPlannedAheadDayStillPassesOnOlderLeftovers() throws {
        var today = try repository.open(oct1)
        today.add("Old leftover", now: now)
        try repository.save(today)
        var planned = PlannerDay(date: oct1.adding(days: 1), isPlannedAhead: true)
        planned.add("Planned", now: now)
        try repository.save(planned)

        // The planned day is never opened; the day after it is.
        let later = try repository.open(oct1.adding(days: 2))
        XCTAssertEqual(later.items.map(\.title), ["Old leftover", "Planned"])
    }
}

final class PlannerSampleDataTests: XCTestCase {
    private let oct1 = PlannerDayKey(rawValue: "2026-10-01")!

    func testEverySampleIsAPartlyFinishedDayWithinTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for kind in PlannerSampleDay.allCases {
            assertPartlyFinished(PlannerDay.sample(on: oct1, kind: kind, calendar: calendar), calendar: calendar)
        }
    }

    func testSampleDaysShareTheFirstOpenItem() {
        // The demo focus timer links the work day's first open item; every
        // other sample day must have an open item with that id too.
        let firstOpen = PlannerDay.sample(on: oct1).items.first { !$0.isDone }?.id
        XCTAssertNotNil(firstOpen)
        for kind in PlannerSampleDay.allCases {
            XCTAssertEqual(PlannerDay.sample(on: oct1, kind: kind).items.first { !$0.isDone }?.id, firstOpen)
        }
    }

    func testMedicineSampleIsAStudyDay() {
        let titles = PlannerDay.sample(on: oct1, kind: .medicine).items.map(\.title)
        XCTAssertTrue(titles.contains("UWorld cardio Qs"))
        XCTAssertFalse(titles.contains("Ship notch planner beta"))
    }

    private func assertPartlyFinished(_ day: PlannerDay, calendar: Calendar, line: UInt = #line) {
        XCTAssertEqual(day.date, oct1, line: line)
        XCTAssertEqual(day.items.count, 5, line: line)
        XCTAssertEqual(day.doneCount, 3, line: line)
        XCTAssertEqual(Set(day.items.map(\.id)).count, 5, line: line)
        for item in day.items {
            XCTAssertEqual(PlannerDayKey(date: item.createdAt, calendar: calendar), oct1, line: line)
            XCTAssertEqual(item.isDone, item.completedAt != nil, line: line)
            if let completed = item.completedAt { XCTAssertGreaterThan(completed, item.createdAt, line: line) }
        }
    }

    func testYesterdaySampleLeavesOneTaskCarriedAndTwoToMove() {
        for kind in PlannerSampleDay.allCases {
            let today = PlannerDay.sample(.today, today: oct1, kind: kind)
            let yesterday = PlannerDay.sample(.yesterday, today: oct1, kind: kind)
            XCTAssertEqual(yesterday.date.rawValue, "2026-09-30")
            XCTAssertEqual(yesterday.unfinished(missingFrom: today).count, 2)
            XCTAssertEqual(yesterday.items.filter { !$0.isDone }.count, 3)
            XCTAssertEqual(today, PlannerDay.sample(on: oct1, kind: kind))
        }
    }

    func testTomorrowSampleIsPlannedAheadTheDayBefore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for kind in PlannerSampleDay.allCases {
            let tomorrow = PlannerDay.sample(.tomorrow, today: oct1, kind: kind, calendar: calendar)
            XCTAssertEqual(tomorrow.date.rawValue, "2026-10-02")
            XCTAssertTrue(tomorrow.isPlannedAhead)
            XCTAssertFalse(tomorrow.items.isEmpty)
            XCTAssertEqual(tomorrow.doneCount, 0)
            for item in tomorrow.items {
                XCTAssertEqual(PlannerDayKey(date: item.createdAt, calendar: calendar), oct1)
            }
        }
    }

    func testSampleIsStable() {
        XCTAssertEqual(PlannerDay.sample(on: oct1), PlannerDay.sample(on: oct1))
    }
}

final class PlannerStarterTaskTests: XCTestCase {
    func testAddsStarterTasksOnceSkippingBlanksAndExistingTitles() {
        var day = PlannerDay(date: PlannerDayKey(date: Date()))
        day.add("Review lecture notes")
        let added = day.addStarterTasks(["review  LECTURE notes", "  ", "Plan the week", "Plan the week"])
        XCTAssertEqual(added.map(\.title), ["Plan the week"])
        XCTAssertEqual(day.items.map(\.title), ["Review lecture notes", "Plan the week"])

        XCTAssertTrue(day.addStarterTasks(["Plan the week"]).isEmpty, "applying a kit again adds nothing")
        XCTAssertEqual(day.items.count, 2)
    }

    func testUndoTakesBackOnlyStarterTasksTheUserHasNotTouched() {
        var day = PlannerDay(date: PlannerDayKey(date: Date()))
        day.add("Mine")
        let added = day.addStarterTasks(["Read", "Write", "Plan"])
        day.toggle(added[0].id)
        XCTAssertTrue(day.rename(added[1].id, to: "Write the essay"))

        XCTAssertTrue(day.removeUntouched(added))
        XCTAssertEqual(day.items.map(\.title), ["Mine", "Read", "Write the essay"])
        XCTAssertFalse(day.removeUntouched(added), "nothing left to take back")
    }
}

final class PlannerViewedDayTests: XCTestCase {
    private let oct1 = PlannerDayKey(rawValue: "2026-10-01")!

    func testStepsOneDayEitherSideOfToday() {
        XCTAssertEqual(PlannerViewedDay.yesterday.key(today: oct1).rawValue, "2026-09-30")
        XCTAssertEqual(PlannerViewedDay.today.key(today: oct1), oct1)
        XCTAssertEqual(PlannerViewedDay.tomorrow.key(today: oct1).rawValue, "2026-10-02")
        XCTAssertEqual(PlannerViewedDay.today.previous, .yesterday)
        XCTAssertEqual(PlannerViewedDay.today.next, .tomorrow)
        XCTAssertEqual(PlannerViewedDay.yesterday.next, .today)
        XCTAssertNil(PlannerViewedDay.yesterday.previous)
        XCTAssertNil(PlannerViewedDay.tomorrow.next)
    }

    func testOnlyYesterdayIsReadOnlyAndOnlyTodayGoesUntitled() {
        XCTAssertFalse(PlannerViewedDay.yesterday.isEditable)
        XCTAssertTrue(PlannerViewedDay.today.isEditable)
        XCTAssertTrue(PlannerViewedDay.tomorrow.isEditable)
        XCTAssertNil(PlannerViewedDay.today.title)
        XCTAssertEqual(PlannerViewedDay.yesterday.title, "Yesterday")
        XCTAssertEqual(PlannerViewedDay.tomorrow.title, "Tomorrow")
    }

    func testPlanStartsNowTodayAtTheWorkingDayTomorrowAndNeverYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // The night before the October clock change, at 11 pm.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
        XCTAssertEqual(PlannerViewedDay.today.planStart(now: now, calendar: calendar), now)
        XCTAssertNil(PlannerViewedDay.yesterday.planStart(now: now, calendar: calendar))
        XCTAssertEqual(PlannerViewedDay.tomorrow.planStart(now: now, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9)))
        XCTAssertEqual(PlannerViewedDay.tomorrow.planStart(now: now, calendar: calendar, startHour: 7),
                       calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7)))
        XCTAssertEqual(PlannerViewedDay.today.planTitle, "Plan my day")
        XCTAssertEqual(PlannerViewedDay.tomorrow.planTitle, "Plan tomorrow")
    }

    func testCalendarCardIsCaptionedForTheDayItLists() {
        XCTAssertEqual(PlannerViewedDay.today.calendarTitle, "Up next")
        XCTAssertEqual(PlannerViewedDay.yesterday.calendarTitle, "Yesterday's calendar")
        XCTAssertEqual(PlannerViewedDay.tomorrow.calendarTitle, "Tomorrow's calendar")
    }
}
