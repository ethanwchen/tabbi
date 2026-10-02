import XCTest
import NotchKitCore

final class AnkiConnectionStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_866_800)

    private func resolve(_ error: AnkiConnectError?, installed: Bool = true, launchedSecondsAgo: TimeInterval? = nil) -> AnkiConnectionState {
        AnkiConnectionState.resolve(
            error: error, isInstalled: installed,
            launchedAt: launchedSecondsAgo.map { now.addingTimeInterval(-$0) }, now: now
        )
    }

    func testSuccessIsReady() {
        XCTAssertEqual(resolve(nil), .ready)
        XCTAssertEqual(resolve(nil, installed: false), .ready)
    }

    func testRefusedWithoutProcessDependsOnInstall() {
        XCTAssertEqual(resolve(.ankiNotRunning), .notRunning)
        XCTAssertEqual(resolve(.ankiNotRunning, installed: false), .notInstalled)
    }

    func testRefusedRightAfterLaunchIsStartingThenAddOnMissing() {
        XCTAssertEqual(resolve(.addOnMissing, launchedSecondsAgo: 3), .starting)
        XCTAssertEqual(resolve(.addOnMissing, launchedSecondsAgo: AnkiConnectionState.startupGrace + 1), .addOnMissing)
        XCTAssertEqual(resolve(.addOnMissing), .addOnMissing)
    }

    func testPermissionAndVersionErrorsAreSetupSteps() {
        XCTAssertEqual(resolve(.permissionDenied), .needsPermission(.permissionDenied))
        XCTAssertEqual(resolve(.apiKeyRequired), .needsPermission(.apiKeyRequired))
        XCTAssertEqual(resolve(.addOnOutdated(version: 5)), .addOnOutdated)
        XCTAssertEqual(resolve(.unsupportedAction("multi")), .addOnOutdated)
        for state in [resolve(.permissionDenied), resolve(.addOnOutdated(version: 5)), resolve(.ankiNotRunning)] {
            XCTAssertTrue(state.isSetupStep)
            XCTAssertFalse(state.keepsLastSummary)
        }
    }

    func testTransientErrorsKeepTheLastSummary() {
        for error in [AnkiConnectError.timeout, .collectionUnavailable, .transport("x"), .invalidResponse("x")] {
            let state = resolve(error)
            XCTAssertEqual(state, .problem(error))
            XCTAssertFalse(state.isSetupStep)
            XCTAssertTrue(state.keepsLastSummary)
        }
    }

    func testSetupStepsPollFasterThanReady() {
        XCTAssertLessThan(AnkiConnectionState.starting.refreshInterval, AnkiConnectionState.notRunning.refreshInterval)
        XCTAssertLessThan(AnkiConnectionState.addOnMissing.refreshInterval, AnkiConnectionState.ready.refreshInterval)
        XCTAssertGreaterThanOrEqual(AnkiConnectionState.ready.refreshInterval, 120)
    }

    func testOnlyStartingPollsWhileHidden() {
        XCTAssertTrue(AnkiConnectionState.starting.pollsWhileHidden)
        let others: [AnkiConnectionState] = [
            .checking, .notInstalled, .notRunning, .addOnMissing, .needsPermission(.permissionDenied),
            .addOnOutdated, .ready, .problem(.timeout),
        ]
        for state in others {
            XCTAssertFalse(state.pollsWhileHidden, "\(state)")
        }
        // Starting ends with the grace period, so hidden polling is bounded.
        let launched = Date(timeIntervalSince1970: 1_000)
        let afterGrace = launched.addingTimeInterval(AnkiConnectionState.startupGrace + 1)
        let state = AnkiConnectionState.resolve(error: .addOnMissing, isInstalled: true, launchedAt: launched, now: afterGrace)
        XCTAssertFalse(state.pollsWhileHidden)
    }

    // MARK: Summary helpers

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func summary(_ stats: [AnkiDeckStats], reviewed: Int = 0) -> AnkiSummary {
        let today = AnkiDay(date: now, rolloverHour: 4, calendar: utc)
        return AnkiSummary(deckStats: stats, reviewedToday: reviewed, reviewsByDay: [], reviews: [],
                           now: now, today: today, rolloverHour: 4, calendar: utc)
    }

    private func deck(_ id: Int64, _ name: String, due: Int) -> AnkiDeckStats {
        AnkiDeckStats(deckID: id, name: name, newCount: 0, learnCount: 0, reviewCount: due, totalInDeck: 100)
    }

    func testTopDecksListsRootsWithDueCardsByMostDue() {
        let value = summary([
            deck(1, "AnKing", due: 40),
            deck(2, "AnKing::Cardio", due: 30),
            deck(3, "Pharm", due: 90),
            deck(4, "Micro", due: 40),
            deck(5, "Default", due: 0),
        ])
        XCTAssertEqual(value.topDecks.map(\.name), ["Pharm", "AnKing", "Micro"])
    }

    func testCompletionFraction() {
        XCTAssertEqual(summary([deck(1, "A", due: 30)], reviewed: 90).completionFraction, 0.75, accuracy: 0.0001)
        XCTAssertEqual(summary([], reviewed: 0).completionFraction, 1)
    }

    func testIsCurrentFollowsRollover() {
        let value = summary([])
        XCTAssertTrue(value.isCurrent(now: now, calendar: utc))
        // 2026-10-02 03:00 UTC is still Oct 1 in Anki (rollover at 4).
        let beforeRollover = Date(timeIntervalSince1970: 1_790_910_000)
        XCTAssertTrue(value.isCurrent(now: beforeRollover, calendar: utc))
        XCTAssertFalse(value.isCurrent(now: beforeRollover.addingTimeInterval(2 * 3600), calendar: utc))
    }

    func testNextRolloverIsTheStartOfTheNextAnkiDay() {
        // 2026-10-02 03:00 UTC is still Oct 1 in Anki, so the next day starts at 04:00 the same morning.
        let beforeRollover = Date(timeIntervalSince1970: 1_790_910_000)
        let sameMorning = AnkiSummary.nextRollover(after: beforeRollover, calendar: utc)
        XCTAssertEqual(sameMorning.timeIntervalSince(beforeRollover), 3600)
        // From 04:00 on, the next one is a full day later.
        XCTAssertEqual(AnkiSummary.nextRollover(after: sameMorning, calendar: utc).timeIntervalSince(sameMorning), 86_400)
        let summary = summary([])
        XCTAssertFalse(summary.isCurrent(now: AnkiSummary.nextRollover(after: now, calendar: utc), calendar: utc))
        XCTAssertTrue(summary.isCurrent(now: AnkiSummary.nextRollover(after: now, calendar: utc).addingTimeInterval(-1), calendar: utc))
    }
}
