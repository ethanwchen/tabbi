import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that hands out a new friend code per registration and
/// can refuse `DELETE /v1/me`, recording each route with its token.
private final class DeletingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var registrations = 0
    private var sent: [String] = []
    private let refusesDelete: Bool

    init(refusesDelete: Bool = false) { self.refusesDelete = refusesDelete }

    /// Each request as "METHOD /path token", the token's first digit only.
    var requests: [String] { lock.withLock { sent } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let token = request.token.map { String($0.prefix(1)) } ?? "-"
        let route = "\(request.method) \(request.path)"
        let number = lock.withLock { () -> Int in
            sent.append("\(route) \(token)")
            if route == "POST /v1/register" { registrations += 1 }
            return route == "POST /v1/register" ? registrations : Int(token) ?? 0
        }
        let code = "CODE000\(number)"
        let profile = #"{"code":"\#(code)","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch route {
        case "POST /v1/register":
            let token = String(repeating: String(number), count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"\#(code)","profile":\#(profile)}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        case "DELETE /v1/me":
            return refusesDelete
                ? reply(#"{"ok":false,"error":"internal","message":"try later"}"#, 500)
                : reply(#"{"ok":true}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// Settings > Party's "Delete my Party data": the signed-out way to delete
/// what the friends server keeps (App Store Guideline 5.1.1(v)).
@MainActor
final class PartyDataDeletionTests: XCTestCase {
    private func makeStore(_ server: DeletingFriendsServer) -> PartyStore {
        PartyStore(runMode: RunMode(isSnapshot: true),
                   environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                   transport: server)
    }

    func testDeletingRemovesTheUserAndStartsOverWithANewFriendCode() async throws {
        let server = DeletingFriendsServer()
        let party = makeStore(server)
        party.start()
        defer { party.stop() }
        try await waitUntil { party.state.friendCode == "CODE0001" }

        party.deletePartyData()
        XCTAssertEqual(party.pending, .deleteData)
        try await waitUntil { party.state.friendCode == "CODE0002" }

        XCTAssertNil(party.pending)
        XCTAssertEqual(party.deletionNotice, "Your Party data was deleted.")
        XCTAssertTrue(server.requests.contains("DELETE /v1/me 1"))
        // The old identity is never used after the delete.
        let afterDelete = server.requests.drop { $0 != "DELETE /v1/me 1" }.dropFirst()
        XCTAssertFalse(afterDelete.contains { $0.hasSuffix(" 1") }, "\(afterDelete)")
    }

    func testAFailedDeleteKeepsTheIdentityAndSaysWhy() async throws {
        let party = makeStore(DeletingFriendsServer(refusesDelete: true))
        party.start()
        defer { party.stop() }
        try await waitUntil { party.state.friendCode == "CODE0001" }

        party.deletePartyData()
        try await waitUntil { party.pending == nil && party.state.friendCode != nil }

        XCTAssertEqual(party.state.friendCode, "CODE0001")
        XCTAssertNotNil(party.deletionNotice)
        XCTAssertNotEqual(party.deletionNotice, "Your Party data was deleted.")
    }

    func testTheDemoDeletesNothing() {
        let party = PartyStore(runMode: RunMode(isDemo: true))
        party.deletePartyData()
        XCTAssertNil(party.pending)
        XCTAssertEqual(party.deletionNotice, "This is a demo. Nothing was deleted.")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
