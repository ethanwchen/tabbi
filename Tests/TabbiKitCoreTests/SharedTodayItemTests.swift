import XCTest
@testable import TabbiKitCore

final class SharedTodayItemTests: XCTestCase {
    private func progress(_ id: String, _ completed: Int, of target: Int) -> ProgressItem {
        ProgressItem(id: id, source: ModuleID("unset"), title: id, completed: completed, target: target, unit: "cards")
    }

    func testOwnItemsAreLeftOutAndGoalsComeBeforeTasks() {
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(tasks: [ProvidedTask(id: "mine", source: .planner, title: "Mine")],
                                       progress: [progress("own", 1, of: 2)])),
            (.study, ModuleProvision(tasks: [ProvidedTask(id: "pomodoro", source: .study, title: "Pomodoro",
                                                          estimatedMinutes: 25)])),
            (.anki, ModuleProvision(progress: [progress("reviews", 112, of: 432)])),
        ])
        let items = snapshot.sharedTodayItems(excluding: .planner)
        XCTAssertEqual(items.map(\.title), ["reviews", "Pomodoro"])
        XCTAssertEqual(items.map(\.source), [.anki, .study])
        XCTAssertEqual(items[0].detail, "320 cards left")
        XCTAssertEqual(items[0].fraction ?? 0, 112.0 / 432, accuracy: 0.0001)
        XCTAssertFalse(items[0].isDone)
        XCTAssertEqual(items[1].detail, "25 min")
        XCTAssertNil(items[1].fraction)
    }

    func testPlannableWorkListsOnlyOtherModulesUnfinishedWork() {
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(tasks: [ProvidedTask(id: "mine", source: .planner, title: "Mine")])),
            (.study, ModuleProvision(tasks: [
                ProvidedTask(id: "pomodoro", source: .study, title: "Pomodoro", estimatedMinutes: 25),
                ProvidedTask(id: "done", source: .study, title: "Done", isDone: true),
            ])),
            (.anki, ModuleProvision(progress: [progress("Anki reviews", 112, of: 432), progress("met", 5, of: 5),
                                               progress("empty", 0, of: 0)])),
        ])
        XCTAssertEqual(snapshot.plannableWork(excluding: .planner),
                       ["Anki reviews (320 cards left)", "Pomodoro (about 25 min)"])
        XCTAssertEqual(ProviderSnapshot().plannableWork(excluding: .planner), [])
    }

    func testGoalsWithNothingDueTodayAreHiddenAndMetGoalsCountAsDone() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision(progress: [progress("empty", 0, of: 0), progress("met", 50, of: 50)])),
        ])
        let items = snapshot.sharedTodayItems(excluding: .planner)
        XCTAssertEqual(items.map(\.title), ["met"])
        XCTAssertTrue(items[0].isDone)
        XCTAssertEqual(items[0].detail, "50 cards")
    }

    func testIdsStayUniqueAcrossModulesAndKinds() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision(tasks: [ProvidedTask(id: "x", source: .anki, title: "x")],
                                    progress: [progress("x", 0, of: 1)])),
            (.study, ModuleProvision(tasks: [ProvidedTask(id: "x", source: .study, title: "x")])),
        ])
        let ids = snapshot.sharedTodayItems(excluding: .planner).map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
    }

    func testAnkiSummaryProgressCountsReviewedPlusDue() {
        let summary = AnkiSummary.demo()
        let item = summary.progressItem()
        XCTAssertEqual(item.source, .anki)
        XCTAssertEqual(item.completed, summary.reviewedToday)
        XCTAssertEqual(item.target, summary.reviewedToday + summary.dueTotal)
        XCTAssertEqual(item.remaining, summary.dueTotal)
        XCTAssertEqual(item.unit, "cards")
    }
}
