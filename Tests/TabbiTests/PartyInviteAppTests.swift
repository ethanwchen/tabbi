import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server with no friends yet that knows one other user, Maya,
/// and records each request as "METHOD /path body".
private final class InvitingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []

    var requests: [String] { lock.withLock { sent } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let route = "\(request.method) \(request.path)"
        let body = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        lock.withLock { sent.append("\(route) \(body)") }
        let me = #"{"code":"CODE0001","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        let maya = #"{"code":"M4YA8QRT","name":"Maya","petName":"Biscuit","species":"dog","breed":"goldenRetriever","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch route {
        case "POST /v1/register":
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"CODE0001","profile":\#(me)}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":\#(me)}"#)
        case "GET /v1/friends":
            return reply(#"{"ok":true,"friends":[]}"#)
        case "GET /v1/blocks":
            return reply(#"{"ok":true,"blocks":[]}"#)
        case "GET /v1/party":
            return reply(#"{"ok":true,"party":null}"#)
        case "POST /v1/friends":
            return body.contains("M4YA8QRT")
                ? reply(#"{"ok":true,"added":true,"friend":\#(maya)}"#, 201)
                : reply(#"{"ok":false,"error":"unknown_code","message":"no such user"}"#, 404)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// What an opened invite link does in Party: it asks first, sends one
/// request once confirmed, and ends in the person, the party or a
/// friendly refusal.
@MainActor
final class PartyInviteAppTests: XCTestCase {
    private func makeStore(_ server: InvitingFriendsServer) async throws -> PartyStore {
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        party.start()
        try await waitUntil { party.state.friendCode == "CODE0001" }
        return party
    }

    func testAFriendLinkAsksThenAddsTheFriend() async throws {
        let server = InvitingFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.open(.addFriend(code: "M4YA8QRT"), partyIsOn: true)
        try await waitUntil { party.invite?.stage == .confirming }
        XCTAssertFalse(server.requests.contains { $0.hasPrefix("POST /v1/friends") }, "nothing is sent before a click")

        party.confirmInvite()
        try await waitUntil { party.invite?.isDone == true }
        XCTAssertEqual(party.invite?.title, "Maya is now your friend")
        XCTAssertEqual(party.invite?.person?.petName, "Biscuit")
        XCTAssertEqual(server.requests.filter { $0.hasPrefix("POST /v1/friends") }, [#"POST /v1/friends {"code":"M4YA8QRT"}"#])

        party.dismissInvite()
        XCTAssertNil(party.invite)
    }

    func testALinkNobodyHasAnymoreSaysToAskForANewOne() async throws {
        let party = try await makeStore(InvitingFriendsServer())
        defer { party.stop() }

        party.open(.addFriend(code: "ZZZZ2222"), partyIsOn: true)
        try await waitUntil { party.invite?.stage == .confirming }
        party.confirmInvite()
        try await waitUntil { party.invite?.stage == .refused(.failed(.unknownCode)) }
        XCTAssertEqual(party.invite?.message, "This link doesn't match anyone now. Ask your friend for a new one.")
        XCTAssertNil(party.invite?.primaryTitle)
    }

    func testMyOwnLinkAnswersWithoutSendingAnything() async throws {
        let server = InvitingFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.open(.addFriend(code: "CODE0001"), partyIsOn: true)
        try await waitUntil { party.invite?.stage == .refused(.ownCode) }
        party.confirmInvite()
        XCTAssertFalse(server.requests.contains { $0.hasPrefix("POST /v1/friends") })
    }

    func testTheDemoAddsAFriendAfterTurningPartyOn() {
        let party = PartyStore(runMode: .demo, environment: [:])
        party.open(.addFriend(code: "AVA7K3RN"), partyIsOn: false)
        XCTAssertEqual(party.invite?.stage, .needsParty)

        party.start()
        party.inviteTurnedPartyOn()
        XCTAssertEqual(party.invite?.stage, .confirming)

        party.confirmInvite()
        XCTAssertEqual(party.invite?.stage, .finished(.added(.demoInvitee)))
        XCTAssertTrue(party.state.friends.contains { $0.profile.code == "AVA7K3RN" })
    }

    func testTheDemoJoinsTheLinkedParty() {
        let party = PartyStore(runMode: .demo, environment: [:])
        party.open(.joinParty(code: "ZX7M2P"), partyIsOn: true)
        XCTAssertEqual(party.invite?.stage, .confirming)

        party.confirmInvite()
        guard case .finished(.joined(let joined)) = party.invite?.stage else {
            return XCTFail("expected to join, got \(String(describing: party.invite?.stage))")
        }
        XCTAssertEqual(joined.code, "ZX7M2P")
        XCTAssertEqual(party.state.party?.code, "ZX7M2P")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
