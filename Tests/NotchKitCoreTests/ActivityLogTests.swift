import XCTest
@testable import NotchKitCore

final class ActivityLogTests: XCTestCase {
    private var folder: URL!
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityLogTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func repository() -> ActivityLogRepository {
        ActivityLogRepository(directory: folder, calendar: calendar)
    }

    private func day(_ key: String) throws -> PlannerDayKey {
        try XCTUnwrap(PlannerDayKey(rawValue: key))
    }

    /// 2026-10-02 at `hour`:`minute` UTC, in whole seconds so ISO 8601 round-trips it.
    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func focus(endingAt end: Date, minutes: Double = 25, source: ModuleID = .focus) -> ActivityRecord {
        ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60), end: end,
                       quantity: minutes, unit: .minutes)
    }

    // MARK: Records

    func testRecordNeverEndsBeforeItStartsAndCountsTowardItsEndDay() throws {
        let moment = ActivityRecord(source: .planner, kind: .taskCompleted, start: date(9))
        XCTAssertEqual(moment.end, moment.start)
        let backwards = ActivityRecord(source: .focus, kind: .breakTaken, start: date(9), end: date(8))
        XCTAssertEqual(backwards.end, date(9))
        let overnight = focus(endingAt: date(0, 10, day: 3), minutes: 30)
        XCTAssertEqual(overnight.day(calendar: calendar), try day("2026-10-03"))
    }

    func testKindsAreOpenStrings() throws {
        let solved = ActivityRecord(source: "leetcode", kind: "problem.solved", start: date(10), subject: "two-sum")
        let data = try JSONEncoder().encode(solved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "problem.solved")
        XCTAssertEqual(json["source"] as? String, "leetcode")
        XCTAssertEqual(try JSONDecoder().decode(ActivityRecord.self, from: data), solved)
    }

    // MARK: Repository

    func testAppendedRecordsReadBackByDayInAVersionedFile() throws {
        let repo = repository()
        let morning = focus(endingAt: date(9))
        let evening = focus(endingAt: date(21), source: .study)
        let tomorrow = focus(endingAt: date(8, day: 3))
        try repo.append([evening, tomorrow, morning])

        XCTAssertEqual(try repo.records(on: day("2026-10-02")), [morning, evening])
        XCTAssertEqual(try repo.records(on: day("2026-10-03")), [tomorrow])
        XCTAssertEqual(try repo.records(on: day("2026-10-04")), [])
        XCTAssertEqual(repo.savedDays(), [try day("2026-10-02"), try day("2026-10-03")])
        let data = try Data(contentsOf: repo.fileURL(for: day("2026-10-02")))
        XCTAssertEqual(VersionedJSON.version(of: data), ActivityLogRepository.schema.current)
    }

    func testAppendingTheSameRecordTwiceKeepsOne() throws {
        let repo = repository()
        let record = focus(endingAt: date(9))
        try repo.append([record])
        try repo.append([record, record])
        XCTAssertEqual(try repo.records(on: day("2026-10-02")), [record])
    }

    func testRangeReadsSkipUnrelatedAndUnreadableFiles() throws {
        let repo = repository()
        let first = focus(endingAt: date(9, day: 1))
        let third = focus(endingAt: date(9, day: 3))
        try repo.append([first, third])
        try Data("not json".utf8).write(to: repo.fileURL(for: day("2026-10-02")))
        try Data("notes".utf8).write(to: folder.appendingPathComponent("readme.txt"))

        XCTAssertEqual(repo.records(from: try day("2026-10-01"), through: try day("2026-10-03")), [first, third])
        XCTAssertEqual(repo.records(from: try day("2026-10-02"), through: try day("2026-10-02")), [])
    }

    func testAnUnreadableDayIsNeverOverwritten() throws {
        let repo = repository()
        try repo.append([focus(endingAt: date(8))])
        let url = repo.fileURL(for: try day("2026-10-02"))
        let garbage = Data("{\"records\": 42}".utf8)
        try garbage.write(to: url)

        XCTAssertThrowsError(try repo.append([focus(endingAt: date(10))]))
        XCTAssertEqual(try Data(contentsOf: url), garbage)
    }

    func testDayFilesWithoutAVersionStillLoad() throws {
        let repo = repository()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = """
        {"records": [{"id": "6F1D3A2E-0C59-4D0B-9A64-1B5B8F1D2C3E", "source": "anki", "kind": "cards.reviewed",
                      "start": "2026-10-02T09:00:00Z", "quantity": 12, "unit": "cards"}]}
        """
        try Data(legacy.utf8).write(to: repo.fileURL(for: day("2026-10-02")))
        let records = try repo.records(on: day("2026-10-02"))
        XCTAssertEqual(records.map(\.kind), [.cardsReviewed])
        XCTAssertEqual(records.first?.end, date(9))
        XCTAssertEqual(records.first?.metadata, [:])
    }

    // MARK: Engines

    func testFocusTimerPhasesBecomeFocusAndBreakRecords() {
        let config = FocusTimerConfig(focusDuration: 50 * 60, restDuration: 10 * 60)
        let focus = FocusPhaseCompletion(phase: .focus, endedAt: date(10)).activityRecord(config: config, source: .focus)
        XCTAssertEqual(focus.kind, .focusCompleted)
        XCTAssertEqual(focus.start, date(9, 10))
        XCTAssertEqual(focus.quantity, 50)
        XCTAssertEqual(focus.unit, .minutes)
        let rest = FocusPhaseCompletion(phase: .rest, endedAt: date(10, 10)).activityRecord(config: config, source: .focus)
        XCTAssertEqual(rest.kind, .breakTaken)
        XCTAssertEqual(rest.quantity, 10)
    }

    func testStudyPhasesLogTheirRunningTimeAndSkipBlips() throws {
        let sprint = StudyPhaseRecord(method: .ankiSprint, phase: .focus, startedAt: date(9), endedAt: date(9, 30),
                                      activeDuration: 20 * 60, outcome: .completed, cards: 40)
        let record = try XCTUnwrap(sprint.activityRecord(source: .study))
        XCTAssertEqual(record.kind, .focusCompleted)
        XCTAssertEqual(record.quantity, 20)
        XCTAssertEqual(record.metadata[ActivityMetadata.method], "ankiSprint")
        XCTAssertEqual(record.metadata[ActivityMetadata.outcome], "completed")
        XCTAssertEqual(record.metadata["cards"], "40")

        let review = StudyPhaseRecord(method: .pomodoro, phase: .review, startedAt: date(10), endedAt: date(10, 10),
                                      activeDuration: 10 * 60, outcome: .stopped)
        XCTAssertEqual(review.activityRecord(source: .study)?.kind, .focusCompleted)
        let rest = StudyPhaseRecord(method: .pomodoro, phase: .longBreak, startedAt: date(11), endedAt: date(11, 15),
                                    activeDuration: 15 * 60, outcome: .completed)
        XCTAssertEqual(rest.activityRecord(source: .study)?.kind, .breakTaken)
        let blip = StudyPhaseRecord(method: .pomodoro, phase: .focus, startedAt: date(12), endedAt: date(12),
                                    activeDuration: 20, outcome: .skipped)
        XCTAssertNil(blip.activityRecord(source: .study))
    }

    func testAnkiLogsOnlyCardsNotLoggedForTheSameAnkiDay() throws {
        let today = AnkiDay(year: 2026, month: 10, day: 2)
        func summary(_ reviewed: Int, on day: AnkiDay = today) -> AnkiSummary {
            AnkiSummary(deckStats: [], reviewedToday: reviewed, reviewsByDay: [], reviews: [], now: date(12), today: day)
        }

        let first = try XCTUnwrap(summary(30).reviewActivity(after: [], source: .anki, now: date(9)))
        XCTAssertEqual(first.kind, .cardsReviewed)
        XCTAssertEqual(first.quantity, 30)
        XCTAssertEqual(first.unit, .cards)
        XCTAssertEqual(first.metadata[AnkiSummary.activityDayKey], "2026-10-02")

        let more = try XCTUnwrap(summary(45).reviewActivity(after: [first], source: .anki, now: date(10)))
        XCTAssertEqual(more.quantity, 15)
        XCTAssertNil(summary(45).reviewActivity(after: [first, more], source: .anki, now: date(11)))
        // Another module's cards don't count as logged.
        let study = ActivityRecord(source: .study, kind: .cardsReviewed, start: date(9), quantity: 45,
                                   metadata: [AnkiSummary.activityDayKey: "2026-10-02"])
        XCTAssertEqual(summary(45).reviewActivity(after: [study], source: .anki, now: date(11))?.quantity, 45)
        // After midnight but before Anki's rollover the count is still the old
        // Anki day's, so nothing new is logged; the next Anki day starts over.
        XCTAssertNil(summary(45).reviewActivity(after: [first, more], source: .anki, now: date(1, day: 3)))
        let nextDay = summary(5, on: today.adding(days: 1))
            .reviewActivity(after: [first, more], source: .anki, now: date(5, day: 3))
        XCTAssertEqual(nextDay?.quantity, 5)
    }
}
