import Foundation

/// What one Mac remembers about syncing, saved beside its pet: its device
/// id (the key of its points tally), the account it last synced with, and
/// the document its pet save last adopted with that document's revision.
///
/// The adopted document is what keeps points honest: this Mac's tally is
/// its ledger minus the other Macs' tallies in it (see
/// `SyncDocument.recording`). Signing out keeps it, so signing back in to
/// the same account goes on where it left off; signing in to another
/// account starts from an empty one.
public struct SyncState: Codable, Hashable, Sendable {
    /// The stored format. Bump with a migration step when it changes.
    public static let schema = VersionedJSON(current: 1)

    public var device: String
    /// The friend code the adopted document belongs to; nil before the first sync.
    public var account: String?
    public var adopted: SyncDocument
    public var revision: Int
    public var lastSyncedAt: Date?
    /// Set while this Mac is signed in; nil when signed out, which keeps
    /// the rest so signing back in goes on where it left off.
    public var session: SyncSession?

    public init(device: String = UUID().uuidString, account: String? = nil,
                adopted: SyncDocument = .empty, revision: Int = 0, lastSyncedAt: Date? = nil,
                session: SyncSession? = nil) {
        self.device = device
        self.account = account
        self.adopted = adopted
        self.revision = revision
        self.lastSyncedAt = lastSyncedAt
        self.session = session
    }

    public var isSignedIn: Bool { session != nil }

    /// This state for syncing with `account`: unchanged when it is the
    /// account last synced, otherwise a fresh start that keeps the device id.
    public func signedIn(to account: String) -> SyncState {
        account == self.account ? self : SyncState(device: device, account: account)
    }

    /// Signed in to `account` with `session`, as `signedIn(to:)` keeps or
    /// resets what was synced before.
    public func signedIn(to account: String, session: SyncSession) -> SyncState {
        var state = signedIn(to: account)
        state.session = session
        return state
    }

    /// Signed out: the adopted document stays, so signing back in to the
    /// same account never counts this Mac's points twice.
    public func signedOut() -> SyncState {
        var state = self
        state.session = nil
        return state
    }

    /// After the account was deleted: nothing of it is kept but the device id.
    public func forgettingAccount() -> SyncState {
        SyncState(device: device)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return try Self.schema.encode(self, using: encoder)
    }

    public static func decode(_ data: Data) throws -> SyncState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try schema.decode(SyncState.self, from: data, using: decoder)
    }
}

/// Who is signed in on this Mac. The name is only what Apple shared on
/// the first sign-in; it stays on this Mac and is never sent anywhere.
public struct SyncSession: Codable, Hashable, Sendable {
    public var name: String?
    public var signedInAt: Date

    public init(name: String? = nil, signedInAt: Date) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed?.isEmpty == false ? trimmed : nil
        self.signedInAt = signedInAt
    }
}

/// This Mac's progress at the start of a sync.
public struct SyncLocalProgress: Hashable, Sendable {
    public var save: PetSave
    /// When the user last changed the pet's look here. Nil when unknown,
    /// which loses to any look another Mac chose.
    public var lookChangedAt: Date?
    /// Local days (`YYYY-MM-DD`) with focus time on this Mac.
    public var studyDays: Set<String>

    public init(save: PetSave, lookChangedAt: Date? = nil, studyDays: Set<String> = []) {
        self.save = save
        self.lookChangedAt = lookChangedAt
        self.studyDays = studyDays
    }
}

/// The result of a sync: the merged document, the pet save to adopt, and
/// the state to save for next time.
public struct SyncOutcome: Hashable, Sendable {
    public var document: SyncDocument
    public var save: PetSave
    public var state: SyncState
    /// False when the server already had everything this Mac had.
    public var pushed: Bool

    /// This outcome for a pet that changed while the round ran (`local`,
    /// with `base` the state the round started from): the change goes on
    /// top of the merged document, so neither it nor what the round pulled
    /// is lost. The server does not have the change yet, so `pushed` is
    /// false and the caller syncs again.
    public func folding(_ local: SyncLocalProgress, base: SyncState) -> SyncOutcome {
        var document = base.adopted
            .recording(local.save, changedAt: SyncRound.lookChange(of: local, since: base), device: base.device)
            .merged(with: self.document)
        document.addStudyDays(local.studyDays)
        var state = self.state
        state.adopted = document
        return SyncOutcome(document: document, save: document.applied(to: local.save), state: state, pushed: false)
    }
}

/// One sync: pull, fold this Mac's progress in, merge, and push when the
/// merge added anything, pulling and merging again when another Mac pushed
/// in between. The merge never loses progress, so retrying is always safe.
public enum SyncRound {
    /// Conflicts tolerated before giving up until the next sync.
    public static let maxAttempts = 3

    public static func run(_ local: SyncLocalProgress, state: SyncState, client: SyncClient,
                           now: Date) async throws -> SyncOutcome {
        var mine = state.adopted.recording(local.save, changedAt: lookChange(of: local, since: state), device: state.device)
        mine.addStudyDays(local.studyDays)

        var attempt = 0
        while true {
            attempt += 1
            let remote = try await client.pull()
            let merged = mine.merged(with: remote.document ?? .empty)
            var revision = remote.revision
            let changed = merged != remote.document
            if changed {
                do {
                    revision = try await client.push(merged, ifMatch: remote.revision)
                } catch let error as PartyError where error.isRevisionConflict && attempt < maxAttempts {
                    mine = merged
                    continue
                }
            }
            var next = state
            next.adopted = merged
            next.revision = revision
            next.lastSyncedAt = now
            return SyncOutcome(document: merged, save: merged.applied(to: local.save), state: next, pushed: changed)
        }
    }

    /// When the local look counts as chosen: nil when it is still the
    /// adopted one, so a look another Mac chose since then wins.
    static func lookChange(of local: SyncLocalProgress, since state: SyncState) -> Date? {
        guard local.save.profile != state.adopted.pet?.profile else { return nil }
        return local.lookChangedAt ?? Date(timeIntervalSince1970: 0)
    }
}
