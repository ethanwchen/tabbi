import XCTest
import NotchDeckCore

/// Replays canned AnkiConnect replies and records what was sent.
private final class FakeAnkiTransport: AnkiConnectTransport, @unchecked Sendable {
    enum Reply {
        case json(String, status: Int = 200)
        case failure(AnkiConnectTransportError)
    }

    private let lock = NSLock()
    private var replies: [String: Reply]
    private var sent: [(body: [String: Any], timeout: TimeInterval)] = []

    init(_ replies: [String: Reply]) { self.replies = replies }

    var requests: [[String: Any]] { lock.withLock { sent.map(\.body) } }
    var timeouts: [TimeInterval] { lock.withLock { sent.map(\.timeout) } }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        let action = object["action"] as? String ?? ""
        let reply: Reply? = lock.withLock {
            sent.append((object, timeout))
            return replies[action]
        }
        switch reply {
        case .json(let text, let status):
            return AnkiConnectHTTPResponse(statusCode: status, body: Data(text.utf8))
        case .failure(let error):
            throw error
        case nil:
            return AnkiConnectHTTPResponse(statusCode: 200, body: Data(#"{"result":null,"error":"unsupported action"}"#.utf8))
        }
    }
}

final class AnkiConnectClientTests: XCTestCase {
    private func client(_ replies: [String: FakeAnkiTransport.Reply], apiKey: String? = nil, ankiRunning: Bool = false) -> (AnkiConnectClient, FakeAnkiTransport) {
        let transport = FakeAnkiTransport(replies)
        let client = AnkiConnectClient(transport: transport, apiKey: apiKey, isAnkiRunning: { ankiRunning })
        return (client, transport)
    }

    private func assertThrows<T>(_ expected: AnkiConnectError, _ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AnkiConnectError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: Request shape

    func testRequestsAlwaysCarryVersionSixAndNoKeyByDefault() async throws {
        let (client, transport) = client(["version": .json(#"{"result":6,"error":null}"#)])
        let version = try await client.version()
        XCTAssertEqual(version, 6)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request["action"] as? String, "version")
        XCTAssertEqual(request["version"] as? Int, 6)
        XCTAssertNil(request["key"])
        XCTAssertNil(request["params"])
        XCTAssertEqual(transport.timeouts, [3])
    }

    func testAPIKeyIsSentWhenConfigured() async throws {
        let (client, transport) = client(["getNumCardsReviewedToday": .json(#"{"result":42,"error":null}"#)], apiKey: "s3cret")
        let count = try await client.numCardsReviewedToday()
        XCTAssertEqual(count, 42)
        XCTAssertEqual(transport.requests.first?["key"] as? String, "s3cret")
    }

    // MARK: Permission

    func testPermissionDecodesCodeSpellingOfRequireApikey() async throws {
        let (client, _) = client(["requestPermission": .json(#"{"result":{"permission":"granted","requireApikey":true,"version":6},"error":null}"#)])
        let permission = try await client.connect()
        XCTAssertEqual(permission, AnkiPermission(granted: true, requireAPIKey: true, version: 6))
    }

    func testPermissionAlsoAcceptsReadmeSpelling() async throws {
        let (client, _) = client(["requestPermission": .json(#"{"result":{"permission":"granted","requireApiKey":true,"version":6},"error":null}"#)])
        let permission = try await client.requestPermission()
        XCTAssertTrue(permission.requireAPIKey)
    }

    func testDeniedPermissionThrowsFromConnect() async {
        let (client, _) = client(["requestPermission": .json(#"{"result":{"permission":"denied"},"error":null}"#)])
        await assertThrows(.permissionDenied) { try await client.connect() }
    }

    func testOldAddOnVersionIsRejectedByConnect() async {
        let (client, _) = client(["requestPermission": .json(#"{"result":{"permission":"granted","requireApikey":false,"version":5},"error":null}"#)])
        await assertThrows(.addOnOutdated(version: 5)) { try await client.connect() }
    }

    func testHTTP403MeansPermissionDenied() async {
        let (client, _) = client(["version": .json("", status: 403)])
        await assertThrows(.permissionDenied) { try await client.version() }
    }

    // MARK: Decks and stats

    func testDecksAreSortedWithIDs() async throws {
        let (client, _) = client(["deckNamesAndIds": .json(#"{"result":{"Step1::Cardio":3,"Default":1,"Step1":2},"error":null}"#)])
        let decks = try await client.decks()
        XCTAssertEqual(decks.map(\.name), ["Default", "Step1", "Step1::Cardio"])
        XCTAssertEqual(decks.map(\.id), [1, 2, 3])
        XCTAssertEqual(decks[2].leafName, "Cardio")
        XCTAssertEqual(decks[2].depth, 1)
        XCTAssertEqual(decks[0].depth, 0)
    }

    func testDeckStatsDecodeReadmeFixtureInRequestedOrder() async throws {
        let fixture = #"""
        {"result":{"1651445861967":{"deck_id":1651445861967,"name":"Japanese::JLPT N5","new_count":20,"learn_count":0,"review_count":0,"total_in_deck":1506},
                   "1651445861960":{"deck_id":1651445861960,"name":"Easy Spanish","new_count":26,"learn_count":10,"review_count":5,"total_in_deck":852}},"error":null}
        """#
        let (client, transport) = client(["getDeckStats": .json(fixture)])
        let stats = try await client.deckStats(for: ["Easy Spanish", "Japanese::JLPT N5", "Missing"])
        XCTAssertEqual(stats.map(\.name), ["Easy Spanish", "Japanese::JLPT N5"])
        XCTAssertEqual(stats[0], AnkiDeckStats(deckID: 1651445861960, name: "Easy Spanish", newCount: 26, learnCount: 10, reviewCount: 5, totalInDeck: 852))
        XCTAssertEqual(stats[0].dueTotal, 41)
        let params = transport.requests.first?["params"] as? [String: Any]
        XCTAssertEqual(params?["decks"] as? [String], ["Easy Spanish", "Japanese::JLPT N5", "Missing"])
    }

    func testDeckStatsForNoDecksSkipsTheRequest() async throws {
        let (client, transport) = client([:])
        let stats = try await client.deckStats(for: [])
        XCTAssertEqual(stats, [])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: History and reviews

    func testReviewedByDayDecodesHeterogeneousPairs() async throws {
        let (client, _) = client(["getNumCardsReviewedByDay": .json(#"{"result":[["2021-02-28",124],["2021-02-27",261]],"error":null}"#)])
        let days = try await client.numCardsReviewedByDay()
        XCTAssertEqual(days, [
            AnkiDayCount(day: AnkiDay(year: 2021, month: 2, day: 28), count: 124),
            AnkiDayCount(day: AnkiDay(year: 2021, month: 2, day: 27), count: 261),
        ])
    }

    func testMalformedDayIsAnInvalidResponse() async {
        let (client, _) = client(["getNumCardsReviewedByDay": .json(#"{"result":[["yesterday",1]],"error":null}"#)])
        do {
            _ = try await client.numCardsReviewedByDay()
            XCTFail("Expected an error")
        } catch let AnkiConnectError.invalidResponse(message) {
            XCTAssertTrue(message.hasPrefix("getNumCardsReviewedByDay"), message)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testCardReviewsDecodeNineTuples() async throws {
        let fixture = #"{"result":[[1594194095746,1485369733217,-1,3,4,-60,2500,6157,0],[1594201393292,1485369902086,-1,1,-60,-60,0,4846,1]],"error":null}"#
        let (client, transport) = client(["cardReviews": .json(fixture)])
        let reviews = try await client.cardReviews(deck: "default", startID: 1594194095740)
        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews[0], AnkiReview(id: 1594194095746, cardID: 1485369733217, ease: 3, interval: 4, lastInterval: -60, factor: 2500, durationMilliseconds: 6157, kind: .learn))
        XCTAssertTrue(reviews[1].isFailure)
        XCTAssertEqual(reviews[1].kind, .review)
        XCTAssertEqual(reviews[0].reviewedAt.timeIntervalSince1970, 1594194095.746, accuracy: 0.001)
        let params = transport.requests.first?["params"] as? [String: Any]
        XCTAssertEqual(params?["deck"] as? String, "default")
        XCTAssertEqual((params?["startID"] as? NSNumber)?.int64Value, 1594194095740)
    }

    func testUnknownReviewKindIsTolerated() async throws {
        let (client, _) = client(["cardReviews": .json(#"{"result":[[1,2,-1,3,4,5,2500,100,9]],"error":null}"#)])
        let reviews = try await client.cardReviews(deck: "d", startID: 0)
        XCTAssertEqual(reviews.first?.kind, .unknown)
    }

    func testFindCardsSendsQuery() async throws {
        let (client, transport) = client(["findCards": .json(#"{"result":[1494723142483,1494703460437],"error":null}"#)])
        let ids = try await client.findCards(query: #"deck:"Step1" rated:7"#)
        XCTAssertEqual(ids, [1494723142483, 1494703460437])
        XCTAssertEqual((transport.requests.first?["params"] as? [String: Any])?["query"] as? String, #"deck:"Step1" rated:7"#)
    }

    // MARK: GUI and sync

    func testGuiActionsSendDeckName() async throws {
        let (client, transport) = client([
            "guiDeckReview": .json(#"{"result":true,"error":null}"#),
            "guiDeckOverview": .json(#"{"result":false,"error":null}"#),
        ])
        let reviewed = try await client.guiDeckReview(name: "Step1")
        let overview = try await client.guiDeckOverview(name: "Nope")
        XCTAssertTrue(reviewed)
        XCTAssertFalse(overview)
        XCTAssertEqual(transport.requests.map { ($0["params"] as? [String: Any])?["name"] as? String }, ["Step1", "Nope"])
    }

    func testSyncUsesLongTimeoutAndAcceptsNullResult() async throws {
        let (client, transport) = client(["sync": .json(#"{"result":null,"error":null}"#)])
        try await client.sync()
        XCTAssertEqual(transport.timeouts, [90])
    }

    func testSyncWithoutAnkiWebLoginIsTyped() async {
        let (client, _) = client(["sync": .json(#"{"result":null,"error":"sync: auth not configured"}"#)])
        await assertThrows(.syncNotConfigured) { try await client.sync() }
    }

    // MARK: Error mapping

    func testRefusedConnectionWithoutAnkiMeansNotRunning() async {
        let (client, _) = client(["version": .failure(.connectionRefused)], ankiRunning: false)
        await assertThrows(.ankiNotRunning) { try await client.version() }
    }

    func testRefusedConnectionWhileAnkiRunsMeansAddOnMissing() async {
        let (client, _) = client(["version": .failure(.connectionRefused)], ankiRunning: true)
        await assertThrows(.addOnMissing) { try await client.version() }
    }

    func testTimeoutAndOtherTransportFailures() async {
        let (timingOut, _) = client(["version": .failure(.timedOut)])
        await assertThrows(.timeout) { try await timingOut.version() }
        let (broken, _) = client(["version": .failure(.failed("boom"))])
        await assertThrows(.transport("boom")) { try await broken.version() }
    }

    func testAnkiErrorStringsMapToTypedCases() async {
        let (keyed, _) = client(["deckNamesAndIds": .json(#"{"result":null,"error":"valid api key must be provided"}"#)])
        await assertThrows(.apiKeyRequired) { try await keyed.decks() }
        let (old, _) = client([:])
        await assertThrows(.unsupportedAction("getNumCardsReviewedByDay")) { try await old.numCardsReviewedByDay() }
        let (other, _) = client(["findCards": .json(#"{"result":null,"error":"invalid search"}"#)])
        await assertThrows(.anki("invalid search")) { try await other.findCards(query: "(") }
        XCTAssertEqual(AnkiConnectError.fromAnkiMessage("collection is not available", action: "x"), .collectionUnavailable)
    }

    func testNonJSONAndWrongTypesAreInvalidResponses() async {
        let (garbage, _) = client(["version": .json("<html>")])
        await assertThrows(.invalidResponse("version: not JSON")) { try await garbage.version() }
        let (wrong, _) = client(["version": .json(#"{"result":"six","error":null}"#)])
        do {
            _ = try await wrong.version()
            XCTFail("Expected an error")
        } catch let error as AnkiConnectError {
            guard case .invalidResponse = error else { return XCTFail("Got \(error)") }
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testEveryErrorHasHumanCopy() {
        let all: [AnkiConnectError] = [
            .ankiNotRunning, .addOnMissing, .timeout, .permissionDenied, .apiKeyRequired,
            .addOnOutdated(version: 4), .unsupportedAction("x"), .collectionUnavailable,
            .syncNotConfigured, .anki("x"), .invalidResponse("x"), .transport("x"),
        ]
        for error in all {
            XCTAssertFalse(error.title.isEmpty)
            XCTAssertTrue(error.suggestion.hasSuffix("."), error.suggestion)
        }
        XCTAssertTrue(AnkiConnectError.addOnMissing.suggestion.contains(AnkiConnectClient.addOnCode))
        XCTAssertTrue(AnkiConnectError.timeout.suggestion.contains("App Nap"))
    }

    // MARK: Transport and detection

    func testURLErrorClassification() {
        XCTAssertEqual(URLSessionAnkiConnectTransport.classify(URLError(.cannotConnectToHost)), .connectionRefused)
        XCTAssertEqual(URLSessionAnkiConnectTransport.classify(URLError(.timedOut)), .timedOut)
        guard case .failed = URLSessionAnkiConnectTransport.classify(URLError(.badServerResponse)) else {
            return XCTFail("Expected .failed")
        }
    }

    func testRealTransportReportsClosedPortAsAnkiNotRunning() async {
        // Port 1 on loopback is never listening, so this exercises the real
        // URLSession path end to end without depending on Anki being installed.
        let transport = URLSessionAnkiConnectTransport(endpoint: URL(string: "http://127.0.0.1:1")!)
        let client = AnkiConnectClient(transport: transport, requestTimeout: 2)
        await assertThrows(.ankiNotRunning) { try await client.version() }
    }

    func testDefaultEndpointIsLoopback() {
        XCTAssertEqual(URLSessionAnkiConnectTransport.defaultEndpoint.absoluteString, "http://127.0.0.1:8765")
    }

    func testAnkiAppDetectionAcceptsBothBundleIDsAndName() {
        XCTAssertTrue(AnkiConnectClient.isAnkiApp(bundleIdentifier: "net.ankiweb.anki", localizedName: nil))
        XCTAssertTrue(AnkiConnectClient.isAnkiApp(bundleIdentifier: "net.ankiweb.dtop", localizedName: nil))
        XCTAssertTrue(AnkiConnectClient.isAnkiApp(bundleIdentifier: "org.python.python", localizedName: "Anki"))
        XCTAssertFalse(AnkiConnectClient.isAnkiApp(bundleIdentifier: "com.apple.Safari", localizedName: "Safari"))
    }

    // MARK: AnkiDay

    func testAnkiDayParsingAndArithmetic() {
        XCTAssertNil(AnkiDay("2021-13-01"))
        XCTAssertNil(AnkiDay("nope"))
        let day = AnkiDay("2024-02-28")!
        XCTAssertEqual(day.adding(days: 1).description, "2024-02-29")
        XCTAssertEqual(day.adding(days: 2).description, "2024-03-01")
        XCTAssertEqual(AnkiDay("2025-01-01")!.adding(days: -1).description, "2024-12-31")
        XCTAssertLessThan(day, day.adding(days: 1))
    }

    func testAnkiDayFromDateRespectsRolloverHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let twoAM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 2))!
        XCTAssertEqual(AnkiDay(date: twoAM, rolloverHour: 4, calendar: calendar).description, "2026-09-30")
        XCTAssertEqual(AnkiDay(date: twoAM, rolloverHour: 0, calendar: calendar).description, "2026-10-01")
    }
}
