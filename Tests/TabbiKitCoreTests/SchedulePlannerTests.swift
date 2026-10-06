import XCTest
import TabbiKitCore

final class SchedulePlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    /// 2026-10-05 (a Monday) plus `day` days, at `hour:minute` Los Angeles time.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    private func task(_ title: String, _ minutes: Int? = nil, _ priority: SchedulePriority = .normal,
                      due: Date? = nil) -> ScheduleWork {
        ScheduleWork(id: title, title: title, estimatedMinutes: minutes, priority: priority, due: due)
    }

    private func plan(now: Date, events: [UpcomingEvent] = [], work: [ScheduleWork],
                      preferences: SchedulePreferences = SchedulePreferences()) -> SchedulePlan {
        SchedulePlanner.planDay(now: now, events: events, work: work, preferences: preferences,
                                calendar: calendar, locale: locale)
    }

    /// Blocks never overlap each other or a buffered event, never start
    /// before `now`, and stay inside working hours.
    private func assertSound(_ plan: SchedulePlan, now: Date, events: [UpcomingEvent],
                             preferences: SchedulePreferences = SchedulePreferences(),
                             file: StaticString = #filePath, line: UInt = #line) {
        let blocks = plan.blocks.map(\.block)
        for (a, b) in zip(blocks, blocks.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start, "\(a.title) overlaps \(b.title)", file: file, line: line)
        }
        let buffer = TimeInterval(preferences.eventBufferMinutes * 60)
        let midnight = calendar.startOfDay(for: plan.day)
        for block in blocks {
            XCTAssertGreaterThanOrEqual(block.start, now, file: file, line: line)
            XCTAssertGreaterThanOrEqual(block.start, SchedulePlanner.clockTime(preferences.workdayStartMinute, on: midnight,
                                                                               calendar: calendar), file: file, line: line)
            XCTAssertLessThanOrEqual(block.end, SchedulePlanner.clockTime(preferences.workdayEndMinute, on: midnight,
                                                                          calendar: calendar), file: file, line: line)
            XCTAssertGreaterThanOrEqual(block.end.timeIntervalSince(block.start), 15 * 60, file: file, line: line)
            for event in events where !event.isAllDay {
                XCTAssertFalse(block.start < event.end.addingTimeInterval(buffer)
                               && event.start.addingTimeInterval(-buffer) < block.end,
                               "\(block.title) touches \(event.title)", file: file, line: line)
            }
        }
    }

    // MARK: - Free time

    func testFreeTimeRespectsWorkingHoursBuffersAndAllDayEvents() {
        let events = [event("Standup", at(10), at(10, 30)), event("Holiday", at(0), at(23, 59), allDay: true)]
        let free = SchedulePlanner.freeTime(day: at(0), now: at(7), events: events, calendar: calendar)
        XCTAssertEqual(free, [DateInterval(start: at(9), end: at(9, 50)), DateInterval(start: at(10, 40), end: at(18))])
    }

    func testFreeTimeKeepsClockHoursOnADaylightSavingChange() {
        // Clocks go back at 2:00 on 2026-11-01 in Los Angeles.
        let free = SchedulePlanner.freeTime(day: at(0, day: 27), now: at(7, day: 27), events: [], calendar: calendar)
        XCTAssertEqual(free, [DateInterval(start: at(9, day: 27), end: at(18, day: 27))])
    }

    func testFreeTimeStartsOnTheNextSlotAfterNow() {
        let free = SchedulePlanner.freeTime(day: at(0), now: at(14, 2), events: [], calendar: calendar)
        XCTAssertEqual(free.first?.start, at(14, 5))
    }

    func testFreeTimeIsEmptyAfterHours() {
        XCTAssertTrue(SchedulePlanner.freeTime(day: at(0), now: at(19), events: [], calendar: calendar).isEmpty)
        let result = plan(now: at(19), work: [task("Email")])
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.unplaced.map(\.reason), ["No free time left today"])
    }

    func testSliversTooShortForABlockAreDropped() {
        // 9:00 to 9:20 minus a 10 min buffer before the meeting leaves 10 min.
        let events = [event("Sync", at(9, 20), at(17))]
        let free = SchedulePlanner.freeTime(day: at(0), now: at(8), events: events, calendar: calendar)
        XCTAssertEqual(free, [DateInterval(start: at(17, 10), end: at(18))])
    }

    // MARK: - Overlaps and buffers

    func testBlocksNeverOverlapEventsAndKeepTheirBuffer() {
        let events = [event("Standup", at(9, 30), at(9, 45)), event("Lunch", at(12), at(13)),
                      event("1:1", at(14), at(14, 30))]
        let work = [task("Design review", 90), task("Write spec", 120), task("Inbox", 30), task("Bugs", 60)]
        let result = plan(now: at(8), events: events, work: work)
        assertSound(result, now: at(8), events: events)
        XCTAssertFalse(result.blocks.isEmpty)
        // The first block waits for the buffer after standup since 9:00-9:20 is too short.
        XCTAssertEqual(result.blocks.first?.block.start, at(9, 55))
    }

    func testZeroBufferPacksRightUpToEvents() {
        let events = [event("Meeting", at(10), at(11))]
        let preferences = SchedulePreferences(eventBufferMinutes: 0)
        let result = plan(now: at(9), events: events, work: [task("Report", 60)], preferences: preferences)
        XCTAssertEqual(result.blocks.map(\.block.start), [at(9)])
        XCTAssertEqual(result.blocks.first?.block.end, at(10))
    }

    func testEventInProgressBlocksUntilItEndsPlusBuffer() {
        let events = [event("Workshop", at(13), at(15))]
        let result = plan(now: at(14), events: events, work: [task("Notes", 30)])
        XCTAssertEqual(result.blocks.first?.block.start, at(15, 10))
    }

    func testNothingIsPlannedInThePast() {
        let result = plan(now: at(11, 7), work: [task("A", 30), task("B", 30)])
        assertSound(result, now: at(11, 7), events: [])
        XCTAssertEqual(result.blocks.first?.block.start, at(11, 10))
    }

    // MARK: - Breaks

    func testBreaksSeparateConsecutiveBlocks() {
        let result = plan(now: at(9), work: [task("A", 30), task("B", 30), task("C", 30)])
        XCTAssertEqual(result.blocks.map(\.block.start), [at(9), at(9, 35), at(10, 10)])
        XCTAssertEqual(result.breaks, [DateInterval(start: at(9, 30), end: at(9, 35)),
                                       DateInterval(start: at(10, 5), end: at(10, 10))])
    }

    func testEveryFourthBreakIsLong() {
        let work = (1...5).map { task("Task \($0)", 25) }
        let result = plan(now: at(9), work: work)
        let lengths = result.breaks.map { Int($0.duration / 60) }
        XCTAssertEqual(lengths, [5, 5, 5, 15])
    }

    func testNoBreakIsShownAcrossAnEvent() {
        let events = [event("Meeting", at(10), at(11))]
        let preferences = SchedulePreferences(eventBufferMinutes: 0)
        let result = plan(now: at(9), events: events, work: [task("A", 60), task("B", 60)], preferences: preferences)
        XCTAssertEqual(result.blocks.map(\.block.start), [at(9), at(11)])
        XCTAssertTrue(result.breaks.isEmpty)
    }

    // MARK: - Ordering

    func testHigherPriorityGoesFirstAndTiesKeepListOrder() {
        let work = [task("Low", 30, .low), task("First", 30), task("Urgent", 30, .high), task("Second", 30)]
        let result = plan(now: at(9), work: work)
        XCTAssertEqual(result.blocks.map(\.block.title), ["Urgent", "First", "Second", "Low"])
        XCTAssertEqual(result.blocks.map(\.reason),
                       ["High priority", "Next on your list", "Next on your list", "Low priority, after the rest"])
    }

    func testTimeSensitiveWorkComesFirstAndFinishesBeforeItsDueTime() {
        let work = [task("Big project", 90, .high), task("Submit form", 30, due: at(11)),
                    task("Pay invoice", 15, due: at(10))]
        let result = plan(now: at(9), work: work)
        XCTAssertEqual(result.blocks.prefix(2).map(\.block.title), ["Pay invoice", "Submit form"])
        let form = result.blocks.first { $0.workID == "Submit form" }!
        XCTAssertLessThanOrEqual(form.block.end, at(11))
        XCTAssertEqual(form.reason, "Due by 11:00")
    }

    func testWorkThatCannotMeetItsDueTimeIsListedWithTheReason() {
        let events = [event("Offsite", at(9), at(12))]
        let result = plan(now: at(8), events: events, work: [task("Prep slides", 60, due: at(11))])
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertEqual(result.unplaced.first?.reason, "No free time before 11:00")
        XCTAssertEqual(result.unplaced.first?.minutes, 60)
    }

    func testReviewsComeFirstByDefaultAndLastWhenAsked() {
        let reviews = ScheduleWork(reviews: StudyReviewWork(title: "Anki reviews", minutes: 40), id: "anki")
        let work = [task("Pharm", 50), reviews]
        let early = plan(now: at(9), work: work)
        XCTAssertEqual(early.blocks.first?.block.kind, .reviews)
        XCTAssertEqual(early.blocks.first?.reason, "Reviews first, while you are fresh")
        let late = plan(now: at(9), work: work, preferences: SchedulePreferences(reviewsFirst: false))
        XCTAssertEqual(late.blocks.map(\.block.title), ["Pharm", "Anki reviews"])
    }

    func testTasksWithoutAnEstimateUseTheDefaultLength() {
        let result = plan(now: at(9), work: [task("Call bank")])
        XCTAssertEqual(result.blocks.first?.block.end, at(9, 30))
    }

    func testChecklistItemsLinkTheirBlocks() {
        let item = PlannerItem(title: "  Draft   notes ", createdAt: at(8))
        let result = plan(now: at(9), work: [ScheduleWork(task: item)])
        XCTAssertEqual(result.blocks.first?.block.linkedTaskID, item.id)
        XCTAssertEqual(result.blocks.first?.block.title, "Draft notes")
    }

    func testBlankTitlesAreIgnored() {
        XCTAssertEqual(plan(now: at(9), work: [task("   ", 30)]), plan(now: at(9), work: []))
    }

    // MARK: - Splitting and limits

    func testLongWorkIsSplitIntoNumberedParts() {
        let result = plan(now: at(9), work: [task("Thesis", 150)])
        XCTAssertEqual(result.blocks.map { Int($0.block.end.timeIntervalSince($0.block.start) / 60) }, [90, 60])
        XCTAssertEqual(result.blocks.map(\.part), [1, 2])
        XCTAssertEqual(result.blocks.map(\.parts), [2, 2])
    }

    func testWorkJustOverTheLongestBlockSplitsWithoutASliver() {
        for (minutes, lengths) in [(95, [80, 15]), (100, [85, 15])] {
            let result = plan(now: at(9), work: [task("Thesis", minutes)])
            XCTAssertEqual(result.blocks.map { Int($0.block.end.timeIntervalSince($0.block.start) / 60) }, lengths)
            XCTAssertTrue(result.unplaced.isEmpty, "\(minutes) min left some out")
        }
    }

    func testWorkFitsWholeInALaterGapBeforeItSplits() {
        let events = [event("Standup", at(10), at(10, 30))]
        let result = plan(now: at(9), events: events, work: [task("Refactor", 60)])
        XCTAssertEqual(result.blocks.map(\.block.start), [at(10, 40)])
    }

    func testWorkSplitsAcrossGapsWithoutLeavingASliver() {
        // Free 9:00-9:50 and 10:40-11:20 only. 60 min of work: 45 and 15, not 50 and 10.
        let events = [event("Standup", at(10), at(10, 30)), event("Offsite", at(11, 30), at(18))]
        let result = plan(now: at(9), events: events, work: [task("Refactor", 60)])
        XCTAssertEqual(result.blocks.map(\.block.start), [at(9), at(10, 40)])
        XCTAssertEqual(result.blocks.map { Int($0.block.end.timeIntervalSince($0.block.start) / 60) }, [45, 15])
    }

    func testFocusLimitCapsTheDayAndListsTheRest() {
        let preferences = SchedulePreferences(maximumFocusMinutes: 120)
        let result = plan(now: at(9), work: [task("A", 90), task("B", 60)], preferences: preferences)
        XCTAssertEqual(result.focusMinutes, 120)
        XCTAssertEqual(result.unplaced.map(\.minutes), [30])
        XCTAssertEqual(result.unplaced.first?.reason, "Over your 2 h focus limit")
    }

    func testOverflowListsWhatDidNotFit() {
        let preferences = SchedulePreferences(workdayStartMinute: 16 * 60, workdayEndMinute: 17 * 60)
        let result = plan(now: at(9), work: [task("A", 45), task("B", 45)], preferences: preferences)
        XCTAssertEqual(result.blocks.map(\.block.title), ["A"])
        XCTAssertEqual(result.unplaced.map(\.work.title), ["B"])
        XCTAssertEqual(result.unplaced.first?.reason, "No free time left today")
    }

    func testCustomWorkingHours() {
        let preferences = SchedulePreferences(workdayStartMinute: 7 * 60 + 30, workdayEndMinute: 12 * 60)
        let result = plan(now: at(6), work: [task("Run", 30)], preferences: preferences)
        XCTAssertEqual(result.blocks.first?.block.start, at(7, 30))
        assertSound(result, now: at(6), events: [], preferences: preferences)
    }

    func testPreferencesClampNonsense() {
        let preferences = SchedulePreferences(workdayStartMinute: -50, workdayEndMinute: -10, defaultTaskMinutes: 1,
                                              maximumBlockMinutes: 0, breakMinutes: -5, maximumFocusMinutes: 0)
        XCTAssertEqual(preferences.workdayStartMinute, 0)
        XCTAssertGreaterThan(preferences.workdayEndMinute, preferences.workdayStartMinute)
        XCTAssertEqual(preferences.defaultTaskMinutes, 15)
        XCTAssertEqual(preferences.maximumBlockMinutes, 15)
        XCTAssertEqual(preferences.breakMinutes, 0)
        XCTAssertEqual(preferences.maximumFocusMinutes, 15)
    }

    func testStudyMethodSetsBlockAndBreakLengths() {
        let preferences = SchedulePreferences(method: .pomodoro)
        XCTAssertEqual(preferences.defaultTaskMinutes, 25)
        XCTAssertEqual(preferences.breakMinutes, 5)
    }

    // MARK: - A realistic day

    func testBusyDayIsSoundAndDeterministic() {
        let events = [event("Standup", at(9, 30), at(9, 45)), event("Lunch", at(12), at(13)),
                      event("Design crit", at(15), at(16)), event("Exam week", at(0), at(23, 59), allDay: true)]
        let work = [ScheduleWork(reviews: StudyReviewWork(title: "Anki reviews", minutes: 30), id: "anki"),
                    task("Write spec", 120, .high), task("Inbox", 20), task("Expense report", 30, due: at(14)),
                    task("Read paper", 60, .low)]
        let first = plan(now: at(8, 50), events: events, work: work)
        let second = plan(now: at(8, 50), events: events, work: work)
        XCTAssertEqual(first.blocks.map(\.block.title), second.blocks.map(\.block.title))
        XCTAssertEqual(first.blocks.map(\.block.start), second.blocks.map(\.block.start))
        assertSound(first, now: at(8, 50), events: events)
        // Inbox fills the short gap before standup; reviews take the first gap that holds them.
        XCTAssertEqual(first.blocks.first?.block.title, "Inbox")
        XCTAssertEqual(first.blocks.first { $0.block.kind == .reviews }?.block.start, at(9, 55))
        XCTAssertTrue(first.unplaced.isEmpty)
        XCTAssertEqual(first.proposal.pending.count, first.blocks.count)
    }

    // MARK: - Week

    func testWeekSpreadsLeftoversOverFollowingDays() {
        let preferences = SchedulePreferences(maximumFocusMinutes: 120)
        let work = [task("A", 120), task("B", 120), task("C", 60)]
        let week = SchedulePlanner.planWeek(now: at(9), days: 3, events: [], work: work, preferences: preferences,
                                            calendar: calendar, locale: locale)
        XCTAssertEqual(week.days.count, 3)
        XCTAssertEqual(week.days.map(\.focusMinutes), [120, 120, 60])
        XCTAssertEqual(week.days[1].blocks.first?.block.start, at(9, day: 1))
        XCTAssertTrue(week.unplaced.isEmpty)
        XCTAssertTrue(week.days.allSatisfy(\.unplaced.isEmpty))
    }

    func testWeekRespectsEachDaysEventsAndListsWhatNeverFit() {
        let preferences = SchedulePreferences(maximumFocusMinutes: 60)
        let events = [event("Conference", at(8, day: 1), at(19, day: 1))]
        let work = [task("A", 60), task("B", 60), task("C", 60)]
        let week = SchedulePlanner.planWeek(now: at(9), days: 2, events: events, work: work, preferences: preferences,
                                            calendar: calendar, locale: locale)
        XCTAssertEqual(week.days.map { $0.blocks.map(\.block.title) }, [["A"], []])
        XCTAssertEqual(week.unplaced.map(\.work.title), ["B", "C"])
        XCTAssertEqual(week.unplaced.first?.reason, "No free time left this week")
    }

    func testWeekKeepsDueWorkBeforeItsDueDay() {
        let events = [event("Busy", at(9), at(18))]
        let work = [task("Tax form", 30, due: at(12, day: 1))]
        let week = SchedulePlanner.planWeek(now: at(9), days: 3, events: events, work: work, calendar: calendar,
                                            locale: locale)
        XCTAssertEqual(week.days[1].blocks.first?.block.start, at(9, day: 1))
        XCTAssertLessThanOrEqual(week.days[1].blocks.first!.block.end, at(12, day: 1))
    }

    // MARK: - Already on the calendar

    func testWorkAlreadyOnTodaysCalendarIsNotPlannedAgain() {
        // Added from an earlier plan this morning, so it's past but done for today.
        let events = [event("Write the spec", at(9), at(10)), event("Standup", at(10), at(10, 30)),
                      event("Gym", at(0), at(0), allDay: true)]
        let work = [task("write  the SPEC", 60), task("Email Ana", 30), task("Gym", 30)]
        let result = plan(now: at(11), events: events, work: work)
        XCTAssertEqual(result.blocks.map(\.block.title), ["Email Ana", "Gym"])
        XCTAssertTrue(result.unplaced.isEmpty)
    }

    func testEventOnAnotherDayDoesNotHideTodaysWork() {
        let events = [event("Write the spec", at(9, day: 1), at(10, day: 1))]
        let result = plan(now: at(9), events: events, work: [task("Write the spec", 60)])
        XCTAssertEqual(result.blocks.map(\.block.title), ["Write the spec"])
    }

    func testWeekSkipsWorkBookedLaterInTheWeek() {
        let events = [event("Write the spec", at(14, day: 3), at(15, day: 3))]
        let work = [task("Write the spec", 60), task("Email Ana", 30)]
        let inWeek = SchedulePlanner.planWeek(now: at(9), days: 7, events: events, work: work,
                                              calendar: calendar, locale: locale)
        XCTAssertEqual(inWeek.days.flatMap { $0.blocks.map(\.block.title) }, ["Email Ana"])
        let shorter = SchedulePlanner.planWeek(now: at(9), days: 2, events: events, work: work,
                                               calendar: calendar, locale: locale)
        XCTAssertEqual(shorter.days.flatMap { $0.blocks.map(\.block.title) }, ["Write the spec", "Email Ana"])
    }
}
