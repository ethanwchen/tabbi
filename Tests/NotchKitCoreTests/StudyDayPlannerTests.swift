import XCTest
import NotchKitCore

final class StudyDayPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-10-01 at `hour:minute` Los Angeles time.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    private let cardio = PlannerItem(title: "Cardio pathology", createdAt: Date(timeIntervalSince1970: 0))
    private let pharm = PlannerItem(title: "Sketchy pharm", createdAt: Date(timeIntervalSince1970: 0))
    private let anki = StudyReviewWork(title: "Anki reviews", minutes: 45)

    private func context(now: Date, events: [UpcomingEvent] = [], tasks: [PlannerItem] = []) -> DayPlanContext {
        DayPlanContext(now: now, events: events, tasks: tasks, calendar: calendar)
    }

    /// A lecture 10-12, lab 13-15 and an all-day reminder.
    private var classDay: [UpcomingEvent] {
        [event("Lecture", at(10), at(12)), event("Anatomy lab", at(13), at(15)),
         event("Exam week", at(0), at(23, 59), allDay: true)]
    }

    private func assertConstraints(_ plan: StudyDayPlan, _ context: DayPlanContext,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let blocks = plan.blocks
        XCTAssertLessThanOrEqual(blocks.count, DayPlanner.maximumBlocks, file: file, line: line)
        for (a, b) in zip(blocks, blocks.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start, "\(a.title) overlaps \(b.title)", file: file, line: line)
        }
        for block in blocks {
            XCTAssertTrue(context.gaps.contains { $0.start <= block.start && block.end <= $0.end },
                          "\(block.title) leaves free time", file: file, line: line)
            XCTAssertGreaterThanOrEqual(block.start, context.now, file: file, line: line)
            XCTAssertLessThanOrEqual(block.end, context.dayEnd, file: file, line: line)
        }
    }

    // MARK: - Reviews

    func testReviewsComeFirstByDefault() {
        let context = context(now: at(8), events: classDay)
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki])
        XCTAssertEqual(plan.blocks.first?.kind, .reviews)
        XCTAssertEqual(plan.blocks.first?.title, "Anki reviews")
        XCTAssertEqual(plan.blocks.first?.start, at(8))
        XCTAssertEqual(plan.blocks.first?.end, at(8, 45))
        assertConstraints(plan, context)
    }

    func testReviewsLastWhenTheUserPrefersIt() {
        let context = context(now: at(8), events: classDay)
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki],
                                        preferences: StudyDayPreferences(reviewsFirst: false))
        let reviews = plan.blocks.filter { $0.kind == .reviews }
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?.end, at(18))
        XCTAssertEqual(reviews.first?.start, at(17, 15))
        XCTAssertEqual(plan.blocks.first?.kind, .study)
        assertConstraints(plan, context)
    }

    func testReviewsSkipAGapTooShortForThemWhole() {
        // 8:00-8:40 is free, then a lecture; 45 min of reviews wait for later.
        let context = context(now: at(8), events: [event("Lecture", at(8, 50), at(10))])
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki],
                                        preferences: StudyDayPreferences(eventBufferMinutes: 10))
        let reviews = plan.blocks.first { $0.kind == .reviews }
        XCTAssertEqual(reviews?.start, at(10, 10))
        XCTAssertEqual(reviews?.end, at(10, 55))
        // The earlier slot still gets a study block.
        XCTAssertEqual(plan.blocks.first?.kind, .study)
        XCTAssertEqual(plan.blocks.first?.start, at(8))
        assertConstraints(plan, context)
    }

    func testReviewsTooLongForAnyGapSplitAcrossTheEarliestGaps() {
        // Free: 8:00-8:40 and 10:10-10:50 (buffered), then a shift until 18:00.
        let context = context(now: at(8), events: [event("Lecture", at(8, 50), at(10)),
                                                   event("Shift", at(11), at(18))])
        let plan = StudyDayPlanner.plan(context: context, reviews: [StudyReviewWork(title: "Anki reviews", minutes: 60)],
                                        preferences: StudyDayPreferences(eventBufferMinutes: 10))
        let reviews = plan.blocks.filter { $0.kind == .reviews }
        XCTAssertEqual(reviews.map(\.start), [at(8), at(10, 10)])
        XCTAssertEqual(reviews.map(\.end), [at(8, 40), at(10, 30)])
        assertConstraints(plan, context)
    }

    func testLateReviewsSplitFromTheEndOfTheDay() {
        // Free: 8:00-8:40, 10:10-11:00 and 16:10-18:00; 150 min capped to 120:
        // 110 min at the end, and the last 10 grows to a 15-min block.
        let context = context(now: at(8), events: [event("Lecture", at(8, 50), at(10)),
                                                   event("Clinic", at(11, 10), at(16))])
        let plan = StudyDayPlanner.plan(context: context, reviews: [StudyReviewWork(title: "Anki reviews", minutes: 150)],
                                        preferences: StudyDayPreferences(reviewsFirst: false, eventBufferMinutes: 10))
        let reviews = plan.blocks.filter { $0.kind == .reviews }
        XCTAssertEqual(reviews.map(\.start), [at(10, 45), at(16, 10)])
        XCTAssertEqual(reviews.map(\.end), [at(11), at(18)])
        assertConstraints(plan, context)
    }

    func testLongReviewQueueIsCappedAndShrinksToTheBiggestGap() {
        let context = context(now: at(16), events: [])
        let plan = StudyDayPlanner.plan(context: context, reviews: [StudyReviewWork(title: "Anki reviews", minutes: 400)])
        // Only 16:00-18:00 is left, so reviews take all of it.
        XCTAssertEqual(plan.blocks.map(\.kind), [.reviews])
        XCTAssertEqual(plan.blocks.first?.start, at(16))
        XCTAssertEqual(plan.blocks.first?.end, at(18))
    }

    func testReviewWorkFromProgressRoundsUpToFiveMinutes() {
        let item = ProgressItem(id: "reviews", source: .anki, title: "Anki reviews", completed: 112, target: 432, unit: "cards")
        // 320 cards at 10 s is 53.3 min.
        XCTAssertEqual(item.reviewWork(), StudyReviewWork(title: "Anki reviews", minutes: 55))
        XCTAssertEqual(item.reviewWork(secondsPerUnit: 6), StudyReviewWork(title: "Anki reviews", minutes: 35))
        let done = ProgressItem(id: "reviews", source: .anki, title: "Anki reviews", completed: 432, target: 432, unit: "cards")
        XCTAssertNil(done.reviewWork())
    }

    // MARK: - Study blocks

    func testStudyBlocksAreExactlyTheMethodLengthWithBreaksBetween() {
        let context = context(now: at(8), events: classDay, tasks: [cardio, pharm])
        let preferences = StudyDayPreferences(method: .fiftyTwoSeventeen)
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki], preferences: preferences)
        let study = plan.blocks.filter { $0.kind == .study }
        XCTAssertFalse(study.isEmpty)
        for block in study { XCTAssertEqual(block.end.timeIntervalSince(block.start), 52 * 60) }
        // Reviews 8:00-8:45; after a 17 min break no 52 min block fits
        // before the lecture's buffer at 9:50, nor in the lunch gap, so
        // study waits for the afternoon: 15:10, then 17 min off, 16:20.
        XCTAssertEqual(plan.blocks.map(\.start), [at(8), at(15, 10), at(16, 20)])
        XCTAssertEqual(plan.breaks, [DateInterval(start: at(16, 2), end: at(16, 20))])
        assertConstraints(plan, context)
    }

    func testOpenTasksNameTheFirstStudyBlocksThenTheGenericTitle() {
        let context = context(now: at(15), events: [], tasks: [cardio, pharm])
        let plan = StudyDayPlanner.plan(context: context, reviews: [],
                                        preferences: StudyDayPreferences(studyTitle: "Question bank"))
        XCTAssertEqual(plan.blocks.map(\.title).prefix(3), ["Cardio pathology", "Sketchy pharm", "Question bank"])
        XCTAssertEqual(plan.blocks.first?.linkedTaskID, cardio.id)
        XCTAssertNil(plan.blocks[2].linkedTaskID)
    }

    func testPomodoroTakesALongBreakAfterEveryFourthBlock() {
        let context = context(now: at(14), events: [])
        let plan = StudyDayPlanner.plan(context: context, reviews: [],
                                        preferences: StudyDayPreferences(method: .pomodoro))
        XCTAssertEqual(plan.blocks.count, DayPlanner.maximumBlocks)
        // 25/5 three times, 25 then a 15 min long break, then the fifth block.
        XCTAssertEqual(plan.blocks.map(\.start), [at(14), at(14, 30), at(15), at(15, 30), at(16, 10)])
        XCTAssertEqual(plan.breaks.last, DateInterval(start: at(15, 55), end: at(16, 10)))
    }

    func testBlocksKeepABufferAroundEvents() {
        let context = context(now: at(8), events: classDay)
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki],
                                        preferences: StudyDayPreferences(eventBufferMinutes: 10))
        let buffer: TimeInterval = 10 * 60
        for block in plan.blocks {
            for event in classDay where !event.isAllDay {
                XCTAssertFalse(block.start < event.end.addingTimeInterval(buffer)
                               && event.start.addingTimeInterval(-buffer) < block.end,
                               "\(block.title) is too close to \(event.title)")
            }
        }
        // A break never spans an event.
        for rest in plan.breaks {
            XCTAssertFalse(classDay.contains { !$0.isAllDay && $0.start < rest.end && rest.start < $0.end })
        }
        assertConstraints(plan, context)
    }

    func testNoBlocksWithoutFreeTime() {
        let context = context(now: at(23), events: [])
        let plan = StudyDayPlanner.plan(context: context, reviews: [anki])
        XCTAssertTrue(plan.blocks.isEmpty)
        XCTAssertTrue(plan.breaks.isEmpty)
    }

    // MARK: - Method lengths

    func testPreferencesFollowTheStudyMethod() {
        let pomodoro = StudyDayPreferences(method: .pomodoro)
        XCTAssertEqual(pomodoro.studyMinutes, 25)
        XCTAssertEqual(pomodoro.breakMinutes, 5)
        XCTAssertEqual(pomodoro.longBreakMinutes, 15)
        XCTAssertEqual(pomodoro.longBreakEvery, 4)

        let questions = StudyDayPreferences(method: .questionBlock)
        XCTAssertEqual(questions.studyMinutes, 120)
        XCTAssertEqual(questions.breakMinutes, 10)

        let flow = StudyDayPreferences(method: .flowtime)
        XCTAssertEqual(flow.studyMinutes, 45)
        XCTAssertEqual(flow.breakMinutes, 8)

        XCTAssertEqual(StudyDayPreferences(method: .ankiSprint()).studyMinutes, 30)
        XCTAssertEqual(StudyDayPreferences(studyMinutes: 3).studyMinutes, DayPlanner.minimumBlockMinutes)
    }
}
