import Foundation

/// The friends server Tabbi talks to.
public enum PartyServer {
    /// The deployed friends worker, used until the user enters another.
    /// It still runs under its old `studynotch-friends` name until the
    /// maintainer deploys the renamed `tabbi-friends` worker and updates this.
    public static let productionURL = URL(string: "https://studynotch-friends.drosophil-anki-friends-backend.workers.dev")!
    /// `npm run dev` in `backend/`.
    public static let localDevURL = URL(string: "http://localhost:8787")!

    /// Parses a server URL typed in Settings. Accepts `https://` anywhere
    /// and plain `http://` only for this Mac, so a token never crosses the
    /// network unencrypted. A missing scheme means `https://`.
    public static func parse(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.query == nil, url.fragment == nil
        else { return nil }
        switch scheme {
        case "https": return url
        case "http": return ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
        default: return nil
        }
    }
}

/// Typed async client for the Tabbi friends API (see
/// `docs/study/backend-api.md`).
///
/// It only sends what the contract lists: profile and pet appearance,
/// presence (status, timer, minute counters) and codes. It has no call that
/// could carry card, deck or note content. It does no scheduling; callers
/// follow the contract's polling guidance (see `PartyHeartbeatSchedule`).
public struct PartyClient: Sendable {
    public var transport: any PartyTransport
    /// The secret bearer token from `register`; `nil` before registration.
    public var token: String?
    public var timeout: TimeInterval

    public init(transport: any PartyTransport, token: String? = nil, timeout: TimeInterval = 10) {
        self.transport = transport
        self.token = token
        self.timeout = timeout
    }

    public init(baseURL: URL, token: String? = nil, timeout: TimeInterval = 10) {
        self.init(transport: URLSessionPartyTransport(baseURL: baseURL), token: token, timeout: timeout)
    }

    // MARK: Health

    /// Service names a friends server answers `GET /` with: the current
    /// `tabbi-friends` worker and the `studynotch-friends` deployment from
    /// before the rename, which serves the same contract.
    public static let serviceNames: Set<String> = ["tabbi-friends", "studynotch-friends"]

    /// `GET /`: true when the server answers as a friends server.
    public func health() async throws -> Bool {
        let reply = try await send("GET", "/", authorized: false, as: HealthReply.self)
        return Self.serviceNames.contains(reply.service)
    }

    // MARK: Profile

    /// `POST /v1/register` without a token: creates a user. Safe to retry,
    /// since a lost reply just means registering again.
    public func register(_ profile: PartyProfileUpdate = PartyProfileUpdate()) async throws -> PartyRegistration {
        let reply = try await send("POST", "/v1/register", body: profile, authorized: false, as: RegisterReply.self)
        guard let token = reply.token else { throw PartyError.invalidResponse("register returned no token") }
        return PartyRegistration(token: token, code: reply.code, profile: reply.profile)
    }

    /// `GET /v1/me`.
    public func me() async throws -> PartyProfile {
        try await send("GET", "/v1/me", as: ProfileReply.self).profile
    }

    /// `PATCH /v1/me`: unchanged fields cost nothing, so sending the whole
    /// profile after every pet edit is fine.
    public func updateProfile(_ update: PartyProfileUpdate) async throws -> PartyProfile {
        try await send("PATCH", "/v1/me", body: update, as: ProfileReply.self).profile
    }

    /// `DELETE /v1/me`: deletes the user and everything about them.
    public func deleteMe() async throws {
        _ = try await send("DELETE", "/v1/me", as: OKReply.self)
    }

    // MARK: Friends

    /// `GET /v1/friends`, sorted by name.
    public func friends() async throws -> [PartyFriend] {
        try await send("GET", "/v1/friends", as: FriendsReply.self).friends
    }

    /// `POST /v1/friends`. Friendship is mutual at once. `added` is false
    /// when they were already friends.
    public func addFriend(code: String) async throws -> (added: Bool, friend: PartyProfile) {
        let code = try Self.validCode(PartyCode.friendCode(code))
        let reply = try await send("POST", "/v1/friends", body: ["code": code], as: AddFriendReply.self)
        return (reply.added, reply.friend)
    }

    /// `DELETE /v1/friends/{code}`. Returns false if we were not friends.
    @discardableResult
    public func removeFriend(code: String) async throws -> Bool {
        let code = try Self.validCode(PartyCode.friendCode(code))
        return try await send("DELETE", "/v1/friends/\(code)", as: RemoveFriendReply.self).removed
    }

    // MARK: Presence

    /// `POST /v1/presence`: the heartbeat.
    public func heartbeat(_ heartbeat: PartyHeartbeat) async throws -> PartyHeartbeatReply {
        let reply = try await send("POST", "/v1/presence", body: heartbeat, as: PresenceReply.self)
        return PartyHeartbeatReply(presence: reply.presence, nextHeartbeat: reply.heartbeatSeconds)
    }

    /// `GET /v1/leaderboard`: this ISO week's minutes for me and my friends.
    public func leaderboard() async throws -> PartyLeaderboard {
        let reply = try await send("GET", "/v1/leaderboard", as: LeaderboardReply.self)
        return PartyLeaderboard(week: reply.week, from: reply.from, to: reply.to, entries: reply.entries)
    }

    // MARK: Parties

    /// `GET /v1/party`: my party, or `nil`.
    public func party() async throws -> Party? {
        try await send("GET", "/v1/party", as: OptionalPartyReply.self).party
    }

    /// `POST /v1/party`: a new party hosted by me, leaving any other.
    public func createParty() async throws -> Party {
        try await send("POST", "/v1/party", as: PartyReply.self).party
    }

    /// `POST /v1/party/join` by party code.
    public func joinParty(code: String) async throws -> Party {
        let code = try Self.validCode(PartyCode.partyCode(code))
        return try await send("POST", "/v1/party/join", body: ["code": code], as: PartyReply.self).party
    }

    /// `POST /v1/party/join` through an online friend who is in a party.
    public func joinParty(friend: String) async throws -> Party {
        let code = try Self.validCode(PartyCode.friendCode(friend))
        return try await send("POST", "/v1/party/join", body: ["friend": code], as: PartyReply.self).party
    }

    /// `POST /v1/party/leave`. Returns false if I was not in a party.
    @discardableResult
    public func leaveParty() async throws -> Bool {
        try await send("POST", "/v1/party/leave", as: LeaveReply.self).left
    }

    /// `POST /v1/party/session` (host only): starts or replaces the shared
    /// session. Send a new `phaseEndsAt` for each phase.
    public func startSession(method: String, phaseEndsAt: Date) async throws -> Party {
        let body = SessionBody(method: method, phaseEndsAt: phaseEndsAt)
        return try await send("POST", "/v1/party/session", body: body, as: PartyReply.self).party
    }

    /// `DELETE /v1/party/session` (host only).
    public func endSession() async throws -> Party {
        try await send("DELETE", "/v1/party/session", as: PartyReply.self).party
    }

    // MARK: Plumbing

    /// Encodes dates as whole unix seconds, which is what the server accepts.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int(date.timeIntervalSince1970.rounded()))
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private static func validCode(_ code: String?) throws -> String {
        guard let code else { throw PartyError.invalidRequest("invalid_field") }
        return code
    }

    private func send<Reply: Decodable>(
        _ method: String, _ path: String, authorized: Bool = true, as type: Reply.Type
    ) async throws -> Reply {
        try await perform(PartyHTTPRequest(method: method, path: path), authorized: authorized, as: type)
    }

    private func send<Body: Encodable, Reply: Decodable>(
        _ method: String, _ path: String, body: Body, authorized: Bool = true, as type: Reply.Type
    ) async throws -> Reply {
        let data = try Self.makeEncoder().encode(body)
        return try await perform(PartyHTTPRequest(method: method, path: path, body: data), authorized: authorized, as: type)
    }

    private func perform<Reply: Decodable>(
        _ request: PartyHTTPRequest, authorized: Bool, as type: Reply.Type
    ) async throws -> Reply {
        var request = request
        if authorized {
            guard let token else { throw PartyError.unauthorized }
            request.token = token
        }
        let response: PartyHTTPResponse
        do {
            response = try await transport.send(request, timeout: timeout)
        } catch let error as PartyError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PartyError.transport(error.localizedDescription)
        }
        return try Self.decode(response, as: type)
    }

    /// Reads the `{ok, error}` envelope and decodes a successful reply.
    static func decode<Reply: Decodable>(_ response: PartyHTTPResponse, as type: Reply.Type) throws -> Reply {
        let decoder = makeDecoder()
        let envelope = try? decoder.decode(Envelope.self, from: response.body)
        if response.statusCode >= 400 || envelope?.ok == false {
            if let code = envelope?.error {
                throw PartyError.fromServer(code: code, status: response.statusCode, retryAfter: response.retryAfter)
            }
            if response.statusCode == 429 {
                throw PartyError.rateLimited(retryAfter: max(1, response.retryAfter ?? 60))
            }
            if response.statusCode >= 500 { throw PartyError.serverUnavailable }
            throw PartyError.invalidResponse("HTTP \(response.statusCode)")
        }
        guard envelope?.ok == true else { throw PartyError.invalidResponse("not a friends-server reply") }
        do {
            return try decoder.decode(Reply.self, from: response.body)
        } catch {
            throw PartyError.invalidResponse(String(describing: error))
        }
    }
}

// MARK: Wire replies

private struct Envelope: Decodable {
    let ok: Bool
    let error: String?
}

private struct OKReply: Decodable {}

private struct HealthReply: Decodable {
    let service: String
}

private struct RegisterReply: Decodable {
    let token: String?
    let code: String
    let profile: PartyProfile
}

private struct ProfileReply: Decodable {
    let profile: PartyProfile
}

private struct FriendsReply: Decodable {
    let friends: [PartyFriend]
}

private struct AddFriendReply: Decodable {
    let added: Bool
    let friend: PartyProfile
}

private struct RemoveFriendReply: Decodable {
    let removed: Bool
}

private struct PresenceReply: Decodable {
    let presence: PartyPresence
    let heartbeatSeconds: TimeInterval?
}

private struct LeaderboardReply: Decodable {
    let week: String
    let from: String
    let to: String
    let entries: [PartyLeaderboardEntry]
}

private struct OptionalPartyReply: Decodable {
    let party: Party?
}

private struct PartyReply: Decodable {
    let party: Party
}

private struct LeaveReply: Decodable {
    let left: Bool
}

private struct SessionBody: Encodable {
    let method: String
    let phaseEndsAt: Date
}
