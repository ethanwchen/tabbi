import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that registers one user and counts every request.
private final class CountingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var requests: Int { lock.withLock { count } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { count += 1 }
        let profile = #"{"code":"CODE0001","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch (request.method, request.path) {
        case ("POST", "/v1/register"):
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"CODE0001","profile":\#(profile)}"#, 201)
        case ("PATCH", "/v1/me"):
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        case ("GET", "/v1/grants"):
            return reply(#"{"ok":true,"items":[]}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// The bond look is drawn on the user's own pet in Party but never sent, so
/// a bond level that grows the collar does not reconnect to the server.
@MainActor
final class PetBondPartyTests: XCTestCase {
    func testAGrowingBondLookShowsInPartyWithoutReconnecting() async throws {
        let server = CountingFriendsServer()
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        party.start()
        defer { party.stop() }
        try await waitUntil { party.state.connection == .connected }
        try await Task.sleep(nanoseconds: 200_000_000)
        let settled = server.requests

        var grown = party.pet
        grown.bondLook = PetBond(points: PetBond.thresholds[PetBond.maxLevel - 1]).look
        party.update(pet: grown)
        XCTAssertEqual(party.pet.bondLook, grown.bondLook, "Party draws the grown pet")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(server.requests, settled, "the bond look is never sent")

        var renamed = grown
        renamed.rename("Biscuit")
        party.update(pet: renamed)
        try await waitUntil { server.requests > settled }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
