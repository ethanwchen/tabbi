import XCTest
import TabbiKitCore

/// Answers each request with whatever `reply` returns for its JSON body, so
/// a test can fail one call and not the next, and records every body.
private final class ScriptedAnkiTransport: AnkiConnectTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [[String: Any]] = []
    private let reply: @Sendable ([String: Any]) -> String

    init(_ reply: @escaping @Sendable ([String: Any]) -> String) { self.reply = reply }

    var requests: [[String: Any]] { lock.withLock { sent } }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        lock.withLock { sent.append(object) }
        return AnkiConnectHTTPResponse(statusCode: 200, body: Data(reply(object).utf8))
    }
}

private func decks(in request: [String: Any]) -> [String] {
    (request["params"] as? [String: Any])?["decks"] as? [String] ?? []
}

private func action(of request: [String: Any]) -> String { request["action"] as? String ?? "" }

/// One deck's `getDeckStats` entry as AnkiConnect writes it.
private func statsJSON(_ id: Int64, _ name: String, due: Int) -> String {
    #""\#(id)":{"deck_id":\#(id),"name":"\#(name)","new_count":\#(due),"learn_count":0,"review_count":0,"total_in_deck":10}"#
}

final class AnkiRobustnessTests: XCTestCase {
    // MARK: Classification, from AnkiConnect's real strings

    /// Replies recorded from the real AnkiConnect handler (the add-on's own
    /// code over Anki 26.09's library) in each state; see the PR.
    func testCollectionClosedStringsFromEveryAnkiConnectVersion() {
        let closed = [
            "collection is not available",       // 2023 to 2025 add-on: no profile open (mw.col is None)
            "database is not available",         // full sync in progress (close_for_full_sync)
            "CollectionNotOpen",                 // Anki's backend, collection closed under AnkiConnect
            "Collection is not available.",      // 2026.10 rewrite: no profile open
            "A collection operation is active.", // 2026.10 rewrite: sync or Check Database running
            "Collection session changed.",       // 2026.10 rewrite: profile reopened mid-request
        ]
        for message in closed {
            XCTAssertEqual(AnkiConnectError.fromAnkiMessage(message, action: "deckNamesAndIds"), .collectionUnavailable, message)
        }
    }

    func testUnrelatedErrorsMentioningACollectionAreNotTheProfilePicker() {
        let unrelated = [
            "'NoneType' object has no attribute 'all'; collection is none of these",
            "collection is not open to new decks",
            "Deck counts unavailable.",
            "model was not found: Basic",
        ]
        for message in unrelated {
            XCTAssertEqual(AnkiConnectError.fromAnkiMessage(message, action: "x"), .anki(message), message)
        }
        XCTAssertEqual(AnkiConnectError.fromAnkiMessage("valid api key must be provided", action: "x"), .apiKeyRequired)
        XCTAssertEqual(AnkiConnectError.fromAnkiMessage("unsupported action", action: "cardReviews"), .unsupportedAction("cardReviews"))
        XCTAssertEqual(AnkiConnectError.fromAnkiMessage("sync: auth not configured", action: "sync"), .syncNotConfigured)
    }

    func testMessagesAreShortenedToOneLine() {
        XCTAssertEqual(AnkiConnectError.shortMessage("  database \n is\tlocked  "), "database is locked")
        let long = String(repeating: "word ", count: 60)
        let short = AnkiConnectError.shortMessage(long)
        XCTAssertLessThanOrEqual(short.count, AnkiConnectError.messageLimit)
        XCTAssertTrue(short.hasSuffix("\u{2026}"))
        XCTAssertEqual(AnkiConnectError.anki("x").message, "x")
        XCTAssertNil(AnkiConnectError.timeout.message)
    }

    // MARK: What the user reads

    func testUnexplainedErrorsQuoteAnkiAndRemindAboutTheAddOn() {
        let error = AnkiConnectError.anki("Deck counts unavailable.")
        XCTAssertTrue(error.isUnexplained)
        XCTAssertEqual(error.quotedMessage, "Anki said: \u{201C}Deck counts unavailable.\u{201D}")
        XCTAssertTrue(error.suggestion.contains("Deck counts unavailable."), error.suggestion)
        XCTAssertTrue(error.suggestion.contains(AnkiConnectClient.addOnCode), error.suggestion)
        XCTAssertTrue(AnkiConnectError.addOnReminder.contains("AnkiConnect"))
        XCTAssertFalse(error.suggestion.contains("Try again in a moment"))
        for known in [AnkiConnectError.permissionDenied, .apiKeyRequired, .addOnOutdated(version: 5), .ankiNotRunning, .timeout] {
            XCTAssertFalse(known.isUnexplained)
            XCTAssertNil(known.quotedMessage)
            XCTAssertFalse(known.suggestion.contains("Make sure the AnkiConnect"), "\(known)")
        }
        XCTAssertEqual(AnkiConnectError.invalidResponse("getNumCardsReviewedByDay: Bad day").quotedMessage,
                       "Details: getNumCardsReviewedByDay: Bad day")
    }

    func testClosedCollectionSaysAnkiMayBeBusyAndOpensAnki() {
        let error = AnkiConnectError.collectionUnavailable
        XCTAssertEqual(error.title, "Waiting for Anki")
        XCTAssertTrue(error.suggestion.contains("syncing"))
        XCTAssertTrue(error.suggestion.contains("reconnects"))
        let status = AnkiConnectionState.problem(.collectionUnavailable).connectionStatus
        XCTAssertEqual(status.action, .openApp(.anki))
        XCTAssertTrue(status.detail.contains("syncing"))
        XCTAssertTrue(status.detail.contains("profile list"))
    }

    func testConnectionsRowAndCopiedDetailsCarryAnkisMessage() {
        let state = AnkiConnectionState.problem(.anki("Deck counts unavailable."))
        let status = state.connectionStatus
        let diagnosis = state.diagnosis
        XCTAssertEqual(status.headline, "Anki reported a problem")
        XCTAssertTrue(diagnosis.verdict.contains(AnkiConnectError.addOnReminderWithCode))
        XCTAssertTrue(status.detail.contains(AnkiConnectClient.addOnCode))
        XCTAssertEqual(status.action, .checkAgain)
        XCTAssertTrue(diagnosis.clearsBySelf)
        XCTAssertEqual(diagnosis.firstFailure?.answer, "No. Anki said \u{201C}Deck counts unavailable.\u{201D}.")
        let details = diagnosis.details(appVersion: "1.0.1", systemVersion: "26.0", checkedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(details.contains("Deck counts unavailable."), details)
        XCTAssertTrue(details.contains("State: anki.problem.anki"), details)
        XCTAssertFalse(AnkiConnectionState.ready.diagnosis.clearsBySelf)
        XCTAssertFalse(AnkiConnectionState.addOnMissing.diagnosis.clearsBySelf)
    }

    // MARK: Deck counts across AnkiConnect versions

    /// AnkiConnect 2026.10 fails the whole `getDeckStats` batch when the
    /// empty Default deck is in it; the client asks again without Default.
    func testDeckStatsRetriesWithoutTheHiddenDefaultDeck() async throws {
        let transport = ScriptedAnkiTransport { request in
            decks(in: request).contains("Default")
                ? #"{"result":null,"error":"Deck counts unavailable."}"#
                : "{\"result\":{\(statsJSON(5, "Biology", due: 3))},\"error\":null}"
        }
        let client = AnkiConnectClient(transport: transport)
        let stats = try await client.deckStats(for: [AnkiDeck(id: 1, name: "Default"), AnkiDeck(id: 5, name: "Biology")])
        XCTAssertEqual(stats.map(\.name), ["Biology"])
        XCTAssertEqual(stats.first?.newCount, 3)
        XCTAssertEqual(transport.requests.map(decks), [["Default", "Biology"], ["Biology"]])
    }

    /// Any other deck that fails is skipped by asking deck by deck in one `multi`.
    func testDeckStatsFallsBackToOneDeckAtATime() async throws {
        let transport = ScriptedAnkiTransport { request in
            if action(of: request) == "multi" {
                return "{\"result\":[{\"result\":{\(statsJSON(5, "Biology", due: 3))},\"error\":null},"
                    + #"{"result":null,"error":"Deck counts unavailable."}"#
                    + ",{\"result\":{\(statsJSON(7, "Chemistry", due: 2))},\"error\":null}],\"error\":null}"
            }
            return #"{"result":null,"error":"Deck counts unavailable."}"#
        }
        let client = AnkiConnectClient(transport: transport, apiKey: "secret")
        let stats = try await client.deckStats(for: [AnkiDeck(id: 5, name: "Biology"), AnkiDeck(id: 6, name: "Broken"),
                                                     AnkiDeck(id: 7, name: "Chemistry")])
        XCTAssertEqual(stats.map(\.name), ["Biology", "Chemistry"])
        let multi = try XCTUnwrap(transport.requests.last)
        let inner = try XCTUnwrap((multi["params"] as? [String: Any])?["actions"] as? [[String: Any]])
        XCTAssertEqual(inner.map(decks), [["Biology"], ["Broken"], ["Chemistry"]])
        // AnkiConnect checks the key of each inner action.
        XCTAssertEqual(inner.compactMap { $0["key"] as? String }, ["secret", "secret", "secret"])
    }

    func testDeckStatsStillFailsWhenAnkiIsClosed() async {
        let transport = ScriptedAnkiTransport { _ in #"{"result":null,"error":"Collection is not available."}"# }
        let client = AnkiConnectClient(transport: transport)
        do {
            _ = try await client.deckStats(for: [AnkiDeck(id: 5, name: "Biology")])
            XCTFail("Expected an error")
        } catch let error as AnkiConnectError {
            XCTAssertEqual(error, .collectionUnavailable)
            XCTAssertEqual(transport.requests.count, 1, "a closed collection is not retried deck by deck")
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    // MARK: A damaged request body

    func testABodyAnkiCouldNotParseIsSentOnceMore() async throws {
        let counter = Counter()
        let transport = ScriptedAnkiTransport { _ in
            counter.next() == 0
                ? #"{"result":null,"error":"Expecting value: line 1 column 1 (char 0)"}"#
                : #"{"result":6,"error":null}"#
        }
        let client = AnkiConnectClient(transport: transport)
        let version = try await client.version()
        XCTAssertEqual(version, 6)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(AnkiConnectError.anki("Expecting property name enclosed in double quotes: line 1 column 2 (char 1)").isMalformedRequest)
        XCTAssertFalse(AnkiConnectError.anki("Deck counts unavailable.").isMalformedRequest)
    }

    // MARK: A summary with a piece missing

    private func summaryTransport(byDay: String, reviews: String = #"{"result":[{"result":[],"error":null}],"error":null}"#) -> ScriptedAnkiTransport {
        ScriptedAnkiTransport { request in
            switch action(of: request) {
            case "deckNamesAndIds": return #"{"result":{"Biology":5},"error":null}"#
            case "getDeckStats": return "{\"result\":{\(statsJSON(5, "Biology", due: 12))},\"error\":null}"
            case "getNumCardsReviewedToday": return #"{"result":7,"error":null}"#
            case "getNumCardsReviewedByDay": return byDay
            case "multi": return reviews
            default: return #"{"result":null,"error":"unsupported action"}"#
            }
        }
    }

    func testAFailingHistoryStillShowsTheDueCounts() async throws {
        let errors = ErrorLog()
        let transport = summaryTransport(byDay: #"{"result":null,"error":"no such column: day"}"#)
        let client = AnkiConnectClient(transport: transport, onError: { action, error in errors.add(action, error) })
        let summary = try await client.summary(now: Date(timeIntervalSince1970: 1_790_000_000), calendar: Self.utc)
        XCTAssertEqual(summary.dueTotal, 12)
        XCTAssertEqual(summary.reviewedToday, 7)
        XCTAssertEqual(summary.missing, [.history])
        XCTAssertEqual(summary.gaps, [AnkiSummary.Gap(action: "getNumCardsReviewedByDay", message: "no such column: day")])
        // The failing action is named for the log.
        XCTAssertEqual(errors.actions, ["getNumCardsReviewedByDay"])
    }

    func testAnUnreadableReviewLogOnlyLosesRetention() async throws {
        let transport = summaryTransport(byDay: #"{"result":[["2026-09-21",7]],"error":null}"#,
                                         reviews: #"{"result":[{"result":[["x"]],"error":null}],"error":null}"#)
        let summary = try await AnkiConnectClient(transport: transport).summary(now: Date(timeIntervalSince1970: 1_790_000_000), calendar: Self.utc)
        XCTAssertEqual(summary.missing, [.reviewLog])
        XCTAssertEqual(summary.dueTotal, 12)
        XCTAssertNil(summary.retention)
    }

    func testAClosedCollectionMidRefreshStillFailsTheRefresh() async {
        let transport = summaryTransport(byDay: #"{"result":null,"error":"database is not available"}"#)
        do {
            _ = try await AnkiConnectClient(transport: transport).summary()
            XCTFail("Expected an error")
        } catch let error as AnkiConnectError {
            XCTAssertEqual(error, .collectionUnavailable)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testMissingPiecesAreFilledFromTheLastSummaryOfTheSameDay() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = AnkiDay(date: now, calendar: Self.utc)
        let stats = [AnkiDeckStats(deckID: 5, name: "Biology", newCount: 12, learnCount: 0, reviewCount: 0, totalInDeck: 10)]
        let history = (0..<5).map { AnkiDayCount(day: today.adding(days: -$0), count: 10) }
        let previous = AnkiSummary(deckStats: stats, reviewedToday: 10, reviewsByDay: history, reviews: [], now: now, today: today, calendar: Self.utc)
        XCTAssertEqual(previous.streak, 5)
        let partial = AnkiSummary(deckStats: stats, reviewedToday: 14, reviewsByDay: [], reviews: [], now: now, today: today,
                                  calendar: Self.utc, missing: [.history], gaps: [AnkiSummary.Gap(action: "getNumCardsReviewedByDay", message: "x")])
        XCTAssertEqual(partial.streak, 1, "a partial summary alone would show a made-up streak")
        let filled = partial.filling(from: previous)
        XCTAssertEqual(filled.streak, 5)
        XCTAssertEqual(filled.reviewedToday, 14)
        XCTAssertEqual(filled.history.last?.count, 14)
        XCTAssertTrue(filled.missing.isEmpty)
        // Nothing to fill from: the piece stays missing.
        XCTAssertEqual(partial.filling(from: nil).missing, [.history])
        XCTAssertEqual(partial.filling(from: partial).missing, [.history])
        // A complete summary is left alone.
        XCTAssertEqual(previous.filling(from: partial), previous)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}

private final class ErrorLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, AnkiConnectError)] = []
    func add(_ action: String, _ error: AnkiConnectError) { lock.withLock { entries.append((action, error)) } }
    var actions: [String] { lock.withLock { entries.map(\.0) } }
}
