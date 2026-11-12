import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server with just enough Party to connect, and Crews: one crew I
/// may be in, the board, and session reports it credits and records.
private final class CrewsServer: PartyTransport, @unchecked Sendable {
    static let me = "ANAC2345"
    private let lock = NSLock()
    private var sent: [String] = []
    private var inCrew: Bool
    private var down = false

    init(inCrew: Bool) { self.inCrew = inCrew }

    var requests: [String] { lock.withLock { sent } }
    func count(_ prefix: String) -> Int { requests.filter { $0.hasPrefix(prefix) }.count }
    func setDown(_ isDown: Bool) { lock.withLock { down = isDown } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let route = "\(request.method) \(request.path)"
        let body = request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
        if lock.withLock({ down }) && route.hasPrefix("POST /v1/crews/sessions") {
            lock.withLock { sent.append("FAILED \(route) \(body)") }
            throw PartyError.unreachable
        }
        return lock.withLock {
            sent.append("\(route) \(body)")
            return answer(route, body)
        }
    }

    private let week = #"{"id":"2026-W46","startsAt":1794268800,"endsAt":1794873600}"#

    private func crew() -> String {
        #"{"id":"NGHTQWLS2K","name":"Night Owls","description":"","frame":"shield","emblem":"owl","color":"indigo","visibility":"private","laurel":null,"trophies":0,"memberCount":1,"maxMembers":20,"weekMinutes":0,"createdAt":1790000000,"rank":null,"mine":true,"owner":true,"inviteCode":"W4LNUT7","hidden":false,"members":[{"ref":"ANAREF2345","name":"Ana","pet":null,"weekMinutes":0,"owner":true,"me":true}]}"#
    }

    private func answer(_ route: String, _ body: String) -> PartyHTTPResponse {
        let now = Int(Date().timeIntervalSince1970)
        switch route {
        case "POST /v1/register":
            let profile = #"{"code":"\#(Self.me)","name":"Ana","petName":"Pet","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
            return reply(#"{"ok":true,"token":"\#(String(repeating: "1", count: 64))","code":"\#(Self.me)","profile":\#(profile)}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":{"code":"\#(Self.me)","name":"Ana","petName":"Pet","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}}"#)
        case "POST /v1/presence":
            let presence = #"{"status":"idle","sessionMinutes":0,"todayMinutes":0,"streakDays":0,"day":"2026-11-12","lastSeen":\#(now)}"#
            return reply(#"{"ok":true,"presence":\#(presence),"heartbeatSeconds":300}"#)
        case "GET /v1/grants": return reply(#"{"ok":true,"items":[]}"#)
        case "GET /v1/blocks": return reply(#"{"ok":true,"blocks":[]}"#)
        case "GET /v1/friends": return reply(#"{"ok":true,"friends":[],"incoming":[],"outgoing":[]}"#)
        case "GET /v1/party": return reply(#"{"ok":true,"party":null}"#)
        case "GET /v1/crews/mine": return reply(#"{"ok":true,"crew":\#(inCrew ? crew() : "null"),"week":\#(week)}"#)
        case "GET /v1/crews/board": return reply(#"{"ok":true,"week":\#(week),"top":[],"featured":null}"#)
        case "POST /v1/crews/leave":
            inCrew = false
            return reply(#"{"ok":true,"left":true}"#)
        case "POST /v1/crews/join":
            guard body.contains("W4LNUT7") else { return reply(#"{"ok":false,"error":"crew_not_found","message":"x"}"#, 404) }
            inCrew = true
            return reply(#"{"ok":true,"joined":true,"crew":\#(crew())}"#)
        case "POST /v1/crews/sessions":
            let count = body.components(separatedBy: "\"minutes\"").count - 1
            let results = Array(repeating: #"{"status":"credited","credited":25}"#, count: count).joined(separator: ",")
            return reply(#"{"ok":true,"results":[\#(results)],"week":\#(week),"crewMinutes":\#(25 * count),"myMinutes":\#(25 * count)}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"x"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// The Crew section's store: what it sends, when it reports sessions, and
/// how it follows the server's answers.
@MainActor
final class CrewsStoreTests: XCTestCase {
    private var records = PassthroughSubject<ActivityRecord, Never>()

    private func make(_ server: CrewsServer, storage: URL? = nil) async throws -> (PartyStore, CrewsStore) {
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        let crews = CrewsStore(party: party, runMode: .live, storage: storage)
        crews.follow(activity: records.eraseToAnyPublisher())
        party.start()
        try await waitUntil { party.state.friendCode == CrewsServer.me && crews.state.mineLoaded }
        return (party, crews)
    }

    private func focus(minutes: Double, endingAgo seconds: TimeInterval = 0) -> ActivityRecord {
        let end = Date().addingTimeInterval(-seconds)
        return ActivityRecord(source: .focus, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60), end: end,
                              quantity: minutes, unit: .minutes)
    }

    func testFinishedFocusIsReportedOnceWhileInACrew() async throws {
        let server = CrewsServer(inCrew: true)
        let (party, crews) = try await make(server)
        defer { party.stop() }
        XCTAssertTrue(crews.state.inCrew)

        records.send(focus(minutes: 25))
        try await waitUntil { server.count("POST /v1/crews/sessions") == 1 }
        try await waitUntil { crews.state.mine?.summary.weekMinutes == 25 }
        XCTAssertEqual(crews.state.mine?.me?.weekMinutes, 25, "my minutes follow the reply")
        // A break or cards never go out.
        records.send(ActivityRecord(source: .focus, kind: .breakTaken, start: Date(), end: Date().addingTimeInterval(300),
                                    quantity: 5, unit: .minutes))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.count("POST /v1/crews/sessions"), 1)
    }

    func testNothingIsKeptOrSentOutsideACrew() async throws {
        let server = CrewsServer(inCrew: false)
        let (party, crews) = try await make(server)
        defer { party.stop() }
        XCTAssertFalse(crews.state.inCrew)
        records.send(focus(minutes: 25))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(server.count("POST /v1/crews/sessions"), 0)
    }

    func testJoiningByPastedInviteThenLeaving() async throws {
        let server = CrewsServer(inCrew: false)
        let (party, crews) = try await make(server)
        defer { party.stop() }

        crews.join(invite: "Join my crew: https://tabbinotch.com/crew/w4ln-ut7")
        try await waitUntil { crews.pending == nil && crews.state.inCrew }
        XCTAssertTrue(server.requests.contains { $0.hasPrefix("POST /v1/crews/join") && $0.contains(#""code":"W4LNUT7""#) })
        XCTAssertEqual(party.notice, "You joined Night Owls.")

        crews.leave()
        try await waitUntil { crews.pending == nil && !crews.state.inCrew }
        XCTAssertEqual(server.count("POST /v1/crews/leave"), 1)

        crews.join(invite: "abc")
        XCTAssertEqual(party.notice, "Crew invite codes have 7 characters.")
        XCTAssertNil(crews.pending, "a malformed code is refused before anything is sent")
    }

    func testSessionsWaitThroughAnOutageInTheQueueFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("crews-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = CrewsServer(inCrew: true)
        server.setDown(true)
        // Both stores are held: the module owns its store in the app.
        let (party, first) = try await make(server, storage: folder)
        records.send(focus(minutes: 25))
        let file = CrewSessionQueueFile(folder: folder)
        // The send failed for the outage and the session stayed in the file.
        try await waitUntil { server.count("FAILED POST /v1/crews/sessions") == 1 }
        XCTAssertEqual(file.load().pending.count, 1)
        party.stop()
        withExtendedLifetime(first) {}

        // A later launch picks the queue up and sends it once the server answers.
        server.setDown(false)
        records = PassthroughSubject()
        let (again, second) = try await make(server, storage: folder)
        defer { again.stop() }
        try await waitUntil { server.count("POST /v1/crews/sessions") >= 1 && file.load().pending.isEmpty }
        withExtendedLifetime(second) {}
    }

    private func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
