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
    /// Answers `PATCH /v1/me` the way the server does for a banned user.
    var banned = false
    /// Names the server refuses (a maintainer's name hold), as `name_not_allowed`.
    var heldNames: Set<String> = []
    /// Pet names it refuses, as `pet_name_not_allowed`.
    var heldPetNames: Set<String> = []
    /// Answers like a self-hosted server still on catalog version 1: newer
    /// accessory ids and more than six colors are an `invalid_field`.
    var catalogVersion1 = false
    /// Answers like a server still on catalog version 3: the mastery
    /// outfits' ids (and release 7's) are an `invalid_field`.
    var catalogVersion3 = false
    /// Answers like a server from before protocol 3: the Study Level
    /// fields are an `unknown_field`, as for any body field it does not know.
    var protocol2 = false
    /// Answers like a server still on catalog version 4: release 7's ids
    /// are an `invalid_field`.
    var catalogVersion4 = false
    /// The pet fields of every profile body it took.
    private(set) var takenBodies: [[String: Any]] = []

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
        let fields = request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        if let name = fields?["name"] as? String, heldNames.contains(name) {
            return reply(#"{"ok":false,"error":"name_not_allowed","message":"no"}"#, 400)
        }
        if let petName = fields?["petName"] as? String, heldPetNames.contains(petName) {
            return reply(#"{"ok":false,"error":"pet_name_not_allowed","message":"no"}"#, 400)
        }
        if protocol2, let fields, fields["studyLevel"] != nil || fields["nameplate"] != nil {
            return reply(#"{"ok":false,"error":"unknown_field","message":"unknown field: studyLevel"}"#, 400)
        }
        if catalogVersion1, let fields {
            let known: Set<String> = ["glasses", "sunglasses", "headphones", "bow", "scarf", "crown", "flower", "party-hat", "beanie", "halo"]
            let accessories = fields["accessories"] as? [String] ?? []
            if !accessories.allSatisfy(known.contains) || (fields["colors"] as? [String] ?? []).count > 6 {
                return reply(#"{"ok":false,"error":"invalid_field","message":"invalid accessories"}"#, 400)
            }
        }
        if catalogVersion3 || catalogVersion4, let fields {
            let release7: Set<String> = [
                "librarian-cardigan", "varsity-jacket", "keepers-peacoat", "rain-slicker", "koi-yukata", "sushi-chef",
                "snow-day-puffer", "daisy-chain", "sailor-collar", "strawberry-cap", "mushroom-cap", "cactus-pot",
                "sun-hat", "aviator-cap", "fireflies",
            ]
            let ids = (fields["accessories"] as? [String] ?? []) + [fields["costume"] as? String].compactMap { $0 }
            if ids.contains(where: release7.contains) {
                return reply(#"{"ok":false,"error":"invalid_field","message":"invalid costume"}"#, 400)
            }
        }
        if catalogVersion3, let fields {
            let added: Set<String> = [
                "astronaut-suit", "starry-cloak", "apprentice-robe", "scholars-robe", "sages-robe", "bakers-apron",
                "little-sprout", "blossom-sprout", "nightcap", "explorers-hat", "bee-antennae", "sporty-sweatband",
                "owl-spectacles", "tiny-lantern",
            ]
            let ids = (fields["accessories"] as? [String] ?? []) + [fields["costume"] as? String].compactMap { $0 }
            if ids.contains(where: added.contains) {
                return reply(#"{"ok":false,"error":"invalid_field","message":"invalid costume"}"#, 400)
            }
        }
        if let fields { lock.withLock { takenBodies.append(fields) } }
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
            let flag = banned ? #","banned":true"# : ""
            return reply(#"{"ok":true,"profile":\#(Self.profile(code: code, name: name))\#(flag)}"#)
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

    func testConnectThrowsBannedWhenTheServerSaysSo() async throws {
        let token = FakeFriendsServer.token(7)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.banned = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(7))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        do {
            try await account.connect(profile: PartyProfileUpdate(name: "Ben"))
            XCTFail("expected banned")
        } catch {
            XCTAssertEqual(error as? PartyError, .banned)
        }
        // The identity stays: an unban later lets the same friend code back in.
        XCTAssertEqual(store.load(for: server)?.code, FakeFriendsServer.code(7))
        XCTAssertEqual(fake.requests, ["PATCH /v1/me"])
    }

    func testARefusedNameIsLeftOutSoTheRestStillSyncs() async throws {
        let token = FakeFriendsServer.token(7)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.heldNames = ["Rude"]
        fake.heldPetNames = ["Worse"]
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(7))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        let profile = try await account.connect(profile: PartyProfileUpdate(name: "Rude", petName: "Worse", breed: "tabby"))

        XCTAssertEqual(profile.name, "Ana", "the server keeps the name it has")
        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me", "PATCH /v1/me"])
        let refused = await account.refusedNames
        XCTAssertEqual(refused, [.name, .petName])

        fake.heldNames = []
        try await account.connect(profile: PartyProfileUpdate(name: "Ana"))
        let cleared = await account.refusedNames
        XCTAssertEqual(cleared, [], "a name the server takes clears the refusal")
    }

    func testAServerOnCatalogVersion1GetsTheLookItCanCarry() async throws {
        let token = FakeFriendsServer.token(7)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.catalogVersion1 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(7))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Nova", breed: .corgi, outfit: .dinosaurHoodie, accessories: [.roundGlasses, .wizardHat])

        _ = try await account.connect(profile: PartyPetAppearance.update(for: pet))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me"], "refused once, then sent as catalog version 1 takes it")
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertEqual(taken["accessories"] as? [String], ["glasses"])
        XCTAssertEqual(taken["costume"] as? String, "hoodie")
        XCTAssertEqual((taken["colors"] as? [String])?.count, 6)
    }

    /// A server not yet on catalog version 4 refuses the mastery outfits;
    /// the profile goes again without just those, so friends there still
    /// see the rest of the pet, before anything falls back to version 1.
    func testAServerOnCatalogVersion3GetsEverythingButTheMasteryOutfits() async throws {
        let token = FakeFriendsServer.token(8)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.catalogVersion3 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(8))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Nova", breed: .corgi, outfit: .astronautSuit,
                             accessories: [.friendshipBandana, .nightcap, .roundGlasses])

        _ = try await account.connect(profile: PartyPetAppearance.update(for: pet))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me"], "refused once, then sent without the new ids")
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertEqual(taken["accessories"] as? [String], ["bandana", "glasses"])
        XCTAssertEqual(taken["costume"] as? String, "none")
        XCTAssertEqual((taken["colors"] as? [String])?.count, PartyPetAppearance.colorRoles.count)
    }

    /// A current app talking to a server from before protocol 3: the
    /// Study Level is refused, the profile goes again without it, and
    /// Party stays online with the pet as before.
    func testAnOlderServerGetsTheProfileWithoutTheStudyLevel() async throws {
        let token = FakeFriendsServer.token(9)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.protocol2 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(9))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Nova", breed: .corgi, accessories: [.roundGlasses])
        let update = PartyPetAppearance.update(for: pet)
            .sharing(StudyStanding(level: StudyLevel(12), nameplate: .ember))

        let profile = try await account.connect(profile: update)

        XCTAssertEqual(profile.code, FakeFriendsServer.code(9))
        XCTAssertNil(profile.standing, "that server shows no level")
        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me"], "refused once, then sent without the level")
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertNil(taken["studyLevel"])
        XCTAssertNil(taken["nameplate"])
        XCTAssertEqual(taken["accessories"] as? [String], ["glasses"], "the pet goes through whole")
    }

    /// A server older still, before protocol 3 and catalog version 4:
    /// the level goes first, then the mastery outfit's id.
    func testAnOlderServerOnCatalogVersion3DropsTheLevelThenTheNewIds() async throws {
        let token = FakeFriendsServer.token(10)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.protocol2 = true
        fake.catalogVersion3 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(10))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Nova", breed: .corgi, outfit: .astronautSuit, accessories: [.roundGlasses])

        _ = try await account.connect(profile: PartyPetAppearance.update(for: pet)
            .sharing(StudyStanding(level: StudyLevel(40), nameplate: .nebula)))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me", "PATCH /v1/me"])
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertNil(taken["studyLevel"])
        XCTAssertEqual(taken["costume"] as? String, "none")
        XCTAssertEqual(taken["accessories"] as? [String], ["glasses"])
    }

    /// A current server keeps the level, and the first try goes through.
    func testACurrentServerTakesTheStudyLevelAtOnce() async throws {
        let token = FakeFriendsServer.token(11)
        let fake = FakeFriendsServer(validTokens: [token])
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(11))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)

        _ = try await account.connect(profile: PartyProfileUpdate(petName: "Nova")
            .sharing(StudyStanding(level: StudyLevel(7), nameplate: .peach)))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me"])
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertEqual(taken["studyLevel"] as? Int, 7)
        XCTAssertEqual(taken["nameplate"] as? String, "peach")
    }

    /// A server not yet on catalog version 5 refuses release 7's items; the
    /// profile goes again without just those, keeping the mastery outfits a
    /// version 4 server takes.
    func testAServerOnCatalogVersion4GetsEverythingButRelease7Items() async throws {
        let token = FakeFriendsServer.token(9)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.catalogVersion4 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(9))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Juno", breed: .corgi, outfit: .rainSlicker,
                             accessories: [.daisyChain, .nightcap, .roundGlasses])

        _ = try await account.connect(profile: PartyPetAppearance.update(for: pet))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me"], "refused once, then sent without release 7's ids")
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertEqual(taken["accessories"] as? [String], ["glasses", "nightcap"])
        XCTAssertEqual(taken["costume"] as? String, "none")
    }

    /// A server on catalog version 3 refuses release 7's items and then the
    /// mastery outfits, so the profile steps down one catalog at a time.
    func testAServerOnCatalogVersion3StepsDownThroughVersion4() async throws {
        let token = FakeFriendsServer.token(10)
        let fake = FakeFriendsServer(validTokens: [token])
        fake.catalogVersion3 = true
        let store = InMemoryPartyCredentialStore([server: PartyCredentials(token: token, code: FakeFriendsServer.code(10))])
        let account = PartyAccount(server: server, transport: fake, credentials: store)
        let pet = PetProfile(name: "Juno", breed: .corgi, outfit: .sushiChef,
                             accessories: [.daisyChain, .nightcap, .roundGlasses])

        _ = try await account.connect(profile: PartyPetAppearance.update(for: pet))

        XCTAssertEqual(fake.requests, ["PATCH /v1/me", "PATCH /v1/me", "PATCH /v1/me"])
        let taken = try XCTUnwrap(fake.takenBodies.last)
        XCTAssertEqual(taken["accessories"] as? [String], ["glasses"])
        XCTAssertEqual(taken["costume"] as? String, "none")
    }

    func testARefusedNameOnRegisterStillRegisters() async throws {
        let fake = FakeFriendsServer()
        fake.heldNames = ["Rude"]
        let account = PartyAccount(server: server, transport: fake, credentials: InMemoryPartyCredentialStore())

        let profile = try await account.connect(profile: PartyProfileUpdate(name: "Rude"))

        XCTAssertEqual(profile.name, "Studier")
        XCTAssertEqual(fake.requests, ["POST /v1/register", "POST /v1/register"])
        XCTAssertEqual(fake.registerCount, 1)
        let refused = await account.refusedNames
        XCTAssertEqual(refused, .name)
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
