import XCTest
import TabbiKitCore

/// Plan My Day on device: what Today hands the local planner and the
/// working hours it plans in.
final class TodayLocalPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    private func item(_ title: String, done: Bool = false) -> PlannerItem {
        PlannerItem(title: title, isDone: done, createdAt: at(8))
    }

    private let anki = ProgressItem(id: "reviews", source: "anki", title: "Anki reviews", completed: 30,
                                    target: 150, unit: "cards")

    // MARK: - Work

    func testWorkIsReviewsThenChecklistThenSharedTasks() {
        let write = item("Write report")
        let work = TodayPlanSettings().localWork(
            tasks: [write, item("Done already", done: true)],
            sharedTasks: [ProvidedTask(id: "daily", source: "leetcode", title: "Two Sum", estimatedMinutes: 20),
                          ProvidedTask(id: "old", source: "leetcode", title: "Old", isDone: true)],
            progress: [anki])

        XCTAssertEqual(work.map(\.title), ["Anki reviews", "Write report", "Two Sum"])
        XCTAssertEqual(work[0].kind, .reviews)
        XCTAssertEqual(work[0].estimatedMinutes, 20, "120 cards at 10 s each")
        XCTAssertEqual(work[1].linkedTaskID, write.id)
        XCTAssertNil(work[1].estimatedMinutes)
        XCTAssertEqual(work[2].estimatedMinutes, 20)
        XCTAssertEqual(Set(work.map(\.id)).count, 3, "ids stay apart across sources")
    }

    func testGoalsThatAreMetOrOnlyAimedForAreNotWork() {
        let met = ProgressItem(id: "met", source: "anki", title: "Done", completed: 50, target: 50, unit: "cards")
        let aim = ProgressItem(id: "focus", source: "study", title: "Focus goal", completed: 0, target: 120,
                               unit: "min", waitsForStart: true)
        XCTAssertEqual(TodayPlanSettings().localWork(tasks: [], progress: [met, aim]), [])
    }

    func testReviewLengthFollowsTheKitsSecondsPerCard() {
        let work = TodayPlanSettings(secondsPerCard: 20).localWork(tasks: [], progress: [anki])
        XCTAssertEqual(work.first?.estimatedMinutes, 40)
    }

    // MARK: - Working hours

    func testWorkingHoursRunFromNineToTheKitsEndOfDay() {
        let preferences = TodayPlanSettings(eventBufferMinutes: 15, dayEndHour: 21)
            .schedulePreferences(now: at(8), calendar: calendar)
        XCTAssertEqual(preferences.workdayStartMinute, 9 * 60)
        XCTAssertEqual(preferences.workdayEndMinute, 21 * 60)
        XCTAssertEqual(preferences.eventBufferMinutes, 15)
    }

    func testPlanningLateStillLeavesTwoHours() {
        let preferences = TodayPlanSettings().schedulePreferences(now: at(19, 30), calendar: calendar)
        XCTAssertEqual(preferences.workdayEndMinute, 21 * 60 + 30)
    }

    func testAnEarlyEndOfDayMovesTheStartBack() {
        let preferences = TodayPlanSettings(dayEndHour: 8).schedulePreferences(now: at(5), calendar: calendar)
        XCTAssertEqual(preferences.workdayEndMinute, 8 * 60)
        XCTAssertEqual(preferences.workdayStartMinute, 6 * 60)
    }

    // MARK: - The plan

    func testPlansReviewsFirstAroundTheCalendarWithReasons() {
        let write = item("Write report")
        let standup = UpcomingEvent(id: "standup", title: "Standup", start: at(10), end: at(10, 30))
        let plan = TodayPlanSettings().localPlan(now: at(8, 50), events: [standup], tasks: [write],
                                                 progress: [anki], calendar: calendar, locale: locale)

        XCTAssertEqual(plan.blocks.map(\.block.title), ["Anki reviews", "Write report"])
        XCTAssertEqual(plan.blocks[0].block.start, at(9))
        XCTAssertEqual(plan.blocks[0].block.end, at(9, 20))
        XCTAssertEqual(plan.blocks[0].reason, "Reviews first, while you are fresh")
        // After the 5 minute break only 25 minutes are left before the
        // standup's 10 minute buffer, so the 30 minute task waits until after it.
        XCTAssertEqual(plan.blocks[1].block.start, at(10, 40))
        XCTAssertEqual(plan.blocks[1].block.end, at(11, 10))
        XCTAssertEqual(plan.blocks[1].block.linkedTaskID, write.id)
        XCTAssertEqual(plan.blocks[1].reason, "Next on your list")
        XCTAssertEqual(plan.breaks, [], "the standup already breaks up the two blocks")
        XCTAssertTrue(plan.unplaced.isEmpty)
        XCTAssertEqual(plan.proposal.pending.count, 2)
    }

    func testNothingToPlanAfterTheDayIsOver() {
        let plan = TodayPlanSettings().localPlan(now: at(22, 30), events: [], tasks: [item("Late task")],
                                                 calendar: calendar, locale: locale)
        XCTAssertTrue(plan.blocks.isEmpty)
        XCTAssertEqual(plan.unplaced.map(\.work.title), ["Late task"])
        XCTAssertTrue(plan.proposal.isSettled)
    }

    func testTheDemoPlanShowsAFullDayAtAnyHour() {
        let now = at(22, 30)
        let call = UpcomingEvent(id: "call", title: "Call", start: now.addingTimeInterval(30 * 60),
                                 end: now.addingTimeInterval(60 * 60))
        let plan = TodayPlanSettings().sampleLocalPlan(
            now: now, events: [call], tasks: [item("Write report"), item("Email Sam"), item("Plan sprint")],
            progress: [anki], calendar: calendar, locale: locale)

        XCTAssertEqual(plan.blocks.count, 4)
        XCTAssertTrue(plan.unplaced.isEmpty)
        // Moved back to now: the first block starts on the next slot, and
        // nothing touches the call or its buffer.
        XCTAssertEqual(plan.blocks.first?.block.start, now)
        for block in plan.blocks.map(\.block) {
            XCTAssertFalse(block.start < call.end.addingTimeInterval(600) && call.start.addingTimeInterval(-600) < block.end)
        }
    }
}
