import XCTest
@testable import NotchKitCore

final class ProviderSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ id: String, startsIn minutes: Double) -> UpcomingEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return UpcomingEvent(id: id, title: id, start: start, end: start.addingTimeInterval(1800))
    }

    private func task(_ id: String, done: Bool = false) -> ProvidedTask {
        ProvidedTask(id: id, source: ModuleID("unset"), title: id, isDone: done)
    }

    func testEmptySnapshotHasNothing() {
        let snapshot = ProviderSnapshot([])
        XCTAssertEqual(snapshot, ProviderSnapshot())
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertNil(snapshot.focus)
    }

    func testTasksKeepTabOrderAndAreStampedWithTheirSource() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision(tasks: [task("due")])),
            (.planner, ModuleProvision(tasks: [task("a"), task("b", done: true)])),
        ])
        XCTAssertEqual(snapshot.tasks.map(\.id), ["due", "a", "b"])
        XCTAssertEqual(snapshot.tasks.map(\.source), [.anki, .planner, .planner])
        XCTAssertEqual(snapshot.openTasks.map(\.id), ["due", "a"])
    }

    func testRepeatedTaskIdIsKeptOncePerModuleButNotAcrossModules() {
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(tasks: [task("x"), task("x")])),
            (.anki, ModuleProvision(tasks: [task("x")])),
        ])
        XCTAssertEqual(snapshot.tasks.map(\.source), [.planner, .anki])
    }

    func testEventsMergeByStartTimeAndDropRepeatedIds() {
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(events: [event("standup", startsIn: 30), event("lunch", startsIn: 120)])),
            (.study, ModuleProvision(events: [event("lecture", startsIn: 60), event("standup", startsIn: 30)])),
        ])
        XCTAssertEqual(snapshot.events.map(\.id), ["standup", "lecture", "lunch"])
    }

    func testEventsWithEqualStartsKeepTabOrder() {
        let snapshot = ProviderSnapshot([
            (.study, ModuleProvision(events: [event("b", startsIn: 10)])),
            (.planner, ModuleProvision(events: [event("a", startsIn: 10)])),
        ])
        XCTAssertEqual(snapshot.events.map(\.id), ["b", "a"])
    }

    func testActiveFocusTimerBeatsAnIdleOneEarlierInTabOrder() {
        let idle = FocusTimer()
        var running = FocusTimer()
        running.start(at: now)
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision(focus: idle)),
            (.study, ModuleProvision(focus: running)),
        ])
        XCTAssertEqual(snapshot.focus, running)
    }

    func testIdleFocusTimerIsKeptWhenNoneIsActive() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision()),
            (.planner, ModuleProvision(focus: FocusTimer())),
        ])
        XCTAssertEqual(snapshot.focus, FocusTimer())
    }

    func testProgressIsMergedInTabOrder() {
        let cards = ProgressItem(id: "due", source: ModuleID("unset"), title: "Anki reviews",
                                 completed: 112, target: 340, unit: "cards")
        let snapshot = ProviderSnapshot([(.anki, ModuleProvision(progress: [cards, cards]))])
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertEqual(snapshot.progress.first?.source, .anki)
    }

    func testProgressMath() {
        var item = ProgressItem(id: "q", source: .study, title: "Questions", completed: 30, target: 40, unit: "questions")
        XCTAssertEqual(item.remaining, 10)
        XCTAssertEqual(item.fraction, 0.75, accuracy: 1e-9)
        XCTAssertFalse(item.isComplete)
        item.completed = 55
        XCTAssertEqual(item.remaining, 0)
        XCTAssertEqual(item.fraction, 1)
        XCTAssertTrue(item.isComplete)
        item.target = 0
        XCTAssertEqual(item.fraction, 1)
    }

    func testChecklistItemBecomesAProvidedTask() {
        let item = PlannerItem(title: "Ship beta", isDone: true, createdAt: now)
        let provided = item.provided(by: .planner)
        XCTAssertEqual(provided.id, item.id.uuidString)
        XCTAssertEqual(provided.source, .planner)
        XCTAssertEqual(provided.title, "Ship beta")
        XCTAssertTrue(provided.isDone)
    }
}
