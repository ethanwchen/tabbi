import Foundation

/// The user's identity on one friends server: it loads the stored token or
/// registers on first use, keeps the profile in sync, and runs every other
/// call with that token.
///
/// The server only stores a token's hash, so an `unauthorized` reply means
/// the identity is gone for good (the user was deleted or purged). The
/// account then drops the stored token, registers again with the last
/// profile it synced and retries the call once, so the Party tab heals
/// itself with a new friend code instead of showing an error forever.
///
/// An actor so concurrent calls (a heartbeat while the panel refreshes)
/// never register twice.
public actor PartyAccount {
    public let server: URL
    private let transport: any PartyTransport
    private let store: any PartyCredentialStore
    private let timeout: TimeInterval

    /// The stored or newly registered identity; nil until the first
    /// successful `connect`, or after `deleteAccount`.
    ///
    /// Read from the store on first use, inside the actor, never in `init`:
    /// a Keychain read can wait on an access prompt (say, for an item an
    /// older build wrote), which must not block the main thread.
    public private(set) var credentials: PartyCredentials? {
        get {
            if let loaded { return loaded }
            let stored = store.load(for: server)
            loaded = .some(stored)
            return stored
        }
        set { loaded = .some(newValue) }
    }
    /// `nil` until the store was read.
    private var loaded: PartyCredentials??
    /// The profile the server last returned.
    public private(set) var profile: PartyProfile?
    /// The names the server refused on the last successful `connect`.
    public private(set) var refusedNames: PartyNameRefusal = []
    /// The profile last sent, reused when the identity must be recreated.
    private var desiredProfile = PartyProfileUpdate()
    /// The registration in flight, shared by every call that needs it.
    private var registering: Task<PartyRegistration, Error>?

    public init(server: URL, transport: (any PartyTransport)? = nil,
                credentials store: any PartyCredentialStore, timeout: TimeInterval = 10) {
        self.server = server
        self.transport = transport ?? URLSessionPartyTransport(baseURL: server)
        self.store = store
        self.timeout = timeout
    }

    /// The public friend code, once known.
    public var friendCode: String? { credentials?.code }

    /// Makes sure there is an identity and the server has `profile`:
    /// registers with it on first use, otherwise sends it with
    /// `PATCH /v1/me` (unchanged fields cost nothing). Call at launch and
    /// after the user edits their name or pet.
    ///
    /// A name the server refuses (`name_not_allowed`, `pet_name_not_allowed`,
    /// for example one a maintainer replaced) is left out and the rest sent
    /// again, so a refused name never takes Party offline; `refusedNames`
    /// says which, so the app can ask for another.
    @discardableResult
    public func connect(profile update: PartyProfileUpdate) async throws -> PartyProfile {
        var update = update
        var refused: PartyNameRefusal = []
        while true {
            do {
                let profile = try await sync(update)
                refusedNames = refused
                return profile
            } catch let error as PartyError {
                guard let refusal = PartyNameRefusal(error), !refused.contains(refusal) else { throw error }
                refused.insert(refusal)
                update = update.removing(refusal)
            }
        }
    }

    private func sync(_ update: PartyProfileUpdate) async throws -> PartyProfile {
        desiredProfile = update
        if credentials == nil {
            _ = try await register()
            if let profile { return profile }
        }
        let standing = try await perform { try await $0.updateStanding(update) }
        profile = standing.profile
        // A banned user's calls still work, but Party has nothing left to
        // offer them, so the tab says so instead of showing an empty room.
        if standing.banned { throw PartyError.banned }
        return standing.profile
    }

    /// Runs `call` with the current token, registering first when there is
    /// none, and recovering once from `unauthorized` by registering again.
    public func perform<T: Sendable>(_ call: @Sendable (PartyClient) async throws -> T) async throws -> T {
        let current = try await identity()
        do {
            return try await call(client(token: current.token))
        } catch PartyError.unauthorized {
            if credentials == current {
                credentials = nil
                try? store.delete(for: server)
            }
            let fresh = try await identity()
            return try await call(client(token: fresh.token))
        }
    }

    /// `DELETE /v1/me`, then forgets the token, so the next `connect`
    /// starts over with a new friend code.
    public func deleteAccount() async throws {
        if let credentials {
            do {
                try await client(token: credentials.token).deleteMe()
            } catch PartyError.unauthorized {
                // Already gone on the server; just forget it here.
            }
        }
        credentials = nil
        profile = nil
        try store.delete(for: server)
    }

    // MARK: Calls that keep the account's profile current

    /// `GET /v1/me`.
    public func refreshProfile() async throws -> PartyProfile {
        let fresh = try await perform { try await $0.me() }
        profile = fresh
        return fresh
    }

    /// The stored identity, or a new one registered with `desiredProfile`.
    private func identity() async throws -> PartyCredentials {
        if let credentials { return credentials }
        return try await register()
    }

    private func register() async throws -> PartyCredentials {
        let task: Task<PartyRegistration, Error>
        if let registering {
            task = registering
        } else {
            let client = client(token: nil)
            let update = desiredProfile
            task = Task { try await client.register(update) }
            registering = task
        }
        let registration: PartyRegistration
        do {
            registration = try await task.value
        } catch {
            if registering == task { registering = nil }
            throw error
        }
        if registering == task {
            registering = nil
            let credentials = PartyCredentials(registration)
            // A lost Keychain write only costs a new code on the next launch.
            try? store.save(credentials, for: server)
            self.credentials = credentials
            profile = registration.profile
        }
        return PartyCredentials(registration)
    }

    private func client(token: String?) -> PartyClient {
        PartyClient(transport: transport, token: token, timeout: timeout)
    }
}
