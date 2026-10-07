import XCTest
import TabbiKitCore

final class TodayTallyTests: XCTestCase {
    private let oct1 = PlannerDayKey(rawValue: "2026-10-01")!

    private func reviews(_ completed: Int, of target: Int) -> [SharedTodayItem] {
        ProviderSnapshot([
            (.anki, ModuleProvision(progress: [ProgressItem(id: "reviews", source: .anki, title: "Anki reviews",
                                                            completed: completed, target: target, unit: "cards")])),
        ]).sharedTodayItems(excluding: .planner)
    }

    func testOwnChecklistAloneMatchesTheDay() throws {
        var day = PlannerDay(date: oct1)
        XCTAssertEqual(TodayTally(day: day, shared: []).summary, "Nothing planned")
        XCTAssertEqual(TodayTally(day: day, shared: []).progress, 0)
        let first = try XCTUnwrap(day.add("One"))
        day.add("Two")
        XCTAssertEqual(TodayTally(day: day, shared: []).summary, "0 of 2 done")
        day.toggle(first.id)
        XCTAssertEqual(TodayTally(day: day, shared: []).summary, "1 of 2 done")
        day.toggle(day.items[1].id)
        XCTAssertEqual(TodayTally(day: day, shared: []).summary, "All 2 done")
    }

    func testShortSummaryCountsDoneOfTotal() throws {
        var day = PlannerDay(date: oct1)
        XCTAssertEqual(TodayTally(day: day, shared: []).shortSummary, "Nothing planned")
        let first = try XCTUnwrap(day.add("One"))
        day.add("Two")
        XCTAssertEqual(TodayTally(day: day, shared: []).shortSummary, "0/2")
        day.toggle(first.id)
        XCTAssertEqual(TodayTally(day: day, shared: reviews(0, of: 80)).shortSummary, "1/3")
        day.toggle(day.items[1].id)
        XCTAssertEqual(TodayTally(day: day, shared: []).shortSummary, "2/2")
    }

    func testPendingReviewsCountAsOneOpenItem() throws {
        var day = PlannerDay(date: oct1)
        let task = try XCTUnwrap(day.add("Pathology lecture notes"))
        day.toggle(task.id)
        let tally = TodayTally(day: day, shared: reviews(112, of: 432))
        XCTAssertEqual(tally.doneCount, 1)
        XCTAssertEqual(tally.totalCount, 2)
        XCTAssertEqual(tally.summary, "1 of 2 done")
        XCTAssertEqual(tally.progress, 0.5)
    }

    func testReviewsCheckThemselvesOffAtZeroDue() throws {
        var day = PlannerDay(date: oct1)
        let task = try XCTUnwrap(day.add("Pathology lecture notes"))
        day.toggle(task.id)
        let shared = reviews(432, of: 432)
        XCTAssertTrue(try XCTUnwrap(shared.first).isDone)
        XCTAssertEqual(TodayTally(day: day, shared: shared).summary, "All 2 done")
        XCTAssertEqual(TodayTally(day: PlannerDay(date: oct1), shared: shared).progress, 1)
    }

    func testReviewsAloneMakeADayWithSomethingPlanned() {
        XCTAssertEqual(TodayTally(day: PlannerDay(date: oct1), shared: reviews(0, of: 80)).summary, "0 of 1 done")
    }
}
