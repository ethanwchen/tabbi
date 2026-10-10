import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that keeps state like the Hub: who my friends are, the
/// party I'm in and its shared session. It knows two other users, Ben and
/// Maya, and Maya hosts a party (`Q4RT8M`) with a session running.
/// Every request is recorded as "METHOD /path body".
private final class StatefulFriendsServer: PartyTransport, @unchecked Sendable {
    static let me = "ANAC2345"
    static let ben = "K7QW2MZD"
    static let maya = "M4YA8QRT"
    static let mayasParty = "Q4RT8M"
    static let myParty = "H7ST42"

    private let lock = NSLock()
    private var sent: [String] = []
    private var friends: [String] = []
    /// The party I'm in: its code and whether I host it.
    private var party: (code: String, hosting: Bool)?
    private var session: (method: String, endsAt: Int)?
    /// Makes the next party action answer `not_in_party`, as when the
    /// party expired while the panel was open.
    private var losesParty = false

    var requests: [String] { lock.withLock { sent } }

    func count(_ prefix: String) -> Int { requests.filter { $0.hasPrefix(prefix) }.count }

    func dropParty() {
        lock.withLock {
            party = nil
            losesParty = true
        }
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let route = "\(request.method) \(request.path)"
        let body = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        return lock.withLock {
            sent.append("\(route) \(body)")
            return answer(route, body)
        }
    }

    private func answer(_ route: String, _ body: String) -> PartyHTTPResponse {
        let now = Int(Date().timeIntervalSince1970)
        switch route {
        case "POST /v1/register":
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"\#(Self.me)","profile":\#(profile(Self.me))}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":\#(profile(Self.me))}"#)
        case "POST /v1/presence":
            let presence = #"{"status":"idle","sessionMinutes":0,"todayMinutes":0,"streakDays":0,"day":"2026-10-09","lastSeen":\#(now)}"#
            return reply(#"{"ok":true,"presence":\#(presence),"heartbeatSeconds":300}"#)
        case "GET /v1/grants":
            return reply(#"{"ok":true,"items":[]}"#)
        case "GET /v1/blocks":
            return reply(#"{"ok":true,"blocks":[]}"#)
        case "GET /v1/friends":
            let list = friends.map { code in
                let ref = code == Self.maya ? #"{"code":"\#(Self.mayasParty)","size":2}"# : "null"
                return #"{"profile":\#(profile(code)),"since":\#(now),"presence":null,"online":true,"party":\#(ref)}"#
            }
            return reply(#"{"ok":true,"friends":[\#(list.joined(separator: ","))]}"#)
        case "POST /v1/friends":
            if body.contains(Self.me) { return failure("self_friend", 400) }
            guard let code = [Self.ben, Self.maya].first(where: body.contains) else { return failure("unknown_code", 404) }
            let added = !friends.contains(code)
            if added { friends.append(code) }
            return reply(#"{"ok":true,"added":\#(added),"friend":\#(profile(code))}"#, added ? 201 : 200)
        case "POST /v1/blocks":
            guard let code = [Self.ben, Self.maya].first(where: body.contains) else { return failure("unknown_code", 404) }
            friends.removeAll { $0 == code }
            let block = #"{"code":"\#(code)","name":"\#(name(code))","petName":"Pet"}"#
            return reply(#"{"ok":true,"blocked":true,"block":\#(block)}"#)
        case "GET /v1/party":
            return reply(#"{"ok":true,"party":\#(partyJSON(now) ?? "null")}"#)
        case "POST /v1/party":
            party = (Self.myParty, true)
            session = nil
            return partyReply(now)
        case "POST /v1/party/join":
            if body.contains(#""friend""#) {
                guard friends.contains(Self.maya), body.contains(Self.maya) else { return failure("not_friend", 403) }
            } else if !body.contains(Self.mayasParty) {
                return failure("party_not_found", 404)
            }
            party = (Self.mayasParty, false)
            session = ("pomodoro", now + 20 * 60)
            return partyReply(now)
        case "POST /v1/party/leave":
            if losesParty { return failure("not_in_party", 409) }
            let left = party != nil
            party = nil
            session = nil
            return reply(#"{"ok":true,"left":\#(left)}"#)
        case "POST /v1/party/session":
            if losesParty { return failure("not_in_party", 409) }
            guard party?.hosting == true else { return failure("not_host", 403) }
            let method = body.contains("deepFocus") ? "deepFocus" : "pomodoro"
            let ends = body.split(separator: ",").first { $0.contains("phaseEndsAt") }
                .flatMap { Int($0.filter(\.isNumber)) } ?? now
            session = (method, ends)
            return partyReply(now)
        case "DELETE /v1/party/session":
            guard party?.hosting == true else { return failure("not_host", 403) }
            session = nil
            return partyReply(now)
        default:
            if route.hasPrefix("DELETE /v1/friends/") {
                let code = String(route.dropFirst("DELETE /v1/friends/".count))
                let removed = friends.contains(code)
                friends.removeAll { $0 == code }
                return reply(#"{"ok":true,"removed":\#(removed)}"#)
            }
            return failure("not_found", 404)
        }
    }

    private func name(_ code: String) -> String {
        [Self.me: "Ana", Self.ben: "Ben", Self.maya: "Maya"][code] ?? "Someone"
    }

    private func profile(_ code: String) -> String {
        #"{"code":"\#(code)","name":"\#(name(code))","petName":"Pet","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
    }

    private func partyJSON(_ now: Int) -> String? {
        guard let party else { return nil }
        let host = party.hosting ? Self.me : Self.maya
        let members = (party.hosting ? [Self.me] : [Self.maya, Self.me]).map { code in
            #"{"profile":\#(profile(code)),"joinedAt":\#(now),"host":\#(code == host),"presence":null,"online":true}"#
        }
        let sessionJSON = session.map { #"{"method":"\#($0.method)","phaseEndsAt":\#($0.endsAt),"startedAt":\#(now)}"# } ?? "null"
        return #"{"code":"\#(party.code)","host":"\#(host)","createdAt":\#(now),"lastActive":\#(now),"expiresAt":\#(now + 43200),"maxMembers":8,"session":\#(sessionJSON),"members":[\#(members.joined(separator: ","))]}"#
    }

    private func partyReply(_ now: Int) -> PartyHTTPResponse {
        reply(#"{"ok":true,"party":\#(partyJSON(now) ?? "null")}"#)
    }

    private func failure(_ code: String, _ status: Int) -> PartyHTTPResponse {
        reply(#"{"ok":false,"error":"\#(code)","message":"\#(code)"}"#, status)
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// The Party panel's actions through `PartyStore`: what each sends, how the
/// state follows the server's answer, and the notice a refusal leaves.
@MainActor
final class PartyStoreActionTests: XCTestCase {
    private typealias Server = StatefulFriendsServer

    private func makeStore(_ server: StatefulFriendsServer) async throws -> PartyStore {
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        party.start()
        try await waitUntil { party.state.friendCode == Server.me && party.state.friendsLoaded }
        return party
    }

    /// Waits for the action in flight to finish.
    private func settle(_ party: PartyStore) async throws {
        try await waitUntil { party.pending == nil }
    }

    func testAMalformedCodeIsRefusedBeforeAnythingIsSent() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.addFriend(code: "abc")
        XCTAssertEqual(party.notice, "Friend codes are 8 letters and digits.")
        XCTAssertNil(party.pending)
        party.joinParty(code: "Q4RT8M0")
        XCTAssertEqual(party.notice, "Party codes are 6 letters and digits.")
        XCTAssertEqual(server.count("POST /v1/friends"), 0)
        XCTAssertEqual(server.count("POST /v1/party/join"), 0)
    }

    func testAddingAndRemovingAFriendFollowsTheServer() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.addFriend(code: "k7qw-2mzd")
        XCTAssertEqual(party.pending, .addFriend, "the button shows progress while it is sent")
        try await settle(party)
        XCTAssertNil(party.notice)
        XCTAssertEqual(party.state.friends.map(\.profile.name), ["Ben"])
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("POST /v1/friends") && $0.contains(Server.ben) },
                      "a pasted code is sent normalized")

        party.removeFriend(code: Server.ben)
        XCTAssertEqual(party.pending, .removeFriend(Server.ben))
        try await settle(party)
        XCTAssertEqual(party.state.friends, [])
        XCTAssertEqual(server.count("DELETE /v1/friends/\(Server.ben)"), 1)
    }

    func testARefusedFriendCodeLeavesTheListAndSaysWhy() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.addFriend(code: "ZZZZ2222")
        try await settle(party)
        XCTAssertEqual(party.notice, PartyError.unknownCode.message)
        XCTAssertFalse(party.noticeConfirms)
        XCTAssertEqual(party.state.friends, [])

        party.addFriend(code: Server.me)
        try await settle(party)
        XCTAssertEqual(party.notice, PartyError.selfFriend.message)

        party.clearNotice()
        XCTAssertNil(party.notice)
    }

    func testOnlyOneActionRunsAtATime() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.createParty()
        party.createParty()
        party.joinParty(code: Server.mayasParty)
        try await settle(party)
        XCTAssertEqual(server.count("POST /v1/party "), 1, "a double click sends one request")
        XCTAssertEqual(server.count("POST /v1/party/join"), 0)
        XCTAssertEqual(party.state.party?.code, Server.myParty)
    }

    func testHostingAPartyRunsAndEndsASharedSession() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.createParty()
        try await settle(party)
        XCTAssertTrue(party.state.isHost)
        XCTAssertNil(party.state.party?.session)

        let started = Date()
        party.startSession(minutes: 25)
        XCTAssertEqual(party.pending, .session)
        try await settle(party)
        let ends = try XCTUnwrap(party.state.party?.session?.phaseEndsAt)
        XCTAssertEqual(ends.timeIntervalSince(started), 25 * 60, accuracy: 5)
        XCTAssertEqual(party.state.session(at: Date())?.endsAt, ends, "the session is shared with other modules")

        party.endSession()
        try await settle(party)
        XCTAssertNil(party.state.party?.session)
        XCTAssertNil(party.notice)

        party.leaveParty()
        try await settle(party)
        XCTAssertFalse(party.state.inParty)
        XCTAssertEqual(server.count("POST /v1/party/leave"), 1)
    }

    func testAGuestJoinsByCodeButCannotRunTheSession() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.joinParty(code: "QQQQ22")
        try await settle(party)
        XCTAssertEqual(party.notice, PartyError.partyNotFound.message)
        XCTAssertFalse(party.state.inParty)

        party.joinParty(code: "q4rt-8m")
        try await settle(party)
        XCTAssertEqual(party.state.party?.code, Server.mayasParty)
        XCTAssertFalse(party.state.isHost)
        let session = try XCTUnwrap(party.state.party?.session)

        party.startSession(minutes: 50)
        try await settle(party)
        XCTAssertEqual(party.notice, PartyError.notHost.message)
        XCTAssertEqual(party.state.party?.session, session, "a refused start leaves the host's session")
    }

    func testJoiningThroughAFriendNeedsTheFriendship() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.join(friend: Server.maya)
        try await settle(party)
        XCTAssertEqual(party.notice, PartyError.notFriend.message)
        XCTAssertFalse(party.state.inParty)

        party.addFriend(code: Server.maya)
        try await settle(party)
        party.join(friend: Server.maya)
        XCTAssertEqual(party.pending, .joinFriend(Server.maya))
        try await settle(party)
        XCTAssertNil(party.notice)
        XCTAssertEqual(party.state.party?.code, Server.mayasParty)
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("POST /v1/party/join") && $0.contains(#""friend":"\#(Server.maya)""#) })
    }

    func testLeavingTheSessionIsLocalAndRejoiningBringsItBack() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.joinParty(code: Server.mayasParty)
        try await settle(party)
        XCTAssertNotNil(party.state.session(at: Date()))
        let sent = server.requests.count

        party.leaveSession()
        XCTAssertTrue(party.state.hasLeftSession(at: Date()))
        XCTAssertNil(party.state.session(at: Date()), "the Timer tab drops a session I stepped out of")
        XCTAssertTrue(party.state.inParty, "stepping out keeps me in the party")

        party.rejoinSession()
        XCTAssertFalse(party.state.hasLeftSession(at: Date()))
        XCTAssertNotNil(party.state.session(at: Date()))
        XCTAssertFalse(server.requests.dropFirst(sent).contains { $0.contains("/v1/party") && !$0.hasPrefix("GET") },
                       "neither step tells the server")
    }

    func testAPartyThatEndedOnTheServerIsDroppedWhenAnActionFails() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.createParty()
        try await settle(party)
        XCTAssertTrue(party.state.inParty)

        server.dropParty()
        party.startSession(minutes: 25)
        try await settle(party)
        XCTAssertFalse(party.state.inParty, "not_in_party clears the stale party at once")
        XCTAssertEqual(party.notice, PartyError.notInParty.message)
    }

    func testBlockingAFriendRemovesThemAndConfirms() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.addFriend(code: Server.ben)
        try await settle(party)
        let ben = try XCTUnwrap(party.state.friends.first?.profile)

        party.block(ben)
        XCTAssertEqual(party.pending, .block(Server.ben))
        try await settle(party)
        XCTAssertEqual(party.state.friends, [])
        XCTAssertEqual(party.blocked?.map(\.code), [Server.ben])
        XCTAssertTrue(party.noticeConfirms)
        XCTAssertEqual(party.notice, "Blocked Ben. Unblock them in Party options.")
    }

    func testRetryWhileConnectedRefetchesFriendsAndParty() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        try await waitUntil { server.count("GET /v1/party") >= 1 }
        let friends = server.count("GET /v1/friends")
        let parties = server.count("GET /v1/party")
        party.retry()
        try await waitUntil { server.count("GET /v1/friends") > friends && server.count("GET /v1/party") > parties }
        XCTAssertEqual(server.count("POST /v1/register"), 1, "a retry while connected does not register again")
    }

    func testCancellingAReportClosesTheCard() async throws {
        let server = StatefulFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        let ben = PartyProfile(code: Server.ben, name: "Ben", petName: "Pet", species: "cat", breed: "tabby")
        party.beginReport(ben)
        XCTAssertEqual(party.reporting, ben)
        party.cancelReport()
        XCTAssertNil(party.reporting)
        XCTAssertEqual(server.count("POST /v1/reports"), 0)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
