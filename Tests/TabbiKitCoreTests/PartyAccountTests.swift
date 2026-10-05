import XCTest
import TabbiKitCore

/// A tiny stand-in friends server: it knows which tokens are valid, hands
/// out new ones on register, and records every request.
private final class FakeFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var validTokens: Set<String>
    private var registrations = 0
    private var sent: [PartyHTTPRequest] = []
    /// Delays each register reply, to overlap concurrent calls.
    var registerDelay: UInt64 = 0
    var unreachable = false

    init(validTokens: Set<String> = []) { self.validTokens = validTokens }

    var requests: [String] { lock.withLock { sent.map { "\($0.method) \($0.path)" } } }
    var registerCount: Int { lock.withLock { registrations } }
    func revoke(_ token: String) { _ = lock.withLock { validTokens.remove(token) } }

    static func token(_ n: Int) -> String { String(format: "%064d", n) }
    static func code(_ n: Int) -> String { "CODE000\(n)" }
    static func profile(code: String, name: String = "Ana") -> String {
        #"{"code":"\#(code)","name":"\#(name)","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { sent.append(request) }
        if unreachable { throw PartyError.unreachable }
        let route = "\(request.method) \(request.path)"
        if route == "POST /v1/register" {
            if registerDelay > 0 { try await Task.sleep(nanoseconds: registerDelay) }
            let n: Int = lock.withLock {
                registrations += 1
                validTokens.insert(Self.token(registrations))
                return registrations
            }
            let name = (request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["name"] as? String ?? "Studier"
            return reply(#"{"ok":true,"token":"\#(Self.token(n))","code":"\#(Self.code(n))","profile":\#(Self.profile(code: Self.code(n), name: name))}"#, 201)
        }
        guard let token = request.token, lock.withLock({ validTokens.contains(token) }) else {
            return reply(#"{"ok":false,"error":"unauthorized","message":"no"}"#, 401)
        }
        let code = Self.code(Int(token) ?? 0)
        switch route {
        case "GET /v1/me", "PATCH /v1/me":
            let name = (request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["name"] as? String ?? "Ana"
            return reply(#"{"ok":true,"profile":\#(Self.profile(code: code, name: name))}"#)
        case "GET /v1/friends":
            return reply(#"{"ok":true,"friends":[]}"#)
        case "DELETE /v1/me":
            revoke(token)
            return reply(#"{"ok":true,"deleted":true}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

final class PartyAccountTests: XCTestCase {
    private let server = URL(string: "http://localhost:8787")!

    func testFirstConnectRegistersWithTheProfileAndStoresTheToken() async throws {
        let fake = FakeFriendsServer()
        let store = InMemoryPartyCredentialStore()
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        let profile = try await account.connect(profile: PartyProfileUpdate(name: "Ana"))

        XCTAssertEqual(profile.name, "Ana")
        XCTAssertEqual(fake.requests, ["POST /v1/register"])
        XCTAssertEqual(store.load(for: server), PartyCredentials(token: FakeFriendsServer.token(1), code: FakeFriendsServer.code(1)))
        let code = await account.friendCode
        XCTAssertEqual(code, FakeFriendsServer.code(1))
    }

    func testStoredIdentityIsReusedAndTheProfilePatched() async throws {
        let token = FakeFriendsServer.token(7)
        let fake = FakeFriendsServer(validTokens: [token])
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(7))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        let profile = try await account.connect(profile: PartyProfileUpdate(name: "Ben"))

        XCTAssertEqual(profile.name, "Ben")
        XCTAssertEqual(profile.code, FakeFriendsServer.code(7))
        XCTAssertEqual(fake.requests, ["PATCH /v1/me"])
        XCTAssertEqual(fake.registerCount, 0)
    }

    func testRevokedTokenRegistersAgainWithTheLastProfileAndRetriesOnce() async throws {
        let fake = FakeFriendsServer()
        let store = InMemoryPartyCredentialStore()
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        try await account.connect(profile: PartyProfileUpdate(name: "Ana"))
        fake.revoke(FakeFriendsServer.token(1))

        let friends = try await account.perform { try await $0.friends() }

        XCTAssertEqual(friends, [])
        XCTAssertEqual(fake.requests, ["POST /v1/register", "GET /v1/friends", "POST /v1/register", "GET /v1/friends"])
        XCTAssertEqual(store.load(for: server)?.code, FakeFriendsServer.code(2))
        let profile = await account.profile
        XCTAssertEqual(profile?.name, "Ana", "the new identity keeps the synced name")
    }

    func testConcurrentCallsShareOneRegistration() async throws {
        let fake = FakeFriendsServer()
        fake.registerDelay = 50_000_000
        let account = PartyAccount(server: server, transport: fake, credentials: InMemoryPartyCredentialStore())

        async let first = account.perform { try await $0.friends() }
        async let second = account.perform { try await $0.me() }
        _ = try await (first, second)

        XCTAssertEqual(fake.registerCount, 1)
    }

    func testUnreachableServerLeavesNoIdentityAndThrowsTransient() async {
        let fake = FakeFriendsServer()
        fake.unreachable = true
        let store = InMemoryPartyCredentialStore()
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        do {
            try await account.connect(profile: PartyProfileUpdate(name: "Ana"))
            XCTFail("Expected unreachable")
        } catch {
            XCTAssertEqual(error as? PartyError, .unreachable)
            XCTAssertTrue((error as? PartyError)?.isTransient ?? false)
        }
        XCTAssertNil(store.load(for: server))

        fake.unreachable = false
        let profile = try? await account.connect(profile: PartyProfileUpdate(name: "Ana"))
        XCTAssertEqual(profile?.code, FakeFriendsServer.code(1), "a later attempt registers normally")
    }

    func testDeleteAccountForgetsTheTokenSoTheNextConnectStartsOver() async throws {
        let fake = FakeFriendsServer()
        let store = InMemoryPartyCredentialStore()
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        try await account.connect(profile: PartyProfileUpdate())

        try await account.deleteAccount()

        XCTAssertNil(store.load(for: server))
        let code = await account.friendCode
        XCTAssertNil(code)
        let profile = try await account.connect(profile: PartyProfileUpdate())
        XCTAssertEqual(profile.code, FakeFriendsServer.code(2))
        XCTAssertEqual(fake.requests, ["POST /v1/register", "DELETE /v1/me", "POST /v1/register"])
    }

    func testIdentitiesStayPerServer() async throws {
        let store = InMemoryPartyCredentialStore()
        let local = PartyAccount(server: server, transport: FakeFriendsServer(), credentials: store)
        try await local.connect(profile: PartyProfileUpdate())

        let other = PartyAccount(server: PartyServer.productionURL, transport: FakeFriendsServer(), credentials: store)
        let otherCode = await other.friendCode

        XCTAssertNil(otherCode)
        XCTAssertNotNil(store.load(for: server))
    }
}
