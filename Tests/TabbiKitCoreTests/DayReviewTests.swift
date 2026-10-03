import XCTest
import TabbiKitCore

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
        let review = DayReviewer.review(of: checklist(), activity: [], calendar: calendar)
        XCTAssertEqual(review.date, oct1)
        XCTAssertEqual(review.done, ["Ship planner beta", "Review Ana's PR"])
        XCTAssertEqual(review.carryingOver, ["Write release notes"])
        XCTAssertEqual(review.focusSessions, 0)
        XCTAssertNil(review.summary)
        XCTAssertFalse(review.isEmpty)
    }

    func testReviewCountsTodaysFocusStretchesFromEveryTimer() {
        let config = FocusTimerConfig(focusDuration: 25 * 60, restDuration: 5 * 60)
        let yesterday = PlannerDayKey(rawValue: "2026-09-30")!
        let study = ActivityRecord(source: .study, kind: .focusCompleted, start: at(13), end: at(13, 40),
                                   quantity: 40, unit: .minutes)
        let activity = [
            FocusPhaseCompletion(phase: .focus, endedAt: at(23, 50, day: yesterday)).activityRecord(config: config, source: .focus),
            FocusPhaseCompletion(phase: .focus, endedAt: at(10)).activityRecord(config: config, source: .focus),
            FocusPhaseCompletion(phase: .rest, endedAt: at(10, 5)).activityRecord(config: config, source: .focus),
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: at(11), quantity: 80, unit: .cards),
            study,
        ]

        let review = DayReviewer.review(of: checklist(), activity: activity, calendar: calendar)
        XCTAssertEqual(review.focusSessions, 2, "breaks, cards and yesterday's session don't count")
        XCTAssertEqual(review.focusMinutes, 65)
    }

    func testReviewSkipsStudyPhasesThatWereCutShort() {
        func phase(_ outcome: StudyPhaseOutcome, from start: Int) -> ActivityRecord? {
            StudyPhaseRecord(method: .flowtime, phase: .focus, startedAt: at(start), endedAt: at(start, 30),
                             activeDuration: 30 * 60, outcome: outcome).activityRecord(source: .study)
        }
        let activity = [phase(.completed, from: 9), phase(.stopped, from: 10),
                        phase(.skipped, from: 11), phase(.abandoned, from: 12)].compactMap { $0 }

        let review = DayReviewer.review(of: checklist(), activity: activity, calendar: calendar)
        XCTAssertEqual(review.focusSessions, 2, "a skipped or abandoned phase isn't a finished session")
        XCTAssertEqual(review.focusMinutes, 60)
    }

    func testLegacySessionLogBecomesPomodoroFocusRecords() {
        let log = FocusSessionLog(sessions: [.init(endedAt: at(10), duration: 25 * 60)])
        let records = log.activityRecords(source: .focus)
        let expected = FocusPhaseCompletion(phase: .focus, endedAt: at(10))
            .activityRecord(config: FocusTimerConfig(focusDuration: 25 * 60), source: .focus)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, expected.kind)
        XCTAssertEqual(records.first?.start, expected.start)
        XCTAssertEqual(records.first?.end, expected.end)
        XCTAssertEqual(records.first?.quantity, 25)
        XCTAssertEqual(records.first?.metadata, expected.metadata)
        XCTAssertEqual(DayReviewer.review(of: checklist(), activity: records, calendar: calendar).focusMinutes, 25)
    }

    func testMovingTheLegacyLogAgainAddsNoCopies() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = ActivityLogRepository(directory: folder, calendar: calendar)
        let log = FocusSessionLog(sessions: [.init(endedAt: at(10), duration: 25 * 60),
                                             .init(endedAt: at(11), duration: 25 * 60)])

        try repository.append(log.activityRecords(source: .focus))
        try repository.append(log.activityRecords(source: .focus))

        XCTAssertEqual(try repository.records(on: oct1).count, 2, "a retried move skips what is already on disk")
    }

    func testEmptyDayIsEmpty() {
        let review = DayReviewer.review(of: PlannerDay(date: oct1), activity: [], calendar: calendar)
        XCTAssertTrue(review.isEmpty)
    }

    func testWrapUpIsSuggestedFromFivePM() {
        XCTAssertFalse(DayReviewer.isWrapUpTime(at(16, 59), calendar: calendar))
        XCTAssertTrue(DayReviewer.isWrapUpTime(at(17), calendar: calendar))
        XCTAssertTrue(DayReviewer.isWrapUpTime(at(23, 30), calendar: calendar))
    }

    // MARK: Claude

    func testPromptListsTheDayAndArgumentsDisableTools() {
        var review = DayReviewer.review(of: checklist(), activity: [], calendar: calendar)
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

        var review = DayReviewer.review(of: checklist(), activity: [], calendar: calendar)
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

    func testMedicineSampleReviewCarriesOverStudyWork() throws {
        let sample = DayReview.sample(on: oct1, kind: .medicine, calendar: calendar)
        XCTAssertEqual(sample.carryingOver, ["UWorld cardio Qs", "Renal notes"])
        let summary = try XCTUnwrap(sample.summary)
        XCTAssertEqual(DayReviewer.summary(from: summary), summary, "the canned summary already fits the card")
        XCTAssertTrue(summary.contains("UWorld"))
    }

    // MARK: Study stats

    private func ankiReviews(done: Int, of target: Int) -> ProgressItem {
        ProgressItem(id: "reviews", source: .anki, title: "Anki reviews", completed: done, target: target, unit: "cards")
    }

    func testReviewKeepsStudyTallyAndSharedGoalCounts() {
        let tally = StudyDayTally(minutes: 185, sessions: 3, points: 215)
        let idle = ProgressItem(id: "q", source: .anki, title: "Questions", completed: 0, target: 0, unit: "questions")
        let review = DayReviewer.review(of: checklist(), activity: [], study: tally,
                                        progress: [ankiReviews(done: 112, of: 432), idle], calendar: calendar)
        XCTAssertEqual(review.study, tally)
        XCTAssertEqual(review.progress, [DayReviewCount(title: "Anki reviews", count: 112, unit: "cards")],
                       "a goal with nothing due and nothing done is left out")
    }

    func testStatsShowStudyTimeSessionsCardsAndPoints() {
        let review = DayReviewer.review(of: checklist(), activity: [],
                                        study: StudyDayTally(minutes: 185, sessions: 3, points: 215),
                                        progress: [ankiReviews(done: 112, of: 432)], calendar: calendar)
        XCTAssertEqual(DayReviewer.stats(for: review).map(\.text), ["3h 5m · 3 sessions", "112 cards", "215 pts"])
    }

    func testStatsFallBackToFocusSessionsWithoutAStudyTally() {
        var review = DayReviewer.review(of: checklist(), activity: [], calendar: calendar)
        XCTAssertEqual(DayReviewer.stats(for: review).map(\.text), ["No focus sessions today"])
        review.focusSessions = 1
        review.focusMinutes = 60
        XCTAssertEqual(DayReviewer.stats(for: review).map(\.text), ["1 focus session · 1h"])
    }

    func testStatsForAStudyDayWithNothingLoggedYet() {
        let review = DayReviewer.review(of: PlannerDay(date: oct1), activity: [], study: StudyDayTally(),
                                        progress: [ankiReviews(done: 0, of: 200)], calendar: calendar)
        XCTAssertEqual(DayReviewer.stats(for: review).map(\.text), ["No study yet", "0 cards", "0 pts"])
        XCTAssertTrue(review.isEmpty)
    }

    func testStudyTimeAloneMakesTheDayWorthReviewing() {
        let review = DayReviewer.review(of: PlannerDay(date: oct1), activity: [],
                                        study: StudyDayTally(minutes: 50, sessions: 1, points: 60), calendar: calendar)
        XCTAssertFalse(review.isEmpty)
        XCTAssertEqual(DayReviewer.fallbackSummary(for: review), "You put in 50m of study today. Rest up and start fresh tomorrow.")
    }

    func testPromptMentionsStudyAndSharedGoalsOnlyWhenPresent() {
        let plain = DayReviewer.prompt(for: DayReviewer.review(of: checklist(), activity: [], calendar: calendar))
        XCTAssertFalse(plain.contains("Studied"))

        let study = DayReviewer.review(of: checklist(), activity: [],
                                       study: StudyDayTally(minutes: 185, sessions: 3, points: 215),
                                       progress: [ankiReviews(done: 112, of: 432)], calendar: calendar)
        let prompt = DayReviewer.prompt(for: study)
        XCTAssertTrue(prompt.contains("Studied: 185 minutes over 3 sessions, 215 points earned"))
        XCTAssertTrue(prompt.contains("Anki reviews: 112 cards done"))
    }

    func testReviewsSavedBeforeStudyStatsStillLoad() throws {
        let json = #"{"date":"2026-10-01","done":["A"],"carryingOver":[],"focusSessions":1,"focusMinutes":25,"summary":"Nice."}"#
        let review = try JSONDecoder().decode(DayReview.self, from: Data(json.utf8))
        XCTAssertEqual(review.done, ["A"])
        XCTAssertNil(review.study)
        XCTAssertEqual(review.progress, [])
        XCTAssertEqual(review.summary, "Nice.")
    }

    func testStudyReviewRoundTripsThroughJSON() throws {
        let review = DayReviewer.review(of: checklist(), activity: [], study: .sample,
                                        progress: [ankiReviews(done: 112, of: 432)], calendar: calendar)
        let decoded = try JSONDecoder().decode(DayReview.self, from: JSONEncoder().encode(review))
        XCTAssertEqual(decoded, review)
    }

    func testSampleTallyFollowsThePointsRules() {
        XCTAssertEqual(StudyDayTally.sample, StudyDayTally(minutes: 185, sessions: 3, points: 215))
    }
}
