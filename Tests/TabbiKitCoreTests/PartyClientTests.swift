import XCTest
import TabbiKitCore

/// Replays recorded friends-server replies by `METHOD path` and records
/// what the client sent.
private final class FakePartyTransport: PartyTransport, @unchecked Sendable {
    enum Reply {
        case json(String, status: Int = 200, retryAfter: TimeInterval? = nil)
        case failure(Error)
    }

    private let lock = NSLock()
    private let replies: [String: Reply]
    private var sent: [PartyHTTPRequest] = []

    init(_ replies: [String: Reply]) { self.replies = replies }

    var requests: [PartyHTTPRequest] { lock.withLock { sent } }

    /// The JSON body of the last request, as a dictionary.
    var lastBody: [String: Any] {
        guard let body = requests.last?.body else { return [:] }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let reply: Reply? = lock.withLock {
            sent.append(request)
            return replies["\(request.method) \(request.path)"]
        }
        switch reply {
        case .json(let text, let status, let retryAfter):
            return PartyHTTPResponse(statusCode: status, body: Data(text.utf8), retryAfter: retryAfter)
        case .failure(let error):
            throw error
        case nil:
            return PartyHTTPResponse(statusCode: 404, body: Data(#"{"ok":false,"error":"not_found","message":"no route"}"#.utf8))
        }
    }
}

/// Recorded replies, shaped exactly like `docs/study/backend-api.md`.
private enum Fixture {
    static let ana = ##"{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":["#F2A65A","#FFFFFF"],"costume":"scrubs","accessories":["glasses","coffee-mug"],"points":1240,"level":7}"##
    static let ben = #"{"code":"B3NX9QRT","name":"Ben","petName":"Biscuit","species":"dog","breed":"corgi","colors":[],"costume":"none","accessories":[],"points":80,"level":2}"#
    static let studying = #"{"status":"studying","method":"pomodoro","phaseEndsAt":1790000000,"sessionMinutes":50,"todayMinutes":125,"streakDays":12,"day":"2026-10-01","lastSeen":1789999100}"#
    static let offline = #"{"status":"offline","method":null,"phaseEndsAt":null,"sessionMinutes":0,"todayMinutes":30,"streakDays":3,"day":"2026-09-30","lastSeen":1789900000}"#
    static let party = #"{"ok":true,"party":{"code":"Q4RT8M","host":"K7QW2MZD","createdAt":1789990000,"lastActive":1789999000,"expiresAt":1790042200,"maxMembers":8,"session":{"method":"pomodoro","phaseEndsAt":1790000000,"startedAt":1789998500},"members":[{"profile":\#(ana),"joinedAt":1789990000,"host":true,"presence":\#(studying),"online":true},{"profile":\#(ben),"joinedAt":1789991000,"host":false,"presence":null,"online":false}]}}"#
    static func error(_ code: String) -> String { #"{"ok":false,"error":"\#(code)","message":"whatever"}"# }
}

final class PartyClientTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)

    private func client(_ replies: [String: FakePartyTransport.Reply], token: String? = nil) -> (PartyClient, FakePartyTransport) {
        let transport = FakePartyTransport(replies)
        return (PartyClient(transport: transport, token: token ?? self.token), transport)
    }

    private func assertThrows<T>(_ expected: PartyError, _ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as PartyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: Profile

    func testRegisterSendsNoTokenAndReturnsCredentials() async throws {
        let (client, transport) = self.client([
            "POST /v1/register": .json(#"{"ok":true,"token":"\#(token)","code":"K7QW2MZD","profile":\#(Fixture.ana)}"#, status: 201),
        ], token: "stale")
        let registration = try await client.register(PartyProfileUpdate(name: "Ana", petName: "Mochi", species: "cat", breed: "tabby"))
        XCTAssertEqual(registration.token, token)
        XCTAssertEqual(registration.code, "K7QW2MZD")
        XCTAssertEqual(registration.profile.accessories, ["glasses", "coffee-mug"])
        XCTAssertNil(transport.requests.last?.token)
        XCTAssertEqual(transport.lastBody as NSDictionary, ["name": "Ana", "petName": "Mochi", "species": "cat", "breed": "tabby"])
    }

    func testProfileUpdateOnlySendsChangedFields() async throws {
        let (client, transport) = self.client(["PATCH /v1/me": .json(#"{"ok":true,"profile":\#(Fixture.ana)}"#)])
        let profile = try await client.updateProfile(PartyProfileUpdate(costume: "scrubs", accessories: ["glasses"], level: 7))
        XCTAssertEqual(profile.costume, "scrubs")
        XCTAssertEqual(transport.requests.last?.token, token)
        XCTAssertEqual(transport.lastBody as NSDictionary, ["costume": "scrubs", "accessories": ["glasses"], "level": 7])
    }

    func testCallsNeedingATokenFailWithoutOne() async {
        let transport = FakePartyTransport([:])
        let client = PartyClient(transport: transport)
        await assertThrows(.unauthorized) { try await client.me() }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testDeleteMe() async throws {
        let (client, transport) = self.client(["DELETE /v1/me": .json(#"{"ok":true}"#)])
        try await client.deleteMe()
        XCTAssertEqual(transport.requests.map(\.method), ["DELETE"])
    }

    // MARK: Friends

    func testFriendsDecodeProfilePresenceAndParty() async throws {
        let body = #"{"ok":true,"friends":[{"profile":\#(Fixture.ana),"since":1789000000,"presence":\#(Fixture.studying),"online":true,"party":{"code":"Q4RT8M","size":3}},{"profile":\#(Fixture.ben),"since":1789000500,"presence":\#(Fixture.offline),"online":false,"party":null},{"profile":\#(Fixture.ben),"since":1789000500,"presence":null,"online":false,"party":{"code":"Q4RT8M","size":3}}]}"#
        let (client, _) = self.client(["GET /v1/friends": .json(body)])
        let friends = try await client.friends()
        XCTAssertEqual(friends.count, 3)
        XCTAssertEqual(friends[0].presence?.status, .studying)
        XCTAssertEqual(friends[0].presence?.phaseEndsAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(friends[0].party, PartyRef(code: "Q4RT8M", size: 3))
        XCTAssertTrue(friends[0].canJoin)
        XCTAssertEqual(friends[1].presence?.status, .offline)
        XCTAssertNil(friends[1].presence?.method)
        XCTAssertFalse(friends[1].canJoin)
        XCTAssertNil(friends[2].presence)
        XCTAssertFalse(friends[2].canJoin, "an offline friend's party is not joinable")
    }

    func testAddFriendNormalizesThePastedCode() async throws {
        let (client, transport) = self.client(["POST /v1/friends": .json(#"{"ok":true,"added":true,"friend":\#(Fixture.ben)}"#)])
        let result = try await client.addFriend(code: "  b3nx-9qrt ")
        XCTAssertTrue(result.added)
        XCTAssertEqual(result.friend.petName, "Biscuit")
        XCTAssertEqual(transport.lastBody as NSDictionary, ["code": "B3NX9QRT"])
    }

    func testAddFriendRejectsMalformedCodesWithoutARequest() async {
        let (client, transport) = self.client([:])
        await assertThrows(.invalidRequest("invalid_field")) { try await client.addFriend(code: "B3NX9QR1") }
        await assertThrows(.invalidRequest("invalid_field")) { try await client.addFriend(code: "short") }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAddFriendErrorsAreTyped() async {
        let cases: [(String, Int, PartyError)] = [
            ("self_friend", 400, .selfFriend),
            ("unknown_code", 404, .unknownCode),
            ("friend_limit", 409, .friendLimit),
            ("their_friend_limit", 409, .theirFriendLimit),
        ]
        for (code, status, expected) in cases {
            let (client, _) = self.client(["POST /v1/friends": .json(Fixture.error(code), status: status)])
            await assertThrows(expected) { try await client.addFriend(code: "B3NX9QRT") }
        }
    }

    func testRemoveFriendUsesTheCodeInThePath() async throws {
        let (client, transport) = self.client(["DELETE /v1/friends/B3NX9QRT": .json(#"{"ok":true,"removed":false}"#)])
        let removed = try await client.removeFriend(code: "b3nx9qrt")
        XCTAssertFalse(removed)
        XCTAssertEqual(transport.requests.last?.path, "/v1/friends/B3NX9QRT")
    }

    // MARK: Presence and leaderboard

    func testHeartbeatSendsWholeSecondsAndOmitsUnsetCounters() async throws {
        let (client, transport) = self.client([
            "POST /v1/presence": .json(#"{"ok":true,"presence":\#(Fixture.studying),"heartbeatSeconds":120}"#),
        ])
        let beat = PartyHeartbeat(status: .studying, method: "pomodoro", phaseEndsAt: Date(timeIntervalSince1970: 1_790_000_000.4), todayMinutes: 125, day: "2026-10-01")
        let reply = try await client.heartbeat(beat)
        XCTAssertEqual(reply.nextHeartbeat, 120)
        XCTAssertEqual(reply.presence.todayMinutes, 125)
        XCTAssertEqual(transport.lastBody as NSDictionary, [
            "status": "studying", "method": "pomodoro", "phaseEndsAt": 1_790_000_000, "todayMinutes": 125, "day": "2026-10-01",
        ])
    }

    func testOfflineHeartbeatSaysStop() async throws {
        let (client, transport) = self.client([
            "POST /v1/presence": .json(#"{"ok":true,"presence":\#(Fixture.offline),"heartbeatSeconds":null}"#),
        ])
        let reply = try await client.heartbeat(.offline)
        XCTAssertNil(reply.nextHeartbeat)
        XCTAssertEqual(transport.lastBody as NSDictionary, ["status": "offline"])
    }

    func testLeaderboardKeepsSharedRanks() async throws {
        let body = #"{"ok":true,"week":"2026-W40","from":"2026-09-28","to":"2026-10-04","entries":[{"rank":1,"minutes":840,"me":false,"profile":\#(Fixture.ana)},{"rank":1,"minutes":840,"me":true,"profile":\#(Fixture.ben)}]}"#
        let (client, _) = self.client(["GET /v1/leaderboard": .json(body)])
        let board = try await client.leaderboard()
        XCTAssertEqual(board.week, "2026-W40")
        XCTAssertEqual(board.entries.map(\.rank), [1, 1])
        XCTAssertEqual(board.entries.first(where: \.me)?.profile.name, "Ben")
    }

    // MARK: Parties

    func testNoPartyDecodesAsNil() async throws {
        let (client, _) = self.client(["GET /v1/party": .json(#"{"ok":true,"party":null}"#)])
        let party = try await client.party()
        XCTAssertNil(party)
    }

    func testPartyDecodesMembersAndSession() async throws {
        let (client, transport) = self.client(["POST /v1/party": .json(Fixture.party, status: 201)])
        let party = try await client.createParty()
        XCTAssertNil(transport.requests.last?.body, "an empty body counts as {}")
        XCTAssertEqual(party.code, "Q4RT8M")
        XCTAssertTrue(party.isHost("K7QW2MZD"))
        XCTAssertFalse(party.isHost("B3NX9QRT"))
        XCTAssertEqual(party.session?.method, "pomodoro")
        XCTAssertEqual(party.session?.phaseEndsAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(party.members.map(\.profile.name), ["Ana", "Ben"])
        XCTAssertEqual(party.members.map(\.host), [true, false])
        XCTAssertNil(party.members[1].presence)
        XCTAssertFalse(party.isFull)
    }

    func testJoinByCodeOrFriendSendsExactlyOneField() async throws {
        let (client, transport) = self.client(["POST /v1/party/join": .json(Fixture.party)])
        _ = try await client.joinParty(code: "q4rt8m")
        XCTAssertEqual(transport.lastBody as NSDictionary, ["code": "Q4RT8M"])
        _ = try await client.joinParty(friend: "K7QW2MZD")
        XCTAssertEqual(transport.lastBody as NSDictionary, ["friend": "K7QW2MZD"])
        await assertThrows(.invalidRequest("invalid_field")) { try await client.joinParty(code: "K7QW2MZD") }
    }

    func testJoinErrorsAreTyped() async {
        let cases: [(String, Int, PartyError)] = [
            ("party_not_found", 404, .partyNotFound),
            ("not_friend", 403, .notFriend),
            ("friend_offline", 409, .friendOffline),
            ("friend_not_in_party", 404, .friendNotInParty),
            ("party_full", 409, .partyFull),
        ]
        for (code, status, expected) in cases {
            let (client, _) = self.client(["POST /v1/party/join": .json(Fixture.error(code), status: status)])
            await assertThrows(expected) { try await client.joinParty(friend: "K7QW2MZD") }
        }
    }

    func testLeaveAndSessionControls() async throws {
        let (client, transport) = self.client([
            "POST /v1/party/leave": .json(#"{"ok":true,"left":true}"#),
            "POST /v1/party/session": .json(Fixture.party),
            "DELETE /v1/party/session": .json(Fixture.error("not_host"), status: 403),
        ])
        let left = try await client.leaveParty()
        XCTAssertTrue(left)
        _ = try await client.startSession(method: "pomodoro", phaseEndsAt: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(transport.lastBody as NSDictionary, ["method": "pomodoro", "phaseEndsAt": 1_790_000_000])
        await assertThrows(.notHost) { try await client.endSession() }
    }

    // MARK: Failures

    func testCommonFailuresAreClassified() async {
        let cases: [(FakePartyTransport.Reply, PartyError)] = [
            (.json(Fixture.error("unauthorized"), status: 401), .unauthorized),
            (.json(Fixture.error("rate_limited"), status: 429, retryAfter: 17), .rateLimited(retryAfter: 17)),
            (.json(Fixture.error("unavailable"), status: 503), .serverUnavailable),
            (.json("<html>Bad gateway</html>", status: 502), .serverUnavailable),
            (.json(Fixture.error("brand_new_code"), status: 418), .server(code: "brand_new_code", status: 418)),
            (.json("<html>captive portal</html>"), .invalidResponse("not a friends-server reply")),
            (.failure(PartyError.unreachable), .unreachable),
        ]
        for (reply, expected) in cases {
            let (client, _) = self.client(["GET /v1/me": reply])
            await assertThrows(expected) { try await client.me() }
        }
    }

    func testHealthCheckNeedsNoToken() async throws {
        let transport = FakePartyTransport(["GET /": .json(#"{"ok":true,"service":"tabbi-friends","version":1}"#)])
        let healthy = try await PartyClient(transport: transport).health()
        XCTAssertTrue(healthy)
        XCTAssertNil(transport.requests.last?.token)
    }

    func testHealthCheckAcceptsThePreRenameWorkerButNoOtherService() async throws {
        let cases = [("studynotch-friends", true), ("tabbi-friends", true), ("some-other-api", false)]
        for (service, expected) in cases {
            let transport = FakePartyTransport(["GET /": .json(#"{"ok":true,"service":"\#(service)","version":1}"#)])
            let healthy = try await PartyClient(transport: transport).health()
            XCTAssertEqual(healthy, expected, service)
        }
    }

    func testURLErrorsMapToReachabilityStates() {
        XCTAssertEqual(URLSessionPartyTransport.classify(URLError(.notConnectedToInternet)), .unreachable)
        XCTAssertEqual(URLSessionPartyTransport.classify(URLError(.cannotConnectToHost)), .unreachable)
        XCTAssertEqual(URLSessionPartyTransport.classify(URLError(.timedOut)), .timedOut)
    }

    func testRouteJoinsOntoBaseURLWithOrWithoutSlash() {
        let route = "/v1/party"
        XCTAssertEqual(URLSessionPartyTransport.url(base: URL(string: "http://localhost:8787/")!, path: route).absoluteString, "http://localhost:8787/v1/party")
        XCTAssertEqual(URLSessionPartyTransport.url(base: PartyServer.productionURL, path: route).absoluteString, PartyServer.productionURL.absoluteString + route)
    }
}

final class PartyServerAndCodeTests: XCTestCase {
    func testServerURLParsing() {
        XCTAssertEqual(PartyServer.parse(" example.workers.dev/ ")?.absoluteString, "https://example.workers.dev")
        XCTAssertEqual(PartyServer.parse("http://localhost:8787")?.absoluteString, "http://localhost:8787")
        XCTAssertNil(PartyServer.parse("http://example.com"), "plain http only for this Mac")
        XCTAssertNil(PartyServer.parse("ftp://example.com"))
        XCTAssertNil(PartyServer.parse(""))
        XCTAssertEqual(PartyServer.parse(PartyServer.productionURL.absoluteString), PartyServer.productionURL)
    }

    func testCodeNormalization() {
        XCTAssertEqual(PartyCode.friendCode("k7qw 2mzd"), "K7QW2MZD")
        XCTAssertEqual(PartyCode.partyCode("q4r-t8m"), "Q4RT8M")
        XCTAssertNil(PartyCode.friendCode("K7QW2MZO"), "O is not in the alphabet")
        XCTAssertNil(PartyCode.partyCode("K7QW2MZD"), "a friend code is not a party code")
    }
}

final class PartyHeartbeatScheduleTests: XCTestCase {
    private func reply(_ status: PartyStatus, next: TimeInterval?) -> PartyHeartbeatReply {
        PartyHeartbeatReply(presence: PartyPresence(status: status, day: "2026-10-02", lastSeen: Date()), nextHeartbeat: next)
    }

    func testFollowsServerIntervalAndStopsAfterOffline() {
        var schedule = PartyHeartbeatSchedule()
        XCTAssertEqual(schedule.delayAfterSuccess(reply(.studying, next: 120)), 120)
        XCTAssertEqual(schedule.delayAfterSuccess(reply(.idle, next: 300)), 300)
        XCTAssertNil(schedule.delayAfterSuccess(reply(.offline, next: nil)))
    }

    func testBacksOffExponentiallyUpToFiveMinutes() {
        var schedule = PartyHeartbeatSchedule()
        let delays = (0..<8).map { _ in schedule.delayAfterFailure(.unreachable) }
        XCTAssertEqual(delays, [5, 10, 20, 40, 80, 160, 300, 300])
        _ = schedule.delayAfterSuccess(reply(.studying, next: 120))
        XCTAssertEqual(schedule.delayAfterFailure(.serverUnavailable), 5, "a success resets the backoff")
    }

    func testRateLimitWaitsForRetryAfterAndPermanentErrorsStop() {
        var schedule = PartyHeartbeatSchedule()
        XCTAssertEqual(schedule.delayAfterFailure(.rateLimited(retryAfter: 42)), 42)
        XCTAssertNil(schedule.delayAfterFailure(.unauthorized))
        XCTAssertNil(schedule.delayAfterFailure(.invalidRequest("invalid_field")))
    }
}
