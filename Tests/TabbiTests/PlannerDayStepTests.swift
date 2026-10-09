import XCTest
import TabbiKitCore
@testable import Tabbi

/// Today's checklist stepped to yesterday and tomorrow: what each shows,
/// where edits land, and what reaches disk.
@MainActor
final class PlannerDayStepTests: XCTestCase {
    private var folder: URL!
    private var repository: PlannerRepository!
    private let today = PlannerDayKey(date: Date())
    private var yesterday: PlannerDayKey { today.adding(days: -1) }
    private var tomorrow: PlannerDayKey { today.adding(days: 1) }

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlannerDayStepTests-\(UUID().uuidString)", isDirectory: true)
        repository = PlannerRepository(storage: EditionStorage(root: folder))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore(runMode: RunMode = .live) -> PlannerStore {
        PlannerStore(focus: FocusStore(runMode: .demo), storage: EditionStorage(root: folder), runMode: runMode)
    }

    /// Yesterday with one finished task, one carried to today when it
    /// opens, and, once today exists, one more added to yesterday's file
    /// after that (as if from another Mac), which today doesn't have.
    private func seedYesterday() throws -> (left: PlannerItem, carried: PlannerItem) {
        var day = PlannerDay(date: yesterday)
        let carried = try XCTUnwrap(day.add("Carried"))
        let done = try XCTUnwrap(day.add("Done"))
        day.toggle(done.id)
        try repository.save(day)
        _ = try repository.open(today)
        let left = try XCTUnwrap(day.add("Left behind"))
        try repository.save(day)
        return (left, carried)
    }

    func testOpensOnTodayAndStepsOneDayEachWay() {
        let store = makeStore()
        XCTAssertEqual(store.viewing, .today)
        XCTAssertEqual(store.shownDay.date, today)

        store.show(.tomorrow)
        XCTAssertEqual(store.shownDay.date, tomorrow)
        XCTAssertNil(store.viewing.next)
        store.show(.yesterday)
        XCTAssertEqual(store.shownDay.date, yesterday)
        XCTAssertNil(store.viewing.previous)
        XCTAssertEqual(store.day.date, today, "today's list stays what other modules see")
    }

    func testYesterdayIsReadOnlyAndOffersOnlyWhatTodayLacks() throws {
        let (left, carried) = try seedYesterday()
        let store = makeStore()
        XCTAssertTrue(store.day.items.contains { $0.id == carried.id })

        store.show(.yesterday)
        XCTAssertFalse(store.canEdit)
        XCTAssertEqual(store.items.map(\.title), ["Carried", "Done", "Left behind"])
        XCTAssertEqual(store.leftovers.map(\.id), [left.id])
        XCTAssertFalse(store.add("Sneaky"))
        store.delete(carried.id)
        XCTAssertEqual(try repository.load(yesterday)?.items.count, 3)
    }

    func testMovingLeftoversAddsThemToTodayOnceAndLeavesYesterdayAsItWas() throws {
        let (left, _) = try seedYesterday()
        let store = makeStore()
        store.show(.yesterday)

        store.moveToToday([left.id])
        XCTAssertEqual(store.day.items.last?.id, left.id)
        XCTAssertEqual(store.leftovers, [])
        XCTAssertEqual(try repository.load(today)?.items.last?.id, left.id)
        XCTAssertEqual(try repository.load(yesterday)?.items.map(\.title), ["Carried", "Done", "Left behind"])

        store.moveToToday()
        XCTAssertEqual(store.day.items.filter { $0.id == left.id }.count, 1)
    }

    func testTomorrowsTasksAreSavedAsPlannedAheadAndJoinTheLeftoversWhenTheDayComes() throws {
        let store = makeStore()
        store.add("Unfinished today")
        store.show(.tomorrow)
        XCTAssertTrue(store.canEdit)
        XCTAssertTrue(store.add("Planned"))
        XCTAssertEqual(store.items.map(\.title), ["Planned"])
        XCTAssertEqual(store.day.items.map(\.title), ["Unfinished today"])

        let saved = try XCTUnwrap(repository.load(tomorrow))
        XCTAssertTrue(saved.isPlannedAhead)
        XCTAssertEqual(try repository.open(tomorrow).items.map(\.title), ["Unfinished today", "Planned"])
    }

    func testLookingAtTomorrowCreatesNoFile() throws {
        let store = makeStore()
        store.show(.tomorrow)
        store.show(.today)
        XCTAssertNil(try repository.load(tomorrow))
    }

    func testKitStarterTasksGoToTodayWhicheverDayIsShown() {
        let store = makeStore()
        store.show(.tomorrow)
        store.addStarterTasks(["Starter"])
        XCTAssertEqual(store.day.items.map(\.title), ["Starter"])
        XCTAssertEqual(store.items, [])
    }

    func testPlanMyDayAndWrapUpReturnToToday() {
        let store = makeStore(runMode: .demo)
        store.show(.tomorrow)
        store.wrapUp()
        XCTAssertEqual(store.viewing, .today)
        XCTAssertTrue(store.review.isActive)

        store.show(.yesterday)
        XCTAssertFalse(store.review.isActive, "another day closes today's wrap-up")
    }

    func testPlanTomorrowPlansTomorrowsListAroundTomorrowsCalendar() async throws {
        let store = makeStore(runMode: .demo)
        store.show(.tomorrow)
        XCTAssertTrue(store.hasPlannableTomorrow)
        let tasks = store.items
        store.planTomorrow()
        XCTAssertEqual(store.viewing, .tomorrow, "planning ahead stays on tomorrow")
        XCTAssertEqual(store.plan.target, .tomorrow)
        XCTAssertEqual(store.plan.phase, .planning)

        store.showForSnapshot(.tomorrow, planning: true)
        guard case .proposal(let proposal) = store.plan.phase else { return XCTFail("\(store.plan.phase)") }
        XCTAssertFalse(proposal.pending.isEmpty)
        XCTAssertTrue(proposal.pending.allSatisfy { PlannerDayKey(date: $0.start) == tomorrow })
        let linked = Set(proposal.pending.compactMap(\.linkedTaskID))
        XCTAssertFalse(linked.isEmpty)
        XCTAssertTrue(linked.isSubset(of: Set(tasks.map(\.id))), "blocks work on tomorrow's tasks")
        let events = store.upNext.planEvents(on: .tomorrow)
        XCTAssertTrue(proposal.pending.allSatisfy { block in
            !events.contains { !$0.isAllDay && $0.start < block.end && block.start < $0.end }
        }, "no block overlaps tomorrow's events")

        store.show(.today)
        XCTAssertFalse(store.plan.isActive, "tomorrow's plan doesn't follow onto today")
        store.show(.yesterday)
        XCTAssertNil(store.viewing.planStart(now: Date()))
    }

    func testClosingThePanelKeepsAPlanForTomorrowAndOtherwiseReturnsToToday() {
        let store = makeStore(runMode: .demo)
        store.show(.tomorrow)
        store.panelClosed()
        XCTAssertEqual(store.viewing, .today)

        store.show(.tomorrow)
        store.planTomorrow()
        store.panelClosed()
        XCTAssertEqual(store.viewing, .tomorrow, "the plan waits on tomorrow for the next open")
        XCTAssertEqual(store.plan.target, .tomorrow)
        XCTAssertTrue(store.plan.isActive)

        store.plan.cancel()
        store.panelClosed()
        XCTAssertEqual(store.viewing, .today)
    }

    func testAnUnreadableTodayDoesNotPullTomorrowsEditsBackToToday() throws {
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: repository.fileURL(for: today))
        let store = makeStore()
        XCTAssertEqual(store.problem, .unreadable(fileName: "\(today.rawValue).json"))

        store.show(.tomorrow)
        XCTAssertTrue(store.add("Planned"))
        XCTAssertEqual(store.viewing, .tomorrow)
        XCTAssertEqual(try repository.load(tomorrow)?.items.map(\.title), ["Planned"])
        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: today)), Data("garbage".utf8))
    }

    func testAnUnreadableTomorrowIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: repository.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: repository.fileURL(for: tomorrow))
        let store = makeStore()
        store.show(.tomorrow)
        XCTAssertEqual(store.shownProblem, .unreadable(fileName: "\(tomorrow.rawValue).json"))
        XCTAssertNil(store.problem)
        XCTAssertFalse(store.add("Planned"))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: tomorrow)), Data("garbage".utf8))
    }

    func testDemoModeShowsSampleDaysAndKeepsEditsInMemory() {
        let store = makeStore(runMode: .demo)
        store.show(.yesterday)
        XCTAssertEqual(store.leftovers.count, 2)
        store.moveToToday()
        XCTAssertEqual(store.leftovers, [])

        store.show(.tomorrow)
        XCTAssertTrue(store.shownDay.isPlannedAhead)
        store.add("Demo plan")
        store.show(.today)
        store.show(.tomorrow)
        XCTAssertEqual(store.items.last?.title, "Demo plan")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testCalendarCardStepsWithTheChecklistAndKeepsTodayForThePreview() {
        let store = makeStore(runMode: .demo)
        let todayEvents = store.upNext.events
        XCTAssertEqual(store.upNext.viewing, .today)
        XCTAssertEqual(store.upNext.shownEvents, todayEvents)

        store.show(.tomorrow)
        XCTAssertEqual(store.upNext.viewing, .tomorrow)
        XCTAssertFalse(store.upNext.shownEvents.isEmpty)
        XCTAssertTrue(store.upNext.shownEvents.allSatisfy { PlannerDayKey(date: $0.start) == tomorrow })
        XCTAssertNil(store.upNext.emptySituation)
        // The closed-notch meeting preview still reads today's events.
        XCTAssertEqual(store.upNext.events, todayEvents)

        store.show(.yesterday)
        XCTAssertTrue(store.upNext.shownEvents.allSatisfy { PlannerDayKey(date: $0.start) == yesterday })

        store.show(.today)
        XCTAssertEqual(store.upNext.shownEvents, todayEvents)
    }

    func testCalendarWithoutAccessExplainsItselfOnEveryDay() {
        let store = UpNextStore(runMode: .live)
        guard store.access != .granted else { return }
        for day in PlannerViewedDay.allCases {
            store.show(day)
            XCTAssertNotNil(store.emptySituation, "\(day)")
            XCTAssertTrue(store.shownEvents.isEmpty, "\(day)")
        }
    }
}
