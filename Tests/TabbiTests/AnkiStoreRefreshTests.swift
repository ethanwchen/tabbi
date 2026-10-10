import XCTest
import Combine
import TabbiKitCore
@testable import TabbiKit
@testable import Tabbi

/// A scripted AnkiConnect: answers the summary's actions for one deck with
/// `due` cards and `reviewed` cards done today, or fails the way a closed,
/// busy or broken Anki does. One action can be held open until released,
/// and a held request ignores cancellation, like a reply already on the wire.
private final class ScriptedAnki: AnkiConnectTransport, @unchecked Sendable {
    enum Mode { case answer, refuse, timeout, garbage }

    private let lock = NSLock()
    private var _mode = Mode.answer
    private var _due = 40
    private var _reviewed = 12
    private var _syncError: String?
    private var _held: String?
    private var _released = false
    private var _heldAnswered = false
    private var _actions: [String] = []

    var mode: Mode {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }
    var due: Int {
        get { lock.withLock { _due } }
        set { lock.withLock { _due = newValue } }
    }
    var reviewed: Int {
        get { lock.withLock { _reviewed } }
        set { lock.withLock { _reviewed = newValue } }
    }
    var syncError: String? {
        get { lock.withLock { _syncError } }
        set { lock.withLock { _syncError = newValue } }
    }
    var actions: [String] { lock.withLock { _actions } }
    /// Whether the held request has been answered after its release.
    var heldAnswered: Bool { lock.withLock { _heldAnswered } }

    /// Holds the next request for `action` until `release()`.
    func hold(_ action: String) { lock.withLock { _held = action; _released = false; _heldAnswered = false } }
    func release() { lock.withLock { _released = true } }

    func count(_ action: String) -> Int { actions.filter { $0 == action }.count }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        let action = object["action"] as? String ?? ""
        let (mode, text, holds) = lock.withLock { () -> (Mode, String, Bool) in
            _actions.append(action)
            let holds = _held == action
            if holds { _held = nil }
            return (_mode, reply(to: action), holds)
        }
        if holds {
            while !lock.withLock({ _released }) {
                // Detached, so a cancelled caller still waits instead of spinning.
                await Task.detached { try? await Task.sleep(for: .milliseconds(5)) }.value
            }
            lock.withLock { _heldAnswered = true }
        }
        switch mode {
        case .refuse: throw AnkiConnectTransportError.connectionRefused
        case .timeout: throw AnkiConnectTransportError.timedOut
        case .garbage: return AnkiConnectHTTPResponse(statusCode: 200, body: Data("<html>busy</html>".utf8))
        case .answer: return AnkiConnectHTTPResponse(statusCode: 200, body: Data(text.utf8))
        }
    }

    /// Called under the lock, so the reply reflects the script when the
    /// request arrived.
    private func reply(to action: String) -> String {
        let today = AnkiDay(date: Date()).description
        switch action {
        case "deckNamesAndIds":
            return #"{"result":{"Pharm":1},"error":null}"#
        case "getDeckStats":
            return #"{"result":{"1":{"deck_id":1,"name":"Pharm","new_count":0,"learn_count":0,"review_count":\#(_due),"total_in_deck":900}},"error":null}"#
        case "getNumCardsReviewedToday":
            return #"{"result":\#(_reviewed),"error":null}"#
        case "getNumCardsReviewedByDay":
            return #"{"result":[["\#(today)",\#(_reviewed)]],"error":null}"#
        case "multi":
            return #"{"result":[{"result":[],"error":null}],"error":null}"#
        case "sync":
            if let message = _syncError { return #"{"result":null,"error":"\#(message)"}"# }
            return #"{"result":null,"error":null}"#
        default:
            return #"{"result":null,"error":"unsupported action"}"#
        }
    }
}

/// The Anki store against a scripted AnkiConnect: what the panel, Today and
/// the activity log see when Anki answers, is closed, busy or garbled, when
/// refreshes overlap, and when Sync fails or finishes after the module is off.
@MainActor
final class AnkiStoreRefreshTests: XCTestCase {
    private static let favoriteKey = "anki.favoriteDeck"
    private var savedFavorite: Any?
    private var anki: ScriptedAnki!
    private var log: ActivityLog!
    private var store: AnkiStore!
    private var provided: [ModuleProvision] = []
    private var subscription: AnyCancellable?

    override func setUp() async throws {
        savedFavorite = UserDefaults.standard.object(forKey: Self.favoriteKey)
        UserDefaults.standard.removeObject(forKey: Self.favoriteKey)
        anki = ScriptedAnki()
        log = ActivityLog(repository: nil)
        store = AnkiStore(activity: log, runMode: .live, client: AnkiConnectClient(transport: anki))
        subscription = store.provision(source: AnkiModule.descriptor.id).sink { [unowned self] in provided.append($0) }
    }

    override func tearDown() async throws {
        store.stop()
        anki.release()
        subscription = nil
        UserDefaults.standard.set(savedFavorite, forKey: Self.favoriteKey)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ what: String = "condition",
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func refreshAndWait() async throws {
        store.refresh()
        try await waitUntil("the refresh") { !store.isRefreshing }
    }

    private var reviewLog: [ActivityRecord] {
        let today = PlannerDayKey(date: Date())
        return log.records(from: today, through: today).filter { $0.kind == .cardsReviewed }
    }

    func testStartSharesTodaysCardsAndLogsEachAnsweredCardOnce() async throws {
        XCTAssertEqual(store.state, .checking)
        store.start()
        XCTAssertTrue(store.isRefreshing, "start fetches right away, so Today has numbers")
        try await waitUntil("ready") { store.state == .ready }

        XCTAssertEqual(store.summary?.dueTotal, 40)
        XCTAssertEqual(store.summary?.reviewedToday, 12)
        XCTAssertNotNil(store.updatedAt)
        XCTAssertNil(store.problem)
        XCTAssertEqual(provided.last?.progress.count, 1, "today's reviews are shared as a goal")
        XCTAssertEqual(reviewLog.map(\.quantity), [12])
        XCTAssertEqual(reviewLog.first?.source, AnkiModule.descriptor.id)

        try await refreshAndWait()
        XCTAssertEqual(reviewLog.map(\.quantity), [12], "the same cards are never logged twice")

        anki.reviewed = 15
        try await refreshAndWait()
        XCTAssertEqual(reviewLog.map(\.quantity), [12, 3], "only the newly answered cards are logged")
        XCTAssertEqual(store.summary?.reviewedToday, 15)
    }

    func testAnkiQuittingClearsTheNumbersAndStopsSharingThem() async throws {
        store.start()
        try await waitUntil("ready") { store.state == .ready }
        XCTAssertEqual(provided.last?.progress.count, 1)

        anki.mode = .refuse
        try await refreshAndWait()

        let expected = AnkiConnectionState.resolve(error: .ankiNotRunning, isInstalled: AnkiStore.isInstalled,
                                                   launchedAt: nil, now: Date())
        XCTAssertEqual(store.state, expected)
        XCTAssertNil(store.summary, "a closed Anki shows its setup screen, not old counts")
        XCTAssertEqual(provided.last, .empty, "Today and the ticker stop showing cards Anki no longer reports")

        anki.mode = .answer
        try await refreshAndWait()
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.summary?.dueTotal, 40)
    }

    func testABusyOrGarbledAnkiKeepsTheLastNumbersWithAWarning() async throws {
        store.start()
        try await waitUntil("ready") { store.state == .ready }
        let shown = store.updatedAt

        anki.mode = .timeout
        try await refreshAndWait()
        XCTAssertEqual(store.state, .problem(.timeout))
        XCTAssertEqual(store.problem, .timeout)
        XCTAssertEqual(store.summary?.dueTotal, 40, "a busy Anki keeps the last good counts")
        XCTAssertEqual(store.updatedAt, shown, "the counts say how old they are")
        XCTAssertEqual(provided.last?.progress.count, 1, "the goal stays shared while the summary is today's")

        anki.mode = .garbage
        try await refreshAndWait()
        guard case .problem(.invalidResponse) = store.state else {
            return XCTFail("a reply that is not JSON is an unexpected reply, got \(store.state)")
        }
        XCTAssertEqual(store.summary?.dueTotal, 40)

        anki.mode = .answer
        anki.due = 25
        try await refreshAndWait()
        XCTAssertEqual(store.state, .ready)
        XCTAssertNil(store.problem)
        XCTAssertEqual(store.summary?.dueTotal, 25)
    }

    func testTheNewestRefreshWinsOverAnOlderSlowerOne() async throws {
        anki.hold("getDeckStats")
        store.start()
        try await waitUntil("the first request to reach Anki") { anki.count("getDeckStats") == 1 }

        anki.due = 7
        store.refresh()
        try await waitUntil("the second refresh") { store.state == .ready }
        XCTAssertEqual(store.summary?.dueTotal, 7)

        // The older reply (40 due) arrives after the newer one.
        anki.release()
        try await waitUntil("the stale reply") { anki.heldAnswered }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(store.summary?.dueTotal, 7, "a stale reply never overwrites newer counts")
        XCTAssertFalse(store.isRefreshing)
    }

    func testStoppingDropsARefreshStillInFlight() async throws {
        anki.hold("getDeckStats")
        store.start()
        try await waitUntil("the request to reach Anki") { anki.count("getDeckStats") == 1 }

        store.stop()
        XCTAssertFalse(store.isRefreshing, "the module is off, so nothing spins")
        anki.release()
        try await waitUntil("the late reply") { anki.heldAnswered }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(store.state, .checking)
        XCTAssertNil(store.summary, "a reply that lands after stop changes nothing")
        XCTAssertTrue(reviewLog.isEmpty, "and logs nothing")
    }

    func testAFailedSyncWarnsOverTheCountsAndASuccessfulOneClearsIt() async throws {
        store.start()
        try await waitUntil("ready") { store.state == .ready }
        let fetches = anki.count("deckNamesAndIds")

        anki.syncError = "auth not configured"
        store.sync()
        XCTAssertTrue(store.isSyncing)
        store.sync()
        try await waitUntil("the sync") { !store.isSyncing }
        XCTAssertEqual(anki.count("sync"), 1, "a second click while syncing does nothing")
        XCTAssertEqual(store.state, .ready, "a failed sync is not a connection problem")
        XCTAssertEqual(store.actionError, .syncNotConfigured)
        XCTAssertEqual(store.problem, .syncNotConfigured, "the panel says why the counts may be stale")
        try await waitUntil("the refresh after the sync") { anki.count("deckNamesAndIds") == fetches + 1 && !store.isRefreshing }

        anki.syncError = nil
        anki.due = 3
        store.sync()
        try await waitUntil("the second sync") { !store.isSyncing }
        XCTAssertNil(store.actionError)
        try await waitUntil("the counts after the sync") { store.summary?.dueTotal == 3 }
        XCTAssertNil(store.problem)
    }

    func testASyncFinishingAfterStopLeavesNoWarningAndFetchesNothing() async throws {
        store.start()
        try await waitUntil("ready") { store.state == .ready }
        let fetches = anki.count("deckNamesAndIds")

        anki.syncError = "AnkiWeb is down"
        anki.hold("sync")
        store.sync()
        try await waitUntil("the sync to reach Anki") { anki.count("sync") == 1 }
        store.stop()
        anki.release()
        try await waitUntil("the sync") { !store.isSyncing }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(store.actionError, "a module that is off shows no warning")
        XCTAssertEqual(anki.count("deckNamesAndIds"), fetches, "and does not refresh")
    }
}
