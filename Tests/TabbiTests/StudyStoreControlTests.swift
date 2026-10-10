import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Study timer's controls through the store: skipping a phase, the deep
/// focus switch and the shared focus clock it publishes, new Custom lengths
/// mid-session, and the Anki card feed that ends a sprint. Phases that need
/// real minutes start from a session saved in the past, as the app saves it.
@MainActor
final class StudyStoreControlTests: XCTestCase {
    private var defaults: UserDefaults!
    private var folder: URL!
    private let workspace = NotificationCenter()
    private let app = NotificationCenter()
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() async throws {
        defaults = InMemoryDefaults()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyStoreControlTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try? FileManager.default.removeItem(at: folder)
    }

    /// A running focus block on `method` that started `minutesAgo`.
    private func saveRunning(_ method: StudyMethod, minutesAgo: Double) throws {
        var session = StudySession(method: method)
        session.start(at: Date().addingTimeInterval(-minutesAgo * 60))
        defaults.set(try JSONEncoder().encode(session), forKey: "study.session")
    }

    /// A live store on private defaults, a temporary folder and its own
    /// sleep and quit centers. With no heartbeat saved, a running session
    /// is picked up as it was.
    private func launch(activity: ActivityLog? = nil) -> StudyStore {
        StudyStore(storage: EditionStorage(root: folder), activity: activity, runMode: .live,
                   defaults: defaults, interruptions: (workspace, app))
    }

    /// A snapshot-mode store: it saves nothing and never chimes.
    private func snapshotStore() -> StudyStore {
        StudyStore(storage: EditionStorage(root: folder), runMode: RunMode(isDemo: false, isSnapshot: true),
                   defaults: defaults)
    }

    private func savedSession() throws -> StudySession {
        let data = try XCTUnwrap(defaults.data(forKey: "study.session"))
        return try JSONDecoder().decode(StudySession.self, from: data)
    }

    /// Records for yesterday and today, so a run just after midnight cannot flake.
    private func logged(_ log: ActivityLog) -> [ActivityRecord] {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        return log.records(on: PlannerDayKey(date: yesterday)) + log.records(on: PlannerDayKey(date: now))
    }

    // MARK: Skip

    func testSkippingARunningBlockLogsItAsSkippedAndRunsTheBreak() throws {
        try saveRunning(.pomodoro, minutesAgo: 10)
        let log = ActivityLog(repository: nil)
        let store = launch(activity: log)
        XCTAssertEqual(store.session.phase, .focus)
        XCTAssertTrue(store.session.isRunning)

        store.skip()

        XCTAssertEqual(store.session.phase, .shortBreak)
        XCTAssertTrue(store.session.isRunning, "skipping while in flow keeps the clock running")
        XCTAssertEqual(store.session.completedFocusCount, 0, "a skipped block is not a finished one")
        let records = logged(log)
        XCTAssertEqual(records.map(\.kind), [.focusCompleted])
        XCTAssertEqual(records.first?.metadata[ActivityMetadata.outcome], StudyPhaseOutcome.skipped.rawValue)
        XCTAssertEqual(try XCTUnwrap(records.first?.quantity), 10, accuracy: 0.1)
        XCTAssertEqual(store.today.minutes, 10, "the minutes still count as study time")
        let saved = try savedSession()
        XCTAssertEqual(saved.phase, .shortBreak, "the skip is saved for the next launch")
        XCTAssertTrue(saved.log.isEmpty, "and the logged block is not saved again with it")

        // Skipping the break straight away drops into the next block, and a
        // break under a minute is not worth logging.
        store.skip()
        XCTAssertEqual(store.session.phase, .focus)
        XCTAssertTrue(store.session.isRunning)
        XCTAssertEqual(logged(log).count, 1)
    }

    func testSkippingWhilePausedLeavesTheNextPhaseWaiting() throws {
        try saveRunning(.pomodoro, minutesAgo: 10)
        let store = launch()
        store.pause()

        store.skip()

        XCTAssertEqual(store.session.phase, .shortBreak)
        XCTAssertEqual(store.session.runState, .idle, "a paused session never starts a phase on its own")
    }

    func testSkippingThePlainTimerStopsIt() throws {
        try saveRunning(.preset(.timer, custom: .standard, timer: .standard), minutesAgo: 2)
        let store = launch()
        XCTAssertEqual(store.session.method.kind, .timer)

        store.skip()

        XCTAssertEqual(store.session.method.kind, .timer)
        XCTAssertEqual(store.session.phase, .focus)
        XCTAssertEqual(store.session.runState, .idle, "a timer has no break to move on to")
    }

    // MARK: Deep focus and the shared clock

    func testDeepFocusIsSavedAndReadBackAtLaunch() {
        let store = launch()
        XCTAssertFalse(store.deepFocus, "deep focus is opt-in")

        store.setDeepFocus(true)
        XCTAssertTrue(launch().deepFocus)

        store.setDeepFocus(false)
        XCTAssertFalse(launch().deepFocus)
    }

    func testTheSharedClockFollowsTheSessionAndTheDeepFocusSwitch() throws {
        let store = snapshotStore()
        store.choose(.pomodoro)
        var shared: [ProvidedFocus?] = []
        store.sharedFocus(by: .study).sink { shared.append($0) }.store(in: &cancellables)
        XCTAssertEqual(shared.count, 1)
        XCTAssertNil(shared.last ?? nil, "an idle timer hides no other module's clock")

        store.primaryAction()
        let running = try XCTUnwrap(shared.last ?? nil)
        XCTAssertEqual(running.source, .study)
        XCTAssertEqual(running.phase, .focus)
        XCTAssertFalse(running.isDeep)
        guard case .countdown(let endsAt) = running.clock else { return XCTFail("expected a countdown, got \(running.clock)") }
        XCTAssertEqual(endsAt, try XCTUnwrap(store.session.endsAt))

        store.setDeepFocus(true)
        XCTAssertEqual((shared.last ?? nil)?.isDeep, true)
        let count = shared.count
        store.setDeepFocus(true)
        XCTAssertEqual(shared.count, count, "the same switch again republishes nothing")

        store.pause()
        guard case .paused = (shared.last ?? nil)?.clock else { return XCTFail("expected a paused clock") }

        store.stop()
        XCTAssertNil(shared.last ?? nil)
        XCTAssertNil(defaults.object(forKey: "study.deepFocus"), "a snapshot run saves no settings")
    }

    // MARK: Custom lengths

    func testNewCustomLengthsRetuneTheRunningBlockAndAreSaved() throws {
        try saveRunning(StudyCustomRhythm.standard.method, minutesAgo: 10)
        let log = ActivityLog(repository: nil)
        let store = launch(activity: log)
        XCTAssertEqual(store.session.method.kind, .custom)
        let started = try XCTUnwrap(store.session.endsAt).addingTimeInterval(-TimeInterval(StudyCustomRhythm.standard.focusMinutes * 60))

        let longer = StudyCustomRhythm(focusMinutes: 40, breakMinutes: 8)
        store.setCustom(longer)

        XCTAssertEqual(store.custom, longer)
        XCTAssertTrue(store.session.isRunning, "the block carries on")
        XCTAssertEqual(store.session.phase, .focus)
        XCTAssertEqual(try XCTUnwrap(store.session.endsAt).timeIntervalSince(started), 40 * 60, accuracy: 1)
        XCTAssertTrue(logged(log).isEmpty, "retuning is not a new block")

        // Trimming below the time already worked still leaves a minute.
        let shorter = StudyCustomRhythm(focusMinutes: 5, breakMinutes: 5)
        store.setCustom(shorter)
        XCTAssertEqual(try XCTUnwrap(store.session.endsAt).timeIntervalSinceNow, StudyMethod.minimumPhase, accuracy: 2)
        XCTAssertTrue(store.session.isRunning)

        XCTAssertEqual(launch().custom, shorter, "the lengths are saved")
    }

    func testCustomLengthsOnAnotherMethodLeaveItsSessionAlone() throws {
        try saveRunning(.pomodoro, minutesAgo: 3)
        let store = launch()
        let before = store.session

        store.setCustom(StudyCustomRhythm(focusMinutes: 40, breakMinutes: 8))

        XCTAssertEqual(store.session, before)
        XCTAssertEqual(store.custom.focusMinutes, 40)
        XCTAssertTrue(store.methods.contains { $0.kind == .custom && $0.duration(of: .focus) == 40 * 60 },
                      "the picker offers the new lengths")
    }

    // MARK: Anki card feed

    /// The provider snapshot with Anki's reviewed-today goal, or none when
    /// Anki is off. Study's own card-unit goal must never feed its sprint.
    private func cards(_ reviewed: Int?, ownCards: Int = 0) -> ProviderSnapshot {
        var provisions: [(module: ModuleID, provision: ModuleProvision)] = [
            (.study, ModuleProvision(progress: [ProgressItem(id: "own", source: .study, title: "Own", completed: ownCards,
                                                             target: 500, unit: ProviderSnapshot.cardUnit)])),
        ]
        if let reviewed {
            provisions.append((.anki, ModuleProvision(progress: [
                ProgressItem(id: "reviews", source: .anki, title: "Reviews", completed: reviewed, target: 300,
                             unit: ProviderSnapshot.cardUnit),
            ])))
        }
        return ProviderSnapshot(provisions)
    }

    func testAnkiReviewsCountTowardTheSprintAndReachingTheGoalEndsIt() throws {
        let store = snapshotStore()
        let feed = CurrentValueSubject<ProviderSnapshot, Never>(cards(nil))
        store.followCards(from: feed)
        store.choose(.ankiSprint)
        XCTAssertNil(store.cardsReviewedToday)
        XCTAssertFalse(store.canCountCards, "no module shares a card goal yet")

        feed.send(cards(50, ownCards: 400))
        XCTAssertEqual(store.cardsReviewedToday, 50, "only other modules' cards count")
        XCTAssertTrue(store.canCountCards)

        store.primaryAction()
        XCTAssertTrue(store.session.isRunning)
        XCTAssertEqual(store.session.cardsDone, 0, "cards reviewed before the start are only the baseline")

        feed.send(cards(80))
        XCTAssertEqual(store.session.cardsDone, 30)
        XCTAssertEqual(store.session.phase, .focus)

        // Pausing ignores cards answered meanwhile, and resuming rebases.
        store.pause()
        feed.send(cards(120))
        store.primaryAction()
        XCTAssertEqual(store.session.cardsDone, 30)

        let goal = try XCTUnwrap(store.session.method.cardGoal)
        feed.send(cards(120 + goal - 30))
        XCTAssertEqual(store.session.completedFocusCount, 1, "reaching the goal ends the sprint")
        XCTAssertEqual(store.session.phase, .shortBreak)
        XCTAssertTrue(store.session.isRunning)

        feed.send(cards(nil))
        XCTAssertNil(store.cardsReviewedToday, "Anki going away stops the count")
        XCTAssertFalse(store.canCountCards)
        XCTAssertEqual(store.session.completedFocusCount, 1)
    }

    func testTheDemoKeepsItsSampleSprintAndIgnoresTheFeed() {
        let store = StudyStore(storage: EditionStorage(root: folder), runMode: RunMode(isDemo: true, isSnapshot: false),
                               defaults: defaults)
        let feed = CurrentValueSubject<ProviderSnapshot, Never>(cards(10))
        store.followCards(from: feed)
        XCTAssertNil(store.cardsReviewedToday)
        XCTAssertTrue(store.canCountCards, "the demo's sample sprint always counts cards")

        store.setDeepFocus(false)
        store.setCustom(StudyCustomRhythm(focusMinutes: 40, breakMinutes: 8))
        XCTAssertNil(defaults.object(forKey: "study.deepFocus"), "the demo saves nothing")
        XCTAssertNil(defaults.object(forKey: "study.custom"))
    }
}
