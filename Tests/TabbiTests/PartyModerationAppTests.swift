import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that answers the moderation routes and records each
/// request as "METHOD /path body".
private final class ModeratingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    private let refusesReports: Bool

    init(refusesReports: Bool = false) { self.refusesReports = refusesReports }

    var requests: [String] { lock.withLock { sent } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let route = "\(request.method) \(request.path)"
        let body = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        lock.withLock { sent.append("\(route) \(body)") }
        let profile = #"{"code":"CODE0001","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        let ben = #"{"code":"K7QW2MZD","name":"Ben","petName":"Olive"}"#
        switch route {
        case "POST /v1/register":
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"CODE0001","profile":\#(profile)}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        case "POST /v1/reports":
            return refusesReports
                ? reply(#"{"ok":false,"error":"report_limit","message":"too many"}"#, 429)
                : reply(#"{"ok":true,"created":true}"#, 201)
        case "POST /v1/blocks":
            return reply(#"{"ok":true,"blocked":true,"block":\#(ben)}"#)
        case "GET /v1/blocks":
            return reply(#"{"ok":true,"blocks":[\#(ben)]}"#)
        case "DELETE /v1/blocks/K7QW2MZD":
            return reply(#"{"ok":true,"unblocked":true}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// Report and Block from the Party panel, and the Blocked list in Party
/// options (App Store Guideline 1.2).
@MainActor
final class PartyModerationAppTests: XCTestCase {
    private let ben = PartyProfile(code: "K7QW2MZD", name: "Ben", petName: "Olive", species: "dog", breed: "beagle")

    private func makeStore(_ server: ModeratingFriendsServer) async throws -> PartyStore {
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        party.start()
        try await waitUntil { party.state.friendCode == "CODE0001" }
        return party
    }

    func testReportingAndBlockingSendsBothAndClosesTheCard() async throws {
        let server = ModeratingFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        party.beginReport(ben)
        XCTAssertEqual(party.reporting, ben)
        party.sendReport(reason: .harassment, note: "  mean messages  ", alsoBlock: true)
        try await waitUntil { party.pending == nil }

        XCTAssertNil(party.reporting)
        XCTAssertTrue(party.noticeConfirms)
        XCTAssertEqual(party.notice, "Thanks. Your report was sent and Ben is blocked.")
        XCTAssertEqual(party.blocked?.map(\.code), ["K7QW2MZD"])
        let moderation = server.requests.filter { $0.contains("reports") || $0.contains("blocks") }
        guard moderation.count == 2 else { return XCTFail("\(moderation)") }
        XCTAssertTrue(moderation[0].hasPrefix("POST /v1/reports"))
        XCTAssertTrue(moderation[0].contains(#""reason":"harassment""#))
        XCTAssertTrue(moderation[0].contains(#""note":"mean messages""#))
        XCTAssertTrue(moderation[1].hasPrefix("POST /v1/blocks"))
    }

    func testAFailedReportKeepsTheCardOpenAndSaysWhy() async throws {
        let server = ModeratingFriendsServer(refusesReports: true)
        let party = try await makeStore(server)
        defer { party.stop() }

        party.beginReport(ben)
        party.sendReport(reason: .spam, note: "", alsoBlock: true)
        try await waitUntil { party.pending == nil }

        XCTAssertEqual(party.reporting, ben)
        XCTAssertFalse(party.noticeConfirms)
        XCTAssertEqual(party.notice, PartyError.reportLimit.message)
        XCTAssertFalse(server.requests.contains { $0.hasPrefix("POST /v1/blocks") }, "no block without the report")
    }

    func testTheBlockedListLoadsAndUnblocks() async throws {
        let server = ModeratingFriendsServer()
        let party = try await makeStore(server)
        defer { party.stop() }

        XCTAssertNil(party.blocked)
        party.loadBlocked()
        try await waitUntil { party.blocked != nil }
        XCTAssertEqual(party.blocked?.map(\.name), ["Ben"])

        party.unblock(code: "K7QW2MZD")
        try await waitUntil { party.pending == nil && party.blocked?.isEmpty == true }
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("DELETE /v1/blocks/K7QW2MZD") })
    }

    func testTheDemoSendsNothing() {
        let party = PartyStore(runMode: RunMode(isDemo: true))
        party.beginReport(ben)
        party.sendReport(reason: .other, note: "", alsoBlock: false)
        XCTAssertNil(party.reporting)
        XCTAssertEqual(party.notice, "This is a demo. No report was sent.")

        party.loadBlocked()
        XCTAssertEqual(party.blocked?.count, 1, "the demo shows a sample Blocked list")
        party.unblock(code: party.blocked?.first?.code ?? "")
        XCTAssertEqual(party.blocked, [], "Unblock in the demo empties its sample list")
        XCTAssertNil(party.pending)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
