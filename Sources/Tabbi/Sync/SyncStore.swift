import AppKit
import Combine
import Foundation
import TabbiKitCore

/// The optional Sign in with Apple account: it signs in through the friends
/// server, keeps the pet save in sync across the user's Macs, and signs out
/// or deletes the account.
///
/// The account is the Party identity: signing in swaps the stored Party
/// credentials for the account's (so the same friend code and friends follow
/// the user to every Mac) and `identityChanged` tells Party to reconnect.
/// Each sync is a `SyncRound` over the shared pet (`ClosetStore`): on launch
/// and wake, a few seconds after the save changes, and once more on quit.
/// Everything works signed out exactly as without an account.
///
/// With `TABBI_DEMO=1` it shows a signed-in sample and never touches the
/// network, the Keychain or the disk; a snapshot run reads and writes
/// nothing either.
@MainActor
final class SyncStore: ObservableObject {
    /// What the Settings account row shows.
    enum Phase: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case deleting
    }

    @Published private(set) var phase: Phase
    /// The name Apple shared on the first sign-in on this Mac, if any.
    @Published private(set) var name: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isSyncing = false
    /// The last failure, in a sentence for the account row; nil when fine.
    @Published private(set) var notice: String?
    /// The age check (`PartyAgeCheck`): accounts are for people 13 and
    /// older, so signing in waits until it passed.
    @Published private(set) var ageStatus: PartyAgeCheck.Status

    /// Sent after the stored Party credentials changed (sign in, sign out,
    /// delete), so Party reconnects with the new identity.
    let identityChanged = PassthroughSubject<Void, Never>()
    /// Sent with `eligibleFrom` when the age question was answered before
    /// signing in, so Party adopts the same answer.
    let ageAnswered = PassthroughSubject<Date, Never>()

    /// How long the save stays quiet before a change is pushed.
    static let debounce: TimeInterval = 5
    /// How long a sync waits after wake, so Wi-Fi is back before it runs
    /// instead of failing with a notice right away.
    static let wakeDelay: TimeInterval = 10
    /// How long quitting waits for the last push.
    static let quitWait: TimeInterval = 2

    let isDemo: Bool
    /// Native sheet or Apple's web page; the row looks the same either way.
    let signInMethod: AppleSignInMethod
    private let webCallback: @MainActor (URL) async throws -> URL?
    private let pet: ClosetStore
    private let stateURL: URL?
    private let credentials: any PartyCredentialStore
    private let server: () -> URL?
    private let ageAnswer: AccountAgeAnswer
    private let transport: (URL) -> any PartyTransport
    private let studyDays: () -> Set<String>
    private let clock: () -> Date
    /// Waits out the debounce and the wake delay; tests release it by hand.
    private let sleep: (TimeInterval) async -> Void
    /// Set when the state on disk could not be read: sync stays off and the
    /// file is never overwritten, so no points are counted twice.
    private let stateIsUnreadable: Bool
    private var state: SyncState
    /// The save the last sync left, so adopting it does not sync again.
    private var syncedSave: PetSave?
    private var syncAgain = false
    private var syncTask: Task<Void, Never>?
    /// Counts started sync tasks, so a cancelled one that finishes late
    /// leaves the newer one's bookkeeping alone.
    private var syncGeneration = 0
    private var debounceTask: Task<Void, Never>?
    /// True once this launch (or wake, or sign-in) fetched the account's
    /// limited edition grants, so later rounds don't ask again.
    private var grantsAreCurrent = false
    private var cancellables: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - signInMethod: how this build signs in (`AppleSignInMethod.current`).
    ///   - webCallback: opens Apple's page for a web sign-in and returns the
    ///     `tabbi://auth/apple` link it ended on, or nil when the user
    ///     closed it (`AppleWebAuthentication`; tests fake it).
    ///   - server: the friends server Party uses now.
    ///   - credentials: where Party keeps its identity; the account replaces it.
    ///   - ageAnswer: where the age check's answer is kept, shared with Party.
    ///   - transport: replaces HTTPS (tests).
    ///   - studyDays: local days with focus time on this Mac, for the streak.
    ///   - sleep: waits before a debounced or post-wake sync (tests).
    init(storage: EditionStorage, runMode: RunMode, pet: ClosetStore, signInMethod: AppleSignInMethod,
         webCallback: @escaping @MainActor (URL) async throws -> URL? = { url in
             try await AppleWebAuthentication().callback(from: url)
         },
         server: @escaping () -> URL?, credentials: any PartyCredentialStore, ageAnswer: AccountAgeAnswer,
         transport: ((URL) -> any PartyTransport)? = nil,
         studyDays: @escaping () -> Set<String> = { [] }, clock: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        isDemo = runMode.isDemo
        self.signInMethod = signInMethod
        self.webCallback = webCallback
        self.pet = pet
        self.server = server
        self.credentials = credentials
        self.ageAnswer = ageAnswer
        self.transport = transport ?? { URLSessionPartyTransport(baseURL: $0) }
        self.studyDays = studyDays
        self.clock = clock
        self.sleep = sleep
        if isDemo {
            stateURL = nil
            stateIsUnreadable = false
            state = SyncState(device: "demo", account: "K7QW2MZD",
                              session: SyncSession(name: "Sam Rivera", signedInAt: clock()))
            phase = .signedIn
            name = "Sam Rivera"
            lastSyncedAt = clock().addingTimeInterval(-4 * 60)
            ageStatus = .passed
            return
        }
        let url = runMode.isSnapshot ? nil : storage.file("state.json", in: "Sync")
        var unreadable = false
        var loaded = SyncState()
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do {
                loaded = try SyncState.decode(Data(contentsOf: url))
            } catch {
                unreadable = true
            }
        }
        stateURL = url
        stateIsUnreadable = unreadable
        state = loaded
        phase = loaded.isSignedIn ? .signedIn : .signedOut
        name = loaded.session?.name
        lastSyncedAt = loaded.lastSyncedAt
        ageStatus = PartyAgeCheck.status(eligibleFrom: ageAnswer.load(), at: clock())
    }

    var isSignedIn: Bool { state.isSignedIn }

    // MARK: Lifecycle

    /// Syncs now and from then on after pet changes and on wake.
    func start() {
        guard !isDemo, cancellables.isEmpty else { return }
        pet.saves
            .dropFirst()
            .sink { [weak self] save in self?.saveDidChange(save) }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.grantsAreCurrent = false
                    self?.syncSoon(after: Self.wakeDelay)
                }
            }
            .store(in: &cancellables)
        syncNow()
    }

    /// Pushes a change not yet synced, waiting up to `quitWait`, because
    /// an async task left running at quit would never leave the Mac. The
    /// result is not adopted; the next launch merges it again, which the
    /// merge makes harmless.
    func flushOnQuit() {
        debounceTask?.cancel()
        guard !isDemo, state.isSignedIn, !stateIsUnreadable, pet.closet.save != syncedSave,
              let client = client() else { return }
        let local = progress()
        let state = state
        let now = clock()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            _ = try? await SyncRound.run(local, state: state, client: client, now: now)
            done.signal()
        }
        _ = done.wait(timeout: .now() + Self.quitWait)
    }

    // MARK: Age check

    /// Reads the answer again, since Party may have taken it meanwhile or
    /// the day the user turns 13 may have come.
    func refreshAgeStatus() {
        guard !isDemo else { return }
        ageStatus = PartyAgeCheck.status(eligibleFrom: ageAnswer.load(), at: clock())
    }

    /// The age question asked before Sign in with Apple, once, as Party
    /// asks it: only the day the user is surely 13 is saved, on this Mac,
    /// and nothing is sent. Under 13, signing in stays off until that day.
    func answerAge(birthMonth month: Int, year: Int) {
        refreshAgeStatus()
        guard !isDemo, ageStatus == .unanswered,
              let eligibleFrom = PartyAgeCheck.eligibleFrom(birthMonth: month, year: year) else { return }
        ageAnswer.save(eligibleFrom)
        ageStatus = PartyAgeCheck.status(eligibleFrom: eligibleFrom, at: clock())
        ageAnswered.send(eligibleFrom)
    }

    // MARK: Account

    /// Signs in with what `ASAuthorizationAppleIDCredential` returned:
    /// links (or adopts) the account, stores its Party identity and syncs,
    /// merging this Mac's progress with the account's.
    func signIn(identityToken: String, authorizationCode: String?, name: String?) async {
        await signIn(name: name) { client in
            try await client.signInWithApple(identityToken: identityToken, authorizationCode: authorizationCode)
        }
    }

    /// Signs in on Apple's web page (`AppleWebSignIn`): opens it, takes the
    /// one-time code the friends server sends back through
    /// `tabbi://auth/apple`, and trades it, with this attempt's state, for
    /// the account, as `signIn(identityToken:authorizationCode:name:)` does.
    /// Closing the page is not an error.
    func signInOnWeb() async {
        refreshAgeStatus()
        guard !isDemo, phase == .signedOut, ageStatus == .passed, let server = server() else { return }
        notice = nil
        phase = .signingIn
        let attempt = AppleWebSignIn()
        let link: URL?
        do {
            link = try await webCallback(attempt.authorizeURL(server: server))
        } catch {
            phase = .signedOut
            appleSignInFailed()
            return
        }
        guard let link else {
            phase = .signedOut
            return
        }
        switch AppleWebSignIn.Callback(url: link) {
        case .code(let code):
            phase = .signedOut
            await signIn(name: nil) { client in
                try await client.exchangeWebSignIn(code: code, state: attempt.state)
            }
        case .failure(let failure):
            phase = .signedOut
            notice = failure.message
        case nil:
            phase = .signedOut
            appleSignInFailed()
        }
    }

    /// Trades what Apple returned for the account through `exchange`, then
    /// stores its Party identity and syncs.
    private func signIn(name: String?, exchange: (SyncClient) async throws -> AppleSignInReply) async {
        refreshAgeStatus()
        guard !isDemo, phase == .signedOut, ageStatus == .passed, let server = server() else { return }
        notice = nil
        phase = .signingIn
        do {
            let client = SyncClient(transport: transport(server), token: credentials.load(for: server)?.token)
            let reply = try await exchange(client)
            try credentials.save(reply.credentials, for: server)
            state = state.signedIn(to: reply.credentials.code,
                                   session: SyncSession(name: name ?? self.name, signedInAt: clock()))
            persist()
            self.name = state.session?.name
            lastSyncedAt = state.lastSyncedAt
            phase = .signedIn
            grantsAreCurrent = false
            identityChanged.send()
            syncNow()
        } catch {
            phase = .signedOut
            notice = Self.message(for: error, signingIn: true)
        }
    }

    /// Apple's sheet failed before anything reached the server.
    func appleSignInFailed() {
        guard !isDemo else { return }
        notice = "Couldn't sign in with Apple. Try again."
    }

    /// Signs out: this Mac keeps its pet and progress, and Party goes back
    /// to an identity of its own. The server is asked to retire this Mac's
    /// token too, so nothing left behind can still act as the account; that
    /// is best effort, and signing out works offline all the same.
    func signOut() {
        guard !isDemo, state.isSignedIn else { return }
        cancelSync()
        if let server = server() {
            if let token = credentials.load(for: server)?.token {
                let client = SyncClient(transport: transport(server), token: token)
                Task { try? await client.signOut() }
            }
            try? credentials.delete(for: server)
        }
        state = state.signedOut()
        persist()
        settleSignedOut()
    }

    /// Deletes the account on the server (the user, the sync document,
    /// presence, friendships, party memberships and Apple's tokens) and the
    /// Party identity here. The pet stays on this Mac.
    func deleteAccount() async {
        guard !isDemo, state.isSignedIn, phase == .signedIn else { return }
        notice = nil
        phase = .deleting
        cancelSync()
        do {
            if let server = server(), let token = credentials.load(for: server)?.token {
                do {
                    try await PartyClient(transport: transport(server), token: token).deleteMe()
                } catch PartyError.unauthorized {
                    // Already gone on the server.
                }
                try? credentials.delete(for: server)
            }
            state = state.forgettingAccount()
            persist()
            settleSignedOut()
        } catch {
            phase = .signedIn
            notice = Self.message(for: error, signingIn: false)
        }
    }

    // MARK: Syncing

    /// Syncs now, or right after the round already running.
    func syncNow() {
        debounceTask?.cancel()
        guard !isDemo, state.isSignedIn, !stateIsUnreadable, client() != nil else { return }
        guard syncTask == nil else {
            syncAgain = true
            return
        }
        syncGeneration += 1
        let generation = syncGeneration
        syncTask = Task { [weak self] in
            await self?.runRounds(generation: generation)
        }
    }

    private func saveDidChange(_ save: PetSave) {
        guard state.isSignedIn, save != syncedSave else { return }
        syncSoon(after: Self.debounce)
    }

    /// Syncs once `delay` passes, unless another change or sync comes first.
    private func syncSoon(after delay: TimeInterval) {
        guard state.isSignedIn else { return }
        debounceTask?.cancel()
        let sleep = sleep
        debounceTask = Task { [weak self] in
            await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    private func runRounds(generation: Int) async {
        isSyncing = true
        repeat {
            syncAgain = false
            await runRound()
        } while syncAgain && !Task.isCancelled && state.isSignedIn
        guard generation == syncGeneration else { return }
        isSyncing = false
        syncTask = nil
    }

    private func runRound() async {
        guard let client = client() else { return }
        let local = progress()
        let base = state
        do {
            var outcome = try await SyncRound.run(local, state: base, client: client, now: clock())
            guard !Task.isCancelled, state == base else { return }
            let current = progress()
            if current.save != local.save {
                // The pet changed while the round ran: keep both, push again.
                outcome = outcome.folding(current, base: base)
                syncAgain = true
            }
            // Set first: adopting publishes the save, which must not read
            // as a new change to push.
            syncedSave = outcome.save
            pet.adoptSynced(outcome.save)
            syncedSave = pet.closet.save
            state = outcome.state
            persist()
            lastSyncedAt = state.lastSyncedAt
            notice = nil
            if !grantsAreCurrent { await fetchGrants() }
        } catch let error as PartyError where error.isNoSyncAccount || error == .unauthorized {
            // The account was deleted on another Mac.
            guard state == base else { return }
            if let server = server() { try? credentials.delete(for: server) }
            state = state.forgettingAccount()
            persist()
            settleSignedOut()
        } catch {
            guard !Task.isCancelled else { return }
            notice = Self.message(for: error, signingIn: false)
        }
    }

    /// Hands the account's limited edition grants (`GET /v1/grants`, such
    /// as the launch week cap) to the pet, so they reach every signed-in Mac
    /// even with Party off. Best effort: a failure asks again next round.
    private func fetchGrants() async {
        guard let server = server(), let token = credentials.load(for: server)?.token,
              let items = try? await PartyClient(transport: transport(server), token: token).grants(),
              !Task.isCancelled, state.isSignedIn else { return }
        grantsAreCurrent = true
        pet.applyGrants(items)
    }

    private func progress() -> SyncLocalProgress {
        SyncLocalProgress(save: pet.closet.save, lookChangedAt: pet.lookChangedAt, studyDays: studyDays())
    }

    private func client() -> SyncClient? {
        guard let server = server(), let token = credentials.load(for: server)?.token else { return nil }
        return SyncClient(transport: transport(server), token: token)
    }

    private func cancelSync() {
        debounceTask?.cancel()
        syncTask?.cancel()
        syncTask = nil
        syncAgain = false
        isSyncing = false
    }

    private func settleSignedOut() {
        name = nil
        lastSyncedAt = nil
        syncedSave = nil
        phase = .signedOut
        identityChanged.send()
    }

    private func persist() {
        guard let stateURL, !stateIsUnreadable, let data = try? state.encoded() else { return }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    private static func message(for error: any Error, signingIn: Bool) -> String {
        if let error = error as? PartyError {
            if error.isRejectedAppleSignIn { return "Apple didn't accept the sign-in. Try again." }
            if error.isExpiredWebSignIn { return "The sign-in took too long. Try again." }
            return error.message
        }
        return signingIn ? "Couldn't sign in. Try again." : "Couldn't reach the server. Try again."
    }
}
