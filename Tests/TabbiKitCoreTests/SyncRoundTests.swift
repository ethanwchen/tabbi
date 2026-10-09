import XCTest
import TabbiKitCore

/// A sync server that behaves like `backend/` for the sign-in and sync
/// routes: it keeps one document with a revision, refuses stale pushes
/// with 409, and can let "another Mac" push right before a pull is served.
private final class FakeSyncServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var revision = 0
    private(set) var stored: Data?
    private(set) var requests: [PartyHTTPRequest] = []
    /// Run before serving each pull; returns a document another Mac pushes.
    var beforePull: ((Int) -> SyncDocument?)?
    var signInReply = #"{"ok":true,"token":"t-new","code":"K7QW2MZD","newAccount":false,"profile":{"code":"K7QW2MZD","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":10,"level":1}}"#
    private var pulls = 0

    var document: SyncDocument? { lock.withLock { stored }.flatMap { try? SyncDocument.decode($0) } }

    func seed(_ document: SyncDocument) {
        lock.withLock {
            stored = try? document.encoded()
            revision += 1
        }
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        lock.withLock { requests.append(request) }
        switch (request.method, request.path) {
        case ("POST", "/v1/auth/apple"):
            return Self.reply(signInReply)
        case ("GET", "/v1/sync"):
            let pull = lock.withLock { () -> Int in pulls += 1; return pulls }
            if let pushed = beforePull?(pull) { seed(pushed) }
            return lock.withLock {
                let document = stored.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
                let updatedAt = stored == nil ? "null" : "1791504000"
                return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":\#(updatedAt),"document":\#(document)}"#)
            }
        case ("PUT", "/v1/sync"):
            let match = Int(request.headers["If-Match"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "")
            return lock.withLock {
                guard match == revision else {
                    return Self.reply(#"{"ok":false,"error":"revision_conflict","message":"stale"}"#, status: 409)
                }
                let body = (try? JSONSerialization.jsonObject(with: request.body ?? Data())) as? [String: Any]
                stored = (body?["document"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                revision += 1
                return Self.reply(#"{"ok":true,"revision":\#(revision),"updatedAt":1791504060}"#)
            }
        default:
            return Self.reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, status: 404)
        }
    }

    private static func reply(_ text: String, status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

final class SyncClientTests: XCTestCase {
    func testSignInSendsTheAppleTokensWithTheCurrentPartyToken() async throws {
        let server = FakeSyncServer()
        let reply = try await SyncClient(transport: server, token: "t-old")
            .signInWithApple(identityToken: "jwt", authorizationCode: "code")
        XCTAssertEqual(reply.credentials, PartyCredentials(token: "t-new", code: "K7QW2MZD"))
        XCTAssertFalse(reply.newAccount)
        XCTAssertEqual(reply.profile.petName, "Mochi")
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(request.token, "t-old")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["identityToken": "jwt", "authorizationCode": "code"])
    }

    func testSignInWithoutTokenOrCodeSendsNeither() async throws {
        let server = FakeSyncServer()
        _ = try await SyncClient(transport: server).signInWithApple(identityToken: "jwt", authorizationCode: nil)
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertNil(request.token)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["identityToken": "jwt"])
    }

    func testPullBeforeAnyPushIsEmpty() async throws {
        let pull = try await SyncClient(transport: FakeSyncServer(), token: "t").pull()
        XCTAssertEqual(pull, SyncPull(revision: 0))
    }

    func testPushSendsTheRevisionAsIfMatchAndRoundTrips() async throws {
        let server = FakeSyncServer()
        let client = SyncClient(transport: server, token: "t")
        let document = SyncDocument(tallies: ["a": SyncTally(earned: 40)], unlocks: ["accessory.beanie"], studyDays: ["2026-10-07"])
        let revision = try await client.push(document, ifMatch: 0)
        XCTAssertEqual(revision, 1)
        XCTAssertEqual(server.requests.last?.headers["If-Match"], "\"0\"")
        let pull = try await client.pull()
        XCTAssertEqual(pull.revision, 1)
        XCTAssertEqual(pull.document, document)
        XCTAssertEqual(pull.updatedAt, Date(timeIntervalSince1970: 1_791_504_000))
    }

    func testSyncRoutesNeedAToken() async {
        do {
            _ = try await SyncClient(transport: FakeSyncServer()).pull()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? PartyError, .unauthorized)
        }
    }

    func testSyncErrorsAreRecognized() {
        XCTAssertTrue(PartyError.fromServer(code: "revision_conflict", status: 409, retryAfter: nil).isRevisionConflict)
        XCTAssertTrue(PartyError.fromServer(code: "no_account", status: 403, retryAfter: nil).isNoSyncAccount)
        XCTAssertTrue(PartyError.fromServer(code: "invalid_identity_token", status: 401, retryAfter: nil).isRejectedAppleSignIn)
        XCTAssertFalse(PartyError.unauthorized.isRevisionConflict)
        XCTAssertEqual(PartyError.fromServer(code: "apple_unavailable", status: 503, retryAfter: nil), .serverUnavailable)
    }
}

final class SyncRoundTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func save(earned: Int, spent: Int = 0, purchased: Set<PetItem> = [], name: String = "Mochi") -> PetSave {
        PetSave(
            profile: PetProfile(name: name, breed: .britishShorthair),
            ledger: PetPointsLedger(earned: earned, spent: spent, purchased: purchased)
        )
    }

    private func run(_ local: SyncLocalProgress, _ state: SyncState, _ server: FakeSyncServer) async throws -> SyncOutcome {
        try await SyncRound.run(local, state: state, client: SyncClient(transport: server, token: "t"), now: now)
    }

    func testFirstSyncPushesLocalProgress() async throws {
        let server = FakeSyncServer()
        let local = SyncLocalProgress(save: save(earned: 100, spent: 30, purchased: [.accessory(.beanie)]),
                                      lookChangedAt: now, studyDays: ["2026-10-06", "2026-10-07"])
        let outcome = try await run(local, SyncState(device: "a", account: "K7QW2MZD"), server)
        XCTAssertTrue(outcome.pushed)
        XCTAssertEqual(outcome.state.revision, 1)
        XCTAssertEqual(outcome.state.lastSyncedAt, now)
        XCTAssertEqual(server.document, outcome.document)
        XCTAssertEqual(outcome.document.tallies["a"], SyncTally(earned: 100, spent: 30))
        XCTAssertEqual(outcome.document.currentStreak(today: "2026-10-07"), 2)
        XCTAssertEqual(outcome.save.ledger, local.save.ledger)
        XCTAssertEqual(outcome.save.profile.name, "Mochi")
    }

    func testFirstSignInMergesIntoAnAccountWithProgress() async throws {
        let server = FakeSyncServer()
        server.seed(SyncDocument.empty.recording(save(earned: 50, name: "Tofu"), changedAt: now, device: "b"))
        // This Mac's pet was never renamed after the account's was chosen.
        let local = SyncLocalProgress(save: save(earned: 100, purchased: [.accessory(.beanie)]),
                                      lookChangedAt: now.addingTimeInterval(-3600))
        let outcome = try await run(local, SyncState(device: "a", account: "K7QW2MZD"), server)
        XCTAssertEqual(outcome.save.ledger.earned, 150, "points from both Macs add up")
        XCTAssertTrue(outcome.save.ledger.owns(.accessory(.beanie)))
        XCTAssertEqual(outcome.save.profile.name, "Tofu", "the newer look wins")
        XCTAssertEqual(server.document?.earned, 150)
    }

    func testUnknownLocalLookTimeLosesToTheAccountsLook() async throws {
        let server = FakeSyncServer()
        server.seed(SyncDocument.empty.recording(save(earned: 0, name: "Tofu"), changedAt: now, device: "b"))
        let outcome = try await run(SyncLocalProgress(save: save(earned: 5)), SyncState(device: "a"), server)
        XCTAssertEqual(outcome.save.profile.name, "Tofu")
    }

    func testNothingNewMeansNoPush() async throws {
        let server = FakeSyncServer()
        let first = try await run(SyncLocalProgress(save: save(earned: 20), lookChangedAt: now), SyncState(device: "a"), server)
        let second = try await run(SyncLocalProgress(save: first.save), first.state, server)
        XCTAssertFalse(second.pushed)
        XCTAssertEqual(second.state.revision, 1)
        XCTAssertEqual(server.requests.filter { $0.method == "PUT" }.count, 1)
    }

    func testFractionalLookTimeSettlesAfterOneRoundTrip() async throws {
        let server = FakeSyncServer()
        let changed = now.addingTimeInterval(0.75)
        let first = try await run(SyncLocalProgress(save: save(earned: 1, name: "Pip"), lookChangedAt: changed),
                                  SyncState(device: "a"), server)
        let second = try await run(SyncLocalProgress(save: first.save, lookChangedAt: changed), first.state, server)
        XCTAssertFalse(second.pushed)
    }

    func testConflictPullsMergesAndRetriesWithoutLosingEitherMac() async throws {
        let server = FakeSyncServer()
        let first = try await run(SyncLocalProgress(save: save(earned: 100), lookChangedAt: now), SyncState(device: "a"), server)
        // Mac B pushed before A's next pull, and Mac C pushes between that pull and A's push.
        server.beforePull = { pull in
            pull == 2 ? first.document.recording(self.save(earned: 125), changedAt: nil, device: "b") : nil
        }
        let racing = FakeRacingTransport(server: server, otherMac: first.document.recording(save(earned: 140), changedAt: nil, device: "c"))
        let outcome = try await SyncRound.run(SyncLocalProgress(save: save(earned: 110)), state: first.state,
                                              client: SyncClient(transport: racing, token: "t"), now: now)
        XCTAssertTrue(outcome.pushed)
        XCTAssertEqual(outcome.document.tallies["a"], SyncTally(earned: 110))
        XCTAssertEqual(outcome.document.tallies["b"], SyncTally(earned: 25))
        XCTAssertEqual(outcome.document.tallies["c"], SyncTally(earned: 40))
        XCTAssertEqual(outcome.save.ledger.earned, 175)
        XCTAssertEqual(server.document, outcome.document)
        XCTAssertEqual(racing.conflicts, 1)
    }

    func testGivesUpAfterRepeatedConflicts() async throws {
        let server = FakeSyncServer()
        let racing = FakeRacingTransport(server: server, otherMac: .empty, every: true)
        do {
            _ = try await SyncRound.run(SyncLocalProgress(save: save(earned: 10)), state: SyncState(device: "a"),
                                        client: SyncClient(transport: racing, token: "t"), now: now)
            XCTFail("expected a conflict")
        } catch let error as PartyError {
            XCTAssertTrue(error.isRevisionConflict)
        }
        XCTAssertEqual(racing.conflicts, SyncRound.maxAttempts)
    }

    func testLaterRoundsCountOnlyWhatThisMacAdded() async throws {
        let server = FakeSyncServer()
        let a = try await run(SyncLocalProgress(save: save(earned: 100), lookChangedAt: now), SyncState(device: "a"), server)
        let b = try await run(SyncLocalProgress(save: save(earned: 50)), SyncState(device: "b"), server)
        XCTAssertEqual(b.save.ledger.earned, 150)
        // A earns 10 more, then syncs: B's 50 arrive and A's tally is 110.
        var next = a.save
        next.ledger = PetPointsLedger(earned: 110, spent: 0, purchased: [])
        let again = try await run(SyncLocalProgress(save: next), a.state, server)
        XCTAssertEqual(again.save.ledger.earned, 160)
        XCTAssertEqual(again.document.tallies, ["a": SyncTally(earned: 110), "b": SyncTally(earned: 50)])
    }
}

/// Lets another Mac push between this Mac's pull and push, so the push
/// meets a 409 (once, or on every attempt).
private final class FakeRacingTransport: PartyTransport, @unchecked Sendable {
    let server: FakeSyncServer
    let otherMac: SyncDocument
    let every: Bool
    private let lock = NSLock()
    private var raced = 0
    var conflicts: Int { lock.withLock { raced } }

    init(server: FakeSyncServer, otherMac: SyncDocument, every: Bool = false) {
        self.server = server
        self.otherMac = otherMac
        self.every = every
    }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        if request.method == "PUT", every || conflicts == 0 {
            lock.withLock { raced += 1 }
            let current = server.document ?? .empty
            server.seed(current.merged(with: otherMac))
        }
        return try await server.send(request, timeout: timeout)
    }
}

final class SyncStateTests: XCTestCase {
    func testRoundTripsWithItsSchemaVersion() throws {
        let state = SyncState(device: "a", account: "K7QW2MZD",
                              adopted: SyncDocument(tallies: ["a": SyncTally(earned: 3)]), revision: 4,
                              lastSyncedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try state.encoded()
        XCTAssertEqual(VersionedJSON.version(of: data), SyncState.schema.current)
        XCTAssertEqual(try SyncState.decode(data), state)
    }

    func testSigningInToAnotherAccountStartsOverButKeepsTheDevice() {
        let state = SyncState(device: "a", account: "K7QW2MZD", adopted: SyncDocument(unlocks: ["x"]), revision: 4)
        XCTAssertEqual(state.signedIn(to: "K7QW2MZD"), state)
        XCTAssertEqual(state.signedIn(to: "B3NX9QRT"), SyncState(device: "a", account: "B3NX9QRT"))
    }

    func testSigningOutKeepsWhatWasSyncedAndSigningBackInGoesOn() throws {
        let session = SyncSession(name: "  Ana  ", signedInAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(session.name, "Ana")
        XCTAssertNil(SyncSession(name: " ", signedInAt: .distantPast).name)
        let synced = SyncState(device: "a", account: "K7QW2MZD", adopted: SyncDocument(unlocks: ["x"]), revision: 4)
            .signedIn(to: "K7QW2MZD", session: session)
        XCTAssertTrue(synced.isSignedIn)
        XCTAssertEqual(try SyncState.decode(synced.encoded()), synced)

        let out = synced.signedOut()
        XCTAssertFalse(out.isSignedIn)
        XCTAssertEqual(out.adopted, synced.adopted)
        XCTAssertEqual(out.revision, 4)
        XCTAssertEqual(out.signedIn(to: "K7QW2MZD", session: session), synced)
    }

    func testForgettingADeletedAccountKeepsOnlyTheDevice() {
        let state = SyncState(device: "a", account: "K7QW2MZD", adopted: SyncDocument(unlocks: ["x"]), revision: 4,
                              session: SyncSession(signedInAt: .distantPast))
        XCTAssertEqual(state.forgettingAccount(), SyncState(device: "a"))
    }

    /// A state saved before sign-in sessions were kept reads as signed out.
    func testAStateWithoutASessionReadsAsSignedOut() throws {
        let data = Data(#"{"schemaVersion":1,"device":"a","adopted":{"tallies":{},"unlocks":[],"studyDays":[],"longestStreak":0},"revision":0}"#.utf8)
        XCTAssertFalse(try SyncState.decode(data).isSignedIn)
    }
}

final class SyncOutcomeFoldingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Points earned while a round was in flight are kept on top of what
    /// the round pulled from another Mac, and the next round pushes them.
    func testAChangeDuringARoundIsFoldedOnTopOfIt() async throws {
        let server = FakeSyncServer()
        server.seed(SyncDocument(tallies: ["b": SyncTally(earned: 50)]))
        let base = SyncState(device: "a")
        let profile = PetProfile(name: "Mochi", breed: .britishShorthair)
        let sent = PetSave(profile: profile, ledger: PetPointsLedger(earned: 10))
        let client = SyncClient(transport: server, token: "t")
        let outcome = try await SyncRound.run(SyncLocalProgress(save: sent, lookChangedAt: now), state: base,
                                              client: client, now: now)
        XCTAssertEqual(outcome.save.ledger.earned, 60)

        var current = sent
        current.ledger = PetPointsLedger(earned: 15)
        let folded = outcome.folding(SyncLocalProgress(save: current, lookChangedAt: now, studyDays: ["2026-10-08"]),
                                     base: base)
        XCTAssertFalse(folded.pushed)
        XCTAssertEqual(folded.save.ledger.earned, 65, "the other Mac's 50 plus this Mac's 15")
        XCTAssertEqual(folded.state.revision, outcome.state.revision)
        XCTAssertTrue(folded.document.studyDays.contains("2026-10-08"))

        let next = try await SyncRound.run(SyncLocalProgress(save: folded.save), state: folded.state,
                                           client: client, now: now)
        XCTAssertTrue(next.pushed)
        XCTAssertEqual(server.document?.earned, 65)
        XCTAssertEqual(next.save.ledger.earned, 65)
    }
}
