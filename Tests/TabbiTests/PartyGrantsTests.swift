import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that registers one user and answers `GET /v1/grants`
/// with the limited edition items a maintainer granted it.
private final class GrantingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    private let items: [String]

    init(items: [String]) { self.items = items }

    var grantFetches: Int { lock.withLock { fetches } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let profile = #"{"code":"CODE0001","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch (request.method, request.path) {
        case ("POST", "/v1/register"):
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"CODE0001","profile":\#(profile)}"#, 201)
        case ("PATCH", "/v1/me"):
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        case ("GET", "/v1/grants"):
            lock.withLock { fetches += 1 }
            let list = items.map { "\"\($0)\"" }.joined(separator: ",")
            return reply(#"{"ok":true,"items":[\#(list)]}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// Event items granted on the server (the launch week cap) reach users who
/// never signed in, through their Party identity.
@MainActor
final class PartyGrantsTests: XCTestCase {
    func testASignedOutPartyIdentityReceivesItsGrantsOncePerIdentity() async throws {
        let cap = PetLimitedEdition.launchWeekCap.item
        let server = GrantingFriendsServer(items: [cap.id])
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        let pet = ClosetStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                              runMode: RunMode(isSnapshot: true))
        var received: [[String]] = []
        let watch = party.grants.sink { items in
            received.append(items)
            pet.applyGrants(items)
        }
        defer { watch.cancel() }

        party.start()
        defer { party.stop() }
        try await waitUntil { !received.isEmpty }
        XCTAssertEqual(received, [[cap.id]])
        XCTAssertEqual(pet.closet.save.ledger.granted, [cap])
        XCTAssertEqual(pet.closet.save.ledger.spent, 0, "a grant costs no points")

        // A new pet look reconnects, which does not ask for grants again.
        party.update(pet: .starter(.dog))
        try await waitUntil { party.state.connection == .connected }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(server.grantFetches, 1)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
