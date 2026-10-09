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
        /// This build cannot sign in (no Sign in with Apple entitlement:
        /// dev, ad-hoc and snapshot builds) and no account is signed in.
        case unavailable
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

    /// Sent after the stored Party credentials changed (sign in, sign out,
    /// delete), so Party reconnects with the new identity.
    let identityChanged = PassthroughSubject<Void, Never>()

    /// How long the save stays quiet before a change is pushed.
    static let debounce: TimeInterval = 5
    /// How long a sync waits after wake, so Wi-Fi is back before it runs
    /// instead of failing with a notice right away.
    static let wakeDelay: TimeInterval = 10
    /// How long quitting waits for the last push.
    static let quitWait: TimeInterval = 2

    let isDemo: Bool
    private let isSnapshot: Bool
    private let isAvailable: Bool
    private let pet: ClosetStore
    private let stateURL: URL?
    private let credentials: any PartyCredentialStore
    private let server: () -> URL?
    private let transport: (URL) -> any PartyTransport
    private let studyDays: () -> Set<String>
    private let clock: () -> Date
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
    private var cancellables: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - isAvailable: whether this build may sign in with Apple
    ///     (`AppleSignInAvailability.isEntitled`).
    ///   - server: the friends server Party uses now.
    ///   - credentials: where Party keeps its identity; the account replaces it.
    ///   - transport: replaces HTTPS (tests).
    ///   - studyDays: local days with focus time on this Mac, for the streak.
    init(storage: EditionStorage, runMode: RunMode, pet: ClosetStore, isAvailable: Bool,
         server: @escaping () -> URL?, credentials: any PartyCredentialStore,
         transport: ((URL) -> any PartyTransport)? = nil,
         studyDays: @escaping () -> Set<String> = { [] }, clock: @escaping () -> Date = Date.init) {
        isDemo = runMode.isDemo
        isSnapshot = runMode.isSnapshot
        self.isAvailable = isAvailable
        self.pet = pet
        self.server = server
        self.credentials = credentials
        self.transport = transport ?? { URLSessionPartyTransport(baseURL: $0) }
        self.studyDays = studyDays
        self.clock = clock
        if isDemo {
            stateURL = nil
            stateIsUnreadable = false
            state = SyncState(device: "demo", account: "K7QW2MZD",
                              session: SyncSession(name: "Sam Rivera", signedInAt: clock()))
            phase = .signedIn
            name = "Sam Rivera"
            lastSyncedAt = clock().addingTimeInterval(-4 * 60)
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
        phase = loaded.isSignedIn ? .signedIn : isAvailable ? .signedOut : .unavailable
        name = loaded.session?.name
        lastSyncedAt = loaded.lastSyncedAt
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
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncSoon(after: Self.wakeDelay) } }
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

    // MARK: Account

    /// Signs in with what `ASAuthorizationAppleIDCredential` returned:
    /// links (or adopts) the account, stores its Party identity and syncs,
    /// merging this Mac's progress with the account's.
    func signIn(identityToken: String, authorizationCode: String?, name: String?) async {
        guard !isDemo, phase == .signedOut || phase == .unavailable, let server = server() else { return }
        notice = nil
        let before = phase
        phase = .signingIn
        do {
            let client = SyncClient(transport: transport(server), token: credentials.load(for: server)?.token)
            let reply = try await client.signInWithApple(identityToken: identityToken, authorizationCode: authorizationCode)
            try credentials.save(reply.credentials, for: server)
            state = state.signedIn(to: reply.credentials.code,
                                   session: SyncSession(name: name ?? self.name, signedInAt: clock()))
            persist()
            self.name = state.session?.name
            lastSyncedAt = state.lastSyncedAt
            phase = .signedIn
            identityChanged.send()
            syncNow()
        } catch {
            phase = before
            notice = Self.message(for: error, signingIn: true)
        }
    }

    /// Lets a snapshot run render the signed-out row a release build shows
    /// (`true`) and then the unavailable one again; does nothing elsewhere.
    func showsSignInForSnapshot(_ shows: Bool) {
        guard isSnapshot, !isDemo, !state.isSignedIn else { return }
        phase = shows ? .signedOut : .unavailable
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
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
            pet.adoptSynced(outcome.save)
            syncedSave = pet.closet.save
            state = outcome.state
            persist()
            lastSyncedAt = state.lastSyncedAt
            notice = nil
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
        phase = isAvailable ? .signedOut : .unavailable
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
            return error.message
        }
        return signingIn ? "Couldn't sign in. Try again." : "Couldn't reach the server. Try again."
    }
}
