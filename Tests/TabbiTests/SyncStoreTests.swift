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
                           pet: ClosetStore, isAvailable: Bool = true) -> SyncStore {
        SyncStore(storage: storage, runMode: .live, pet: pet, isAvailable: isAvailable,
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

    func testABuildWithoutTheEntitlementIsUnavailableUntilSignedIn() {
        let store = makeStore(server: FakeAccountServer(), credentials: InMemoryPartyCredentialStore(),
                              pet: petStore(earned: 0), isAvailable: false)
        XCTAssertEqual(store.phase, .unavailable)
    }

    func testDemoShowsASignedInSampleAndTouchesNothing() async {
        let server = FakeAccountServer()
        let pet = ClosetStore(storage: storage, runMode: .demo)
        let store = SyncStore(storage: storage, runMode: .demo, pet: pet, isAvailable: false,
                              server: { [serverURL] in serverURL }, credentials: InMemoryPartyCredentialStore(),
                              transport: { _ in server })
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.name, "Sam Rivera")
        XCTAssertNotNil(store.lastSyncedAt)
        store.start()
        store.syncNow()
        await store.deleteAccount()
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testTheAppHasOneAccountThatSnapshotsShowAsUnavailable() {
        let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let demo = AppServices(settings: settings, moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertEqual(demo.accountSync.phase, .signedIn)
        XCTAssertEqual(demo.accountSync.name, "Sam Rivera")

        let snapshot = AppServices(settings: settings, moduleTypes: types, environment: [:],
                                   arguments: ["Tabbi", "--snapshot", "out"])
        XCTAssertEqual(snapshot.accountSync.phase, .unavailable, "a snapshot build cannot sign in")
        XCTAssertFalse(snapshot.accountSync === demo.accountSync, "each app has its own account")
    }

    /// Snapshots can render the signed-out row a release build shows, and
    /// only a snapshot run can.
    func testOnlySnapshotsCanShowTheSignInRowWithoutTheEntitlement() {
        let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let snapshot = AppServices(settings: settings, moduleTypes: types, environment: [:],
                                   arguments: ["Tabbi", "--snapshot", "out"])
        snapshot.accountSync.showsSignInForSnapshot(true)
        XCTAssertEqual(snapshot.accountSync.phase, .signedOut)
        snapshot.accountSync.showsSignInForSnapshot(false)
        XCTAssertEqual(snapshot.accountSync.phase, .unavailable)

        let live = makeStore(server: FakeAccountServer(), credentials: InMemoryPartyCredentialStore(),
                             pet: petStore(earned: 0), isAvailable: false)
        live.showsSignInForSnapshot(true)
        XCTAssertEqual(live.phase, .unavailable)
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
    var failDelete = false
    var accountGone = false

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
            case ("DELETE", "/v1/me"):
                if failDelete { return Self.reply(#"{"ok":false,"error":"server_error","message":"no"}"#, 500) }
                deleted = request.token
                return Self.reply(#"{"ok":true}"#)
            default:
                return Self.reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
            }
        }
    }

    private static func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}
