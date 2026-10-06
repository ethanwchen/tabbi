import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A friends server that registers anyone and echoes profile edits,
/// recording the name each request sent.
private final class EchoFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(route: String, name: String?)] = []

    /// The routes that carried a name, with that name, in order.
    var namesSent: [String] { lock.withLock { sent.compactMap { entry in entry.name.map { "\(entry.route) \($0)" } } } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        let body = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let name = body?["name"] as? String
        let route = "\(request.method) \(request.path)"
        lock.withLock { sent.append((route, name)) }
        let profile = #"{"code":"CODE0001","name":"\#(name ?? "Studier")","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch route {
        case "POST /v1/register":
            return reply(#"{"ok":true,"token":"\#(String(repeating: "1", count: 64))","code":"CODE0001","profile":\#(profile)}"#, 201)
        case "PATCH /v1/me":
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

/// Party's name is the app-wide name: one value that Settings > General,
/// the Party pane and the friends server all agree on.
@MainActor
final class PartyNameTests: XCTestCase {
    private func makeServices() throws -> (SettingsStore, PartyStore) {
        let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        return (settings, try XCTUnwrap(services.modules.module(PartyModule.self)).store)
    }

    func testPartyShowsTheNameSetInGeneral() throws {
        let (settings, party) = try makeServices()
        settings.settings.displayName = "Ana"
        XCTAssertEqual(party.settings.name, "Ana")
        XCTAssertEqual(party.settings.cleanedName, "Ana")
    }

    func testANameEditedInPartyBecomesTheAppWideName() throws {
        let (settings, party) = try makeServices()
        var edited = party.settings
        edited.name = "Ben"
        party.update(edited)
        XCTAssertEqual(settings.settings.displayName, "Ben")
        XCTAssertEqual(party.settings.name, "Ben")
    }

    func testANewNameSyncsToTheServerOnceTypingPauses() async throws {
        let server = EchoFriendsServer()
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787"],
                               transport: server)
        let names = CurrentValueSubject<String, Never>("Ana")
        party.follow(name: names.eraseToAnyPublisher(), save: { _ in })
        party.start()
        defer { party.stop() }
        try await waitUntil { party.state.profile?.name == "Ana" }

        // General saves on every keystroke: only the settled name is sent.
        for typed in ["B", "Be", "Ben"] { names.send(typed) }
        try await waitUntil { party.state.profile?.name == "Ben" }
        XCTAssertEqual(server.namesSent, ["POST /v1/register Ana", "PATCH /v1/me Ben"])
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
