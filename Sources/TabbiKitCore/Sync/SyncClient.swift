import Foundation

/// What `POST /v1/auth/apple` hands back: the friends identity this Mac
/// uses from now on (it replaces the stored Party credentials) and whether
/// the Apple ID was new to the server.
public struct AppleSignInReply: Hashable, Sendable {
    public var credentials: PartyCredentials
    public var profile: PartyProfile
    /// False when the Apple ID already had an account, so this Mac adopted
    /// its friend code (and the friends and progress that come with it).
    public var newAccount: Bool

    public init(credentials: PartyCredentials, profile: PartyProfile, newAccount: Bool) {
        self.credentials = credentials
        self.profile = profile
        self.newAccount = newAccount
    }
}

/// The account's sync document as the server holds it.
public struct SyncPull: Hashable, Sendable {
    /// 0 before any Mac pushed.
    public var revision: Int
    public var updatedAt: Date?
    /// Nil before any Mac pushed.
    public var document: SyncDocument?

    public init(revision: Int, updatedAt: Date? = nil, document: SyncDocument? = nil) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.document = document
    }
}

/// The calls Sign in with Apple adds to the friends API (see
/// `docs/study/backend-api.md`). Errors are `PartyError`s, like every
/// other friends-server call; the sync-only ones are named below.
public struct SyncClient: Sendable {
    public var transport: any PartyTransport
    /// The friends token. Optional for sign-in (it links the Mac's
    /// anonymous Party user), required for the sync routes.
    public var token: String?
    public var timeout: TimeInterval

    public init(transport: any PartyTransport, token: String? = nil, timeout: TimeInterval = 10) {
        self.transport = transport
        self.token = token
        self.timeout = timeout
    }

    /// `POST /v1/auth/apple` with what `ASAuthorizationAppleIDCredential`
    /// returned. Store the reply's credentials in place of the old ones.
    public func signInWithApple(identityToken: String, authorizationCode: String?) async throws -> AppleSignInReply {
        var body: [String: String] = ["identityToken": identityToken]
        body["authorizationCode"] = authorizationCode
        let data = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        let request = PartyHTTPRequest(method: "POST", path: "/v1/auth/apple", body: data, token: token)
        let reply = try PartyClient.decode(try await send(request), as: SignInReply.self)
        return AppleSignInReply(
            credentials: PartyCredentials(token: reply.token, code: reply.code),
            profile: reply.profile,
            newAccount: reply.newAccount
        )
    }

    /// `GET /v1/sync`.
    public func pull() async throws -> SyncPull {
        let response = try await send(try authorized(PartyHTTPRequest(method: "GET", path: "/v1/sync")))
        let reply = try PartyClient.decode(response, as: PullReply.self)
        // The document keeps its own date format, so it is read from the raw object.
        let object = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
        var document: SyncDocument?
        if let raw = object?["document"] as? [String: Any] {
            do {
                document = try SyncDocument.decode(JSONSerialization.data(withJSONObject: raw))
            } catch {
                throw PartyError.invalidResponse("unreadable sync document")
            }
        }
        return SyncPull(revision: reply.revision, updatedAt: reply.updatedAt, document: document)
    }

    /// `PUT /v1/sync` with `If-Match: revision`, the revision `document`
    /// was merged into. Returns the new revision. Throws a `PartyError`
    /// whose `isRevisionConflict` is true when another Mac pushed first:
    /// pull, merge and push again.
    public func push(_ document: SyncDocument, ifMatch revision: Int) async throws -> Int {
        var body = Data(#"{"document":"#.utf8)
        body.append(try document.encoded())
        body.append(Data("}".utf8))
        let request = PartyHTTPRequest(method: "PUT", path: "/v1/sync", body: body,
                                       headers: ["If-Match": "\"\(revision)\""])
        return try PartyClient.decode(try await send(try authorized(request)), as: PushReply.self).revision
    }

    // MARK: Plumbing

    private func authorized(_ request: PartyHTTPRequest) throws -> PartyHTTPRequest {
        guard let token else { throw PartyError.unauthorized }
        var request = request
        request.token = token
        return request
    }

    private func send(_ request: PartyHTTPRequest) async throws -> PartyHTTPResponse {
        do {
            return try await transport.send(request, timeout: timeout)
        } catch let error as PartyError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PartyError.transport(error.localizedDescription)
        }
    }
}

extension PartyError {
    /// `409 revision_conflict`: another Mac pushed since the last pull.
    public var isRevisionConflict: Bool {
        if case .server("revision_conflict", _) = self { return true }
        return false
    }

    /// `403 no_account`: the token is not linked to a Sign in with Apple
    /// account (for example after the account was deleted on another Mac).
    public var isNoSyncAccount: Bool {
        if case .server("no_account", _) = self { return true }
        return false
    }

    /// `401 invalid_identity_token`: Apple's token was refused; ask the
    /// user to sign in again.
    public var isRejectedAppleSignIn: Bool {
        if case .server("invalid_identity_token", _) = self { return true }
        return false
    }
}

// MARK: Wire replies

private struct SignInReply: Decodable {
    let token: String
    let code: String
    let profile: PartyProfile
    let newAccount: Bool
}

private struct PullReply: Decodable {
    let revision: Int
    let updatedAt: Date?
}

private struct PushReply: Decodable {
    let revision: Int
}
