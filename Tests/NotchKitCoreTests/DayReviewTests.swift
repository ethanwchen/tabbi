import XCTest
import NotchKitCore

final class DayReviewTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let oct1 = PlannerDayKey(rawValue: "2026-10-01")!

    private func at(_ hour: Int, _ minute: Int = 0, day: PlannerDayKey? = nil) -> Date {
        (day ?? oct1).startDate(calendar: calendar).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private func checklist() -> PlannerDay {
        var day = PlannerDay(date: oct1)
        let ship = day.add("Ship planner beta", now: at(9))!
        day.add("Write release notes", now: at(9))
        let review = day.add("Review Ana's PR", now: at(9))!
        day.toggle(review.id, now: at(10))
        day.toggle(ship.id, now: at(15))
        return day
    }

    // MARK: Aggregation

    func testReviewSplitsDoneAndCarryOverInListOrder() {
        let review = DayReviewer.review(of: checklist(), focusLog: FocusSessionLog(), calendar: calendar)
        XCTAssertEqual(review.date, oct1)
        XCTAssertEqual(review.done, ["Ship planner beta", "Review Ana's PR"])
        XCTAssertEqual(review.carryingOver, ["Write release notes"])
        XCTAssertEqual(review.focusSessions, 0)
        XCTAssertNil(review.summary)
        XCTAssertFalse(review.isEmpty)
    }

    func testReviewCountsOnlyTodaysFocusSessions() {
        let config = FocusTimerConfig(focusDuration: 25 * 60, restDuration: 5 * 60)
        var log = FocusSessionLog()
        let yesterday = PlannerDayKey(rawValue: "2026-09-30")!
        log.record([FocusPhaseCompletion(phase: .focus, endedAt: at(23, 50, day: yesterday))], config: config, now: at(0), calendar: calendar)
        log.record([
            FocusPhaseCompletion(phase: .focus, endedAt: at(10)),
            FocusPhaseCompletion(phase: .rest, endedAt: at(10, 5)),
        ], config: config, now: at(10, 5), calendar: calendar)
        log.record([FocusPhaseCompletion(phase: .focus, endedAt: at(14))], config: FocusTimerConfig(focusDuration: 50 * 60), now: at(14), calendar: calendar)

        let review = DayReviewer.review(of: checklist(), focusLog: log, calendar: calendar)
        XCTAssertEqual(review.focusSessions, 2, "breaks and yesterday's session don't count")
        XCTAssertEqual(review.focusMinutes, 75)
    }

    func testFocusLogForgetsSessionsOlderThanAWeek() {
        let config = FocusTimerConfig()
        var log = FocusSessionLog()
        let old = PlannerDayKey(rawValue: "2026-09-20")!
        log.record([FocusPhaseCompletion(phase: .focus, endedAt: at(10, day: old))], config: config, now: at(10, day: old), calendar: calendar)
        log.record([FocusPhaseCompletion(phase: .focus, endedAt: at(10))], config: config, now: at(10), calendar: calendar)
        XCTAssertEqual(log.sessions.map(\.endedAt), [at(10)])
    }

    func testEmptyDayIsEmpty() {
        let review = DayReviewer.review(of: PlannerDay(date: oct1), focusLog: FocusSessionLog(), calendar: calendar)
        XCTAssertTrue(review.isEmpty)
    }

    func testWrapUpIsSuggestedFromFivePM() {
        XCTAssertFalse(DayReviewer.isWrapUpTime(at(16, 59), calendar: calendar))
        XCTAssertTrue(DayReviewer.isWrapUpTime(at(17), calendar: calendar))
        XCTAssertTrue(DayReviewer.isWrapUpTime(at(23, 30), calendar: calendar))
    }

    // MARK: Claude

    func testPromptListsTheDayAndArgumentsDisableTools() {
        var review = DayReviewer.review(of: checklist(), focusLog: FocusSessionLog(), calendar: calendar)
        review.focusSessions = 2
        review.focusMinutes = 50
        let prompt = DayReviewer.prompt(for: review)
        XCTAssertTrue(prompt.contains("- Ship planner beta"))
        XCTAssertTrue(prompt.contains("- Write release notes"))
        XCTAssertTrue(prompt.contains("Focus sessions completed: 2 (50 minutes)"))

        let empty = DayReviewer.prompt(for: DayReview(date: oct1, done: [], carryingOver: [], focusSessions: 0, focusMinutes: 0))
        XCTAssertTrue(empty.contains("Done today:\n- none"))

        let arguments = DayReviewer.extraArguments()
        XCTAssertEqual(arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] }, "")
        XCTAssertTrue(arguments.contains("--model"))
    }

    func testSummaryCleansFencesQuotesAndLineBreaks() {
        XCTAssertEqual(DayReviewer.summary(from: "  \"Nice work today.\nRest well.\"  "), "Nice work today. Rest well.")
        XCTAssertEqual(DayReviewer.summary(from: "```\nGreat focus today.\n```"), "Great focus today.")
        XCTAssertEqual(DayReviewer.summary(from: "\u{201C}Solid progress.\u{201D}"), "Solid progress.")
    }

    func testSummaryKeepsAtMostTwoSentences() {
        XCTAssertEqual(DayReviewer.summary(from: "One. Two! Three? Four."), "One. Two!")
    }

    func testOverlongSummaryIsCutAtAWord() throws {
        let long = String(repeating: "wonderful ", count: 40)
        let summary = try XCTUnwrap(DayReviewer.summary(from: long))
        XCTAssertLessThanOrEqual(summary.count, DayReviewer.maximumSummaryLength)
        XCTAssertTrue(summary.hasSuffix("wonderful\u{2026}"))
    }

    func testBlankSummaryIsNil() {
        XCTAssertNil(DayReviewer.summary(from: "  \n "))
        XCTAssertNil(DayReviewer.summary(from: "\"\""))
    }

    func testFallbackSummaryFitsTheDay() {
        func review(done: Int, left: Int, focus: Int = 0) -> DayReview {
            DayReview(date: oct1, done: Array(repeating: "a", count: done), carryingOver: Array(repeating: "b", count: left),
                      focusSessions: focus, focusMinutes: focus * 25)
        }
        XCTAssertEqual(DayReviewer.fallbackSummary(for: review(done: 3, left: 0)), "You cleared all 3 tasks today. Enjoy the evening.")
        XCTAssertEqual(DayReviewer.fallbackSummary(for: review(done: 1, left: 2)),
                       "You finished 1 task today. 2 tasks will be waiting tomorrow.")
        XCTAssertTrue(DayReviewer.fallbackSummary(for: review(done: 0, left: 1)).contains("1 task ready"))
        XCTAssertTrue(DayReviewer.fallbackSummary(for: review(done: 0, left: 0, focus: 1)).contains("1 focus session"))
        XCTAssertEqual(DayReviewer.fallbackSummary(for: review(done: 0, left: 0)), "A quiet day. Rest up and start fresh tomorrow.")
    }

    // MARK: Persistence and demo

    func testRepositorySavesOneFilePerDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = DayReviewRepository(directory: directory)
        XCTAssertNil(try repository.load(oct1))

        var review = DayReviewer.review(of: checklist(), focusLog: FocusSessionLog(), calendar: calendar)
        review.summary = "Good day."
        try repository.save(review)
        XCTAssertEqual(repository.fileURL(for: oct1).lastPathComponent, "2026-10-01.json")
        XCTAssertEqual(try DayReviewRepository(directory: directory).load(oct1), review)

        review.summary = "Even better."
        try repository.save(review)
        XCTAssertEqual(try repository.load(oct1)?.summary, "Even better.")
    }

    func testSampleReviewIsRealistic() throws {
        let sample = DayReview.sample(on: oct1, calendar: calendar)
        XCTAssertEqual(sample.done.count, 3)
        XCTAssertEqual(sample.carryingOver, ["Ship notch planner beta", "30-minute run"])
        XCTAssertGreaterThan(sample.focusSessions, 0)
        let summary = try XCTUnwrap(sample.summary)
        XCTAssertEqual(DayReviewer.summary(from: summary), summary, "the canned summary already fits the card")
    }
}
