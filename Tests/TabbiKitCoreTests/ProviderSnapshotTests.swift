import XCTest
@testable import TabbiKitCore

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
            (.planner, ModuleProvision(focus: idle.shared)),
            (.study, ModuleProvision(focus: running.shared)),
        ])
        XCTAssertEqual(snapshot.focus, running.provided(by: .study))
        XCTAssertEqual(snapshot.focus?.source, .study)
    }

    private func clock(_ clock: ProvidedFocus.Clock) -> ProvidedFocus {
        ProvidedFocus(source: ModuleID("unset"), phase: .focus, clock: clock, phaseLength: 1500)
    }

    func testRunningFocusClockBeatsAPausedOneEarlierInTabOrder() {
        let snapshot = ProviderSnapshot([
            (.focus, ModuleProvision(focus: clock(.paused(shown: 600)))),
            (.study, ModuleProvision(focus: clock(.countUp(since: now)))),
        ])
        XCTAssertEqual(snapshot.focus?.source, .study)
    }

    func testMostRecentlyStartedRunningClockWins() {
        let provisions: [(module: ModuleID, provision: ModuleProvision)] = [
            (.focus, ModuleProvision(focus: clock(.countdown(endsAt: now.addingTimeInterval(1200))))),
            (.study, ModuleProvision(focus: clock(.countUp(since: now)))),
        ]
        let studyLater = ProviderSnapshot(provisions, focusStarts: [.focus: now, .study: now.addingTimeInterval(60)])
        XCTAssertEqual(studyLater.focus?.source, .study)
        let focusLater = ProviderSnapshot(provisions, focusStarts: [.focus: now.addingTimeInterval(60), .study: now])
        XCTAssertEqual(focusLater.focus?.source, .focus)
    }

    func testRunningClocksWithNoKnownStartGoByTabOrder() {
        let provisions: [(module: ModuleID, provision: ModuleProvision)] = [
            (.study, ModuleProvision(focus: clock(.countUp(since: now)))),
            (.focus, ModuleProvision(focus: clock(.countdown(endsAt: now.addingTimeInterval(1200))))),
        ]
        XCTAssertEqual(ProviderSnapshot(provisions).focus?.source, .study)
        // A known start beats one restored with no start.
        XCTAssertEqual(ProviderSnapshot(provisions, focusStarts: [.focus: now]).focus?.source, .focus)
    }

    func testStartOfAPausedClockDoesNotCount() {
        let snapshot = ProviderSnapshot([
            (.study, ModuleProvision(focus: clock(.countUp(since: now)))),
            (.focus, ModuleProvision(focus: clock(.paused(shown: 600)))),
        ], focusStarts: [.focus: now.addingTimeInterval(60)])
        XCTAssertEqual(snapshot.focus?.source, .study)
    }

    func testIdleFocusTimerIsKeptWhenNoneIsActive() {
        let snapshot = ProviderSnapshot([
            (.anki, ModuleProvision()),
            (.planner, ModuleProvision(focus: FocusTimer().shared)),
        ])
        XCTAssertEqual(snapshot.focus, FocusTimer().shared)
    }

    func testProgressIsMergedInTabOrder() {
        let cards = ProgressItem(id: "due", source: ModuleID("unset"), title: "Anki reviews",
                                 completed: 112, target: 340, unit: "cards")
        let snapshot = ProviderSnapshot([(.anki, ModuleProvision(progress: [cards, cards]))])
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertEqual(snapshot.progress.first?.source, .anki)
    }

    func testStudyTalliesAddUpAcrossModules() {
        XCTAssertNil(ProviderSnapshot([(.anki, ModuleProvision())]).study, "no module keeps a tally")
        let snapshot = ProviderSnapshot([
            (.study, ModuleProvision(study: StudyDayTally(minutes: 100, sessions: 2, points: 120))),
            (.anki, ModuleProvision()),
            (.focus, ModuleProvision(study: StudyDayTally(minutes: 25, sessions: 1, points: 35))),
        ])
        XCTAssertEqual(snapshot.study, StudyDayTally(minutes: 125, sessions: 3, points: 155))
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
