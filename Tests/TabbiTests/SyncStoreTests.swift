import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The account flow end to end against a fake friends server: signing in
/// links the Party identity and merges the pet with the account's, changes
/// sync, and signing out or deleting keeps the pet on this Mac.
@MainActor
final class SyncStoreTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
    private let serverURL = URL(string: "https://party.example.test")!
    private var storage: EditionStorage { EditionStorage(root: folder) }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore(server: FakeAccountServer, credentials: InMemoryPartyCredentialStore,
                           pet: ClosetStore, method: AppleSignInMethod = .native,
                           webPage: @escaping @MainActor (URL) async throws -> URL? = { _ in nil }) -> SyncStore {
        SyncStore(storage: storage, runMode: .live, pet: pet, signInMethod: method, webCallback: webPage,
                  server: { [serverURL] in serverURL }, credentials: credentials,
                  transport: { _ in server }, studyDays: { ["2026-10-08"] })
    }

    private func petStore(earned: Int) -> ClosetStore {
        let store = ClosetStore(storage: storage, runMode: .live, starter: .starter(.cat))
        store.adoptSynced(PetSave(profile: .starter(.cat), ledger: PetPointsLedger(earned: earned)))
        return store
    }

    private func waitUntilSynced(_ store: SyncStore) async {
        for _ in 0..<200 where store.isSyncing || store.lastSyncedAt == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        for _ in 0..<200 where store.isSyncing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testSigningInLinksThePartyIdentityAndMergesWithTheAccount() async throws {
        let server = FakeAccountServer()
        server.document = SyncDocument(tallies: ["other-mac": SyncTally(earned: 50)])
        let credentials = InMemoryPartyCredentialStore([serverURL: PartyCredentials(token: "t-anon", code: "ANON1234")])
        let pet = petStore(earned: 20)
        let store = makeStore(server: server, credentials: credentials, pet: pet)
        var identityChanges = 0
        let watch = store.identityChanged.sink { identityChanges += 1 }
        defer { watch.cancel() }
        XCTAssertEqual(store.phase, .signedOut)

        await store.signIn(identityToken: "jwt", authorizationCode: "code", name: "Ana")
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.name, "Ana")
        XCTAssertEqual(server.signInBearer, "t-anon", "the anonymous Party user is linked")
        XCTAssertEqual(credentials.load(for: serverURL), PartyCredentials(token: "t-acct", code: "K7QW2MZD"))
        XCTAssertEqual(identityChanges, 1)

        await waitUntilSynced(store)
        XCTAssertEqual(pet.closet.save.ledger.earned, 70, "this Mac's 20 plus the account's 50")
        XCTAssertEqual(server.document?.earned, 70)
        XCTAssertEqual(server.document?.studyDays, ["2026-10-08"])
        XCTAssertNotNil(store.lastSyncedAt)

        // A relaunch remembers the account.
        let relaunched = makeStore(server: server, credentials: credentials, pet: pet)
        XCTAssertEqual(relaunched.phase, .signedIn)
        XCTAssertEqual(relaunched.name, "Ana")
    }

    /// An event item the maintainer granted the account (the launch week
    /// cap) reaches a signed-in Mac through sync, with Party off, once per
    /// launch rather than on every round.
    func testSyncHandsTheAccountsGrantsToThePetOnce() async throws {
        let server = FakeAccountServer()
        let cap = PetLimitedEdition.launchWeekCap.item
        server.grantedItems = [cap.id, "accessory.fromANewerBuild"]
        let pet = petStore(earned: 0)
        let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: pet)
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await waitUntilSynced(store)

        XCTAssertEqual(pet.closet.save.ledger.granted, [cap])
        XCTAssertEqual(pet.closet.save.ledger.spent, 0, "a grant costs no points")
        XCTAssertEqual(server.grantsFetchedWith, ["t-acct"])

        let before = server.requestCount
        pet.rename("Mochi")
        store.syncNow()
        for _ in 0..<200 where server.requestCount == before || store.isSyncing {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(server.requestCount, before, "another round ran")
        XCTAssertEqual(server.grantsFetchedWith.count, 1, "later rounds don't ask again")
    }

    func testSigningOutKeepsThePetAndDropsTheAccountIdentity() async throws {
        let server = FakeAccountServer()
        let credentials = InMemoryPartyCredentialStore()
        let pet = petStore(earned: 20)
        let store = makeStore(server: server, credentials: credentials, pet: pet)
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await waitUntilSynced(store)
        XCTAssertNil(store.name)

        store.signOut()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.lastSyncedAt)
        XCTAssertNil(credentials.load(for: serverURL), "Party starts an identity of its own")
        XCTAssertEqual(pet.closet.save.ledger.earned, 20)
        XCTAssertEqual(makeStore(server: server, credentials: credentials, pet: pet).phase, .signedOut)
        for _ in 0..<200 where server.signedOutWith == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(server.signedOutWith, "t-acct", "the server retires this Mac's token")
    }

    func testDeletingTheAccountDeletesItOnTheServerAndKeepsThePet() async throws {
        let server = FakeAccountServer()
        let credentials = InMemoryPartyCredentialStore()
        let pet = petStore(earned: 20)
        let store = makeStore(server: server, credentials: credentials, pet: pet)
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: "Ana")
        await waitUntilSynced(store)

        await store.deleteAccount()
        XCTAssertEqual(server.deletedWith, "t-acct")
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(credentials.load(for: serverURL))
        XCTAssertEqual(pet.closet.save.ledger.earned, 20)
    }

    func testAFailedDeleteStaysSignedInAndSaysWhy() async throws {
        let server = FakeAccountServer()
        let credentials = InMemoryPartyCredentialStore()
        let store = makeStore(server: server, credentials: credentials, pet: petStore(earned: 0))
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await waitUntilSynced(store)
        server.failDelete = true

        await store.deleteAccount()
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertNotNil(store.notice)
        XCTAssertNotNil(credentials.load(for: serverURL))
    }

    func testARefusedSignInStaysSignedOutWithANotice() async {
        let server = FakeAccountServer()
        server.refuseSignIn = true
        let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: petStore(earned: 0))
        await store.signIn(identityToken: "bad", authorizationCode: nil, name: nil)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.notice, "Apple didn't accept the sign-in. Try again.")
    }

    /// Another Mac deleted the account: this Mac signs out on its next sync.
    func testAnAccountDeletedElsewhereSignsThisMacOut() async throws {
        let server = FakeAccountServer()
        let credentials = InMemoryPartyCredentialStore()
        let store = makeStore(server: server, credentials: credentials, pet: petStore(earned: 5))
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await waitUntilSynced(store)
        server.accountGone = true

        store.syncNow()
        for _ in 0..<200 where store.phase != .signedOut {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(credentials.load(for: serverURL))
    }

    // MARK: Web sign-in

    /// Apple's page as the friends server finishes it: checks the authorize
    /// link, has the server issue a one-time code for the attempt's state,
    /// and ends on `tabbi://auth/apple?code=...`.
    private func webPage(_ server: FakeAccountServer, opened: @escaping (URLComponents) -> Void = { _ in })
        -> @MainActor (URL) async throws -> URL? {
        { url in
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            opened(components)
            let state = try XCTUnwrap(components.queryItems?.first { $0.name == "state" }?.value)
            return URL(string: "tabbi://auth/apple?code=\(server.issueWebCode(for: state))")
        }
    }

    func testSigningInOnTheWebTradesTheCodeWithItsStateAndSyncs() async throws {
        let server = FakeAccountServer()
        server.document = SyncDocument(tallies: ["other-mac": SyncTally(earned: 50)])
        let credentials = InMemoryPartyCredentialStore([serverURL: PartyCredentials(token: "t-anon", code: "ANON1234")])
        let pet = petStore(earned: 20)
        var opened: URLComponents?
        let store = makeStore(server: server, credentials: credentials, pet: pet, method: .web,
                              webPage: webPage(server) { opened = $0 })
        var identityChanges = 0
        let watch = store.identityChanged.sink { identityChanges += 1 }
        defer { watch.cancel() }

        await store.signInOnWeb()
        XCTAssertEqual(opened?.host, "appleid.apple.com")
        XCTAssertEqual(opened?.queryItems?.first { $0.name == "redirect_uri" }?.value,
                       "https://party.example.test/v1/auth/apple/web/callback",
                       "Apple posts to the server this Mac uses")
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertNil(store.notice)
        XCTAssertNil(store.name, "the web flow shares no name")
        XCTAssertEqual(server.signInBearer, "t-anon", "the anonymous Party user is linked")
        XCTAssertEqual(credentials.load(for: serverURL), PartyCredentials(token: "t-acct", code: "K7QW2MZD"))
        XCTAssertEqual(identityChanges, 1)

        await waitUntilSynced(store)
        XCTAssertEqual(pet.closet.save.ledger.earned, 70, "this Mac's 20 plus the account's 50")
    }

    func testEachWebSignInUsesAFreshState() async throws {
        let server = FakeAccountServer()
        var states: [String] = []
        let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: petStore(earned: 0),
                              method: .web, webPage: { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            states.append(components?.queryItems?.first { $0.name == "state" }?.value ?? "")
            return nil
        })
        await store.signInOnWeb()
        await store.signInOnWeb()
        XCTAssertEqual(states.count, 2)
        XCTAssertNotEqual(states[0], states[1])
    }

    func testClosingApplesPageIsNotAnError() async {
        let server = FakeAccountServer()
        let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: petStore(earned: 0),
                              method: .web, webPage: { _ in nil })
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.notice)
        XCTAssertEqual(server.requestCount, 0)
    }

    func testAWebSignInTheServerTurnedDownSaysWhy() async {
        for (link, notice) in [
            ("tabbi://auth/apple?error=cancelled", nil),
            ("tabbi://auth/apple?error=invalid_state", AppleWebSignIn.Failure.rejected.message),
            ("tabbi://auth/apple?error=apple_unavailable", AppleWebSignIn.Failure.unavailable.message),
            ("tabbi://auth/apple?code=not-a-code", "Couldn't sign in with Apple. Try again."),
        ] {
            let server = FakeAccountServer()
            let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: petStore(earned: 0),
                                  method: .web, webPage: { _ in URL(string: link) })
            await store.signInOnWeb()
            XCTAssertEqual(store.phase, .signedOut, link)
            XCTAssertEqual(store.notice, notice, link)
            XCTAssertEqual(server.requestCount, 0, link)
        }
    }

    func testAFailingWebPageSaysSo() async {
        let store = makeStore(server: FakeAccountServer(), credentials: InMemoryPartyCredentialStore(),
                              pet: petStore(earned: 0), method: .web, webPage: { _ in throw URLError(.notConnectedToInternet) })
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.notice, "Couldn't sign in with Apple. Try again.")
    }

    /// The code is bound to the state of the attempt that made it, and to
    /// one use.
    func testAWebCodeOnlyWorksOnceAndWithItsOwnState() async throws {
        let server = FakeAccountServer()
        let stolen = server.issueWebCode(for: "someone-elses-state")
        let store = makeStore(server: server, credentials: InMemoryPartyCredentialStore(), pet: petStore(earned: 0),
                              method: .web, webPage: { _ in URL(string: "tabbi://auth/apple?code=\(stolen)") })
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.notice, "The sign-in took too long. Try again.")
    }

    func testWebSignInDoesNothingWithoutAServer() async {
        var opened = false
        let store = SyncStore(storage: storage, runMode: .live, pet: petStore(earned: 0), signInMethod: .web,
                              webCallback: { _ in opened = true; return nil },
                              server: { nil }, credentials: InMemoryPartyCredentialStore())
        await store.signInOnWeb()
        XCTAssertFalse(opened)
        XCTAssertEqual(store.phase, .signedOut)
    }

    func testDemoShowsASignedInSampleAndTouchesNothing() async {
        let server = FakeAccountServer()
        let pet = ClosetStore(storage: storage, runMode: .demo)
        let store = SyncStore(storage: storage, runMode: .demo, pet: pet, signInMethod: .web,
                              webCallback: { _ in XCTFail("demo opens no page"); return nil },
                              server: { [serverURL] in serverURL }, credentials: InMemoryPartyCredentialStore(),
                              transport: { _ in server })
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.name, "Sam Rivera")
        XCTAssertNotNil(store.lastSyncedAt)
        store.start()
        store.syncNow()
        await store.deleteAccount()
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testTheAppHasOneAccountThatSnapshotsShowSignedOut() {
        let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let demo = AppServices(settings: settings, moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertEqual(demo.accountSync.phase, .signedIn)
        XCTAssertEqual(demo.accountSync.name, "Sam Rivera")

        let snapshot = AppServices(settings: settings, moduleTypes: types, environment: [:],
                                   arguments: ["Tabbi", "--snapshot", "out"])
        XCTAssertEqual(snapshot.accountSync.phase, .signedOut, "snapshots show the Sign in with Apple button")
        XCTAssertFalse(snapshot.accountSync === demo.accountSync, "each app has its own account")
    }

    func testAFailedAppleSheetSaysSoAndStaysSignedOut() {
        let store = makeStore(server: FakeAccountServer(), credentials: InMemoryPartyCredentialStore(),
                              pet: petStore(earned: 0))
        store.appleSignInFailed()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.notice, "Couldn't sign in with Apple. Try again.")
    }

    func testTheAccountRowSaysWhenItLastSynced() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AccountSettingsRow.relative(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertTrue(AccountSettingsRow.relative(now.addingTimeInterval(-4 * 60), now: now).contains("4"))
        XCTAssertTrue(AccountSettingsRow.deleteMessage.contains("friend code"),
                      "the confirmation says what is deleted")
    }
}

/// The friends server's account routes: sign-in, sync and delete.
private final class FakeAccountServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var revision = 0
    private var stored: SyncDocument?
    private var requests = 0
    private var bearer: String?
    private var deleted: String?
    private var signedOut: String?
    var refuseSignIn = false
    /// One-time web sign-in codes and the state each is bound to.
    private var webCodes: [String: String] = [:]
    var failDelete = false
    var accountGone = false
    /// The limited edition item ids `GET /v1/grants` returns.
    var grantedItems: [String] = []
    private var grantFetches: [String?] = []
    /// The bearer token of each `GET /v1/grants`.
    var grantsFetchedWith: [String?] { lock.withLock { grantFetches } }

    var document: SyncDocument? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue; revision += 1 } }
    }
    var signInBearer: String? { lock.withLock { bearer } }
    var deletedWith: String? { lock.withLock { deleted } }
    var signedOutWith: String? { lock.withLock { signedOut } }
    var requestCount: Int { lock.withLock { requests } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock {
            requests += 1
            switch (request.method, request.path) {
            case ("POST", "/v1/auth/apple"):
                if refuseSignIn { return Self.reply(#"{"ok":false,"error":"invalid_identity_token","message":"no"}"#, 401) }
                bearer = request.token
                return Self.reply(#"{"ok":true,"token":"t-acct","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}}"#)
            case ("POST", "/v1/auth/apple/web/token"):
                let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: String]
                guard let code = body?["code"], let state = webCodes.removeValue(forKey: code),
                      state == body?["state"] else {
                    return Self.reply(#"{"ok":false,"error":"invalid_code","message":"no"}"#, 401)
                }
                bearer = request.token
                return Self.reply(#"{"ok":true,"token":"t-acct","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}}"#)
            case ("GET", "/v1/sync"):
                if accountGone { return Self.reply(#"{"ok":false,"error":"no_account","message":"no"}"#, 403) }
                let document = stored.flatMap { try? $0.encoded() }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
                return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":null,"document":\#(document)}"#)
            case ("PUT", "/v1/sync"):
                let match = Int(request.headers["If-Match"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "")
                guard match == revision else { return Self.reply(#"{"ok":false,"error":"revision_conflict","message":"stale"}"#, 409) }
                let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
                stored = (body?["document"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    .flatMap { try? SyncDocument.decode($0) }
                revision += 1
                return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":1791504060}"#)
            case ("POST", "/v1/auth/signout"):
                signedOut = request.token
                return Self.reply(#"{"ok":true}"#)
            case ("GET", "/v1/grants"):
                grantFetches.append(request.token)
                let items = grantedItems.map { "\"\($0)\"" }.joined(separator: ",")
                return Self.reply(#"{"ok":true,"items":[\#(items)]}"#)
            case ("DELETE", "/v1/me"):
                if failDelete { return Self.reply(#"{"ok":false,"error":"server_error","message":"no"}"#, 500) }
                deleted = request.token
                return Self.reply(#"{"ok":true}"#)
            default:
                return Self.reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
            }
        }
    }

    /// What the callback does after Apple's post checks out: a one-time code
    /// bound to `state`.
    func issueWebCode(for state: String) -> String {
        let code = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }
            .joined().lowercased().prefix(64)
        lock.withLock { webCodes[String(code)] = state }
        return String(code)
    }

    private static func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}
