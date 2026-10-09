import Foundation

/// Every way a friends-server call can fail, classified by the server's
/// stable `error` code (never its English `message`) so the UI can explain
/// it in one line and the scheduler knows whether and when to retry.
public enum PartyError: Error, Hashable, Sendable {
    /// No network, DNS failure or connection refused: the server is unreachable.
    case unreachable
    /// The server did not answer in time.
    case timedOut
    /// The token is missing or unknown (e.g. the user was deleted); register again.
    case unauthorized
    /// Too many requests; wait this long before the next one.
    case rateLimited(retryAfter: TimeInterval)
    /// `503 unavailable` or `500 internal`: retry later with backoff.
    case serverUnavailable
    /// A field failed validation (`invalid_field`, `unknown_field`, ...).
    case invalidRequest(String)
    case selfFriend
    case unknownCode
    case friendLimit
    case theirFriendLimit
    case partyNotFound
    case notFriend
    case friendOffline
    case friendNotInParty
    case partyFull
    case notInParty
    case notHost
    /// The display name or pet name failed the name filter (`PartyNameFilter`).
    case nameNotAllowed
    case petNameNotAllowed
    case selfBlock
    case blockLimit
    /// I blocked that user; unblock them before adding them.
    case blocked
    case selfReport
    /// 20 reports in the last 24 hours.
    case reportLimit
    /// The maintainer banned this user from Party.
    case banned
    /// Any other error code the server returned.
    case server(code: String, status: Int)
    /// The reply was not the JSON we expected.
    case invalidResponse(String)
    /// Some other network failure.
    case transport(String)

    /// Maps a server `error` code and HTTP status to a typed case.
    public static func fromServer(code: String, status: Int, retryAfter: TimeInterval?) -> PartyError {
        switch code {
        case "unauthorized": return .unauthorized
        case "rate_limited": return .rateLimited(retryAfter: max(1, retryAfter ?? 60))
        case "unavailable", "internal": return .serverUnavailable
        case "invalid_json", "unknown_field", "invalid_field", "body_too_large": return .invalidRequest(code)
        case "self_friend": return .selfFriend
        case "unknown_code": return .unknownCode
        case "friend_limit": return .friendLimit
        case "their_friend_limit": return .theirFriendLimit
        case "party_not_found": return .partyNotFound
        case "not_friend": return .notFriend
        case "friend_offline": return .friendOffline
        case "friend_not_in_party": return .friendNotInParty
        case "party_full": return .partyFull
        case "not_in_party": return .notInParty
        case "not_host": return .notHost
        case "name_not_allowed": return .nameNotAllowed
        case "pet_name_not_allowed": return .petNameNotAllowed
        case "self_block": return .selfBlock
        case "block_limit": return .blockLimit
        case "blocked": return .blocked
        case "self_report": return .selfReport
        case "report_limit": return .reportLimit
        case "banned": return .banned
        default: return status >= 500 ? .serverUnavailable : .server(code: code, status: status)
        }
    }

    /// True for failures that say nothing about the request itself, so the
    /// same call may succeed later (the scheduler backs off and retries).
    public var isTransient: Bool {
        switch self {
        case .unreachable, .timedOut, .rateLimited, .serverUnavailable, .transport: return true
        default: return false
        }
    }

    /// One short sentence for the UI.
    public var message: String {
        switch self {
        case .unreachable: return "Can't reach the party server."
        case .timedOut: return "The party server didn't answer in time."
        case .unauthorized: return "Your party profile was reset. Reconnecting…"
        case .rateLimited: return "Too many requests. Trying again shortly."
        case .serverUnavailable: return "The party server is busy. Trying again shortly."
        case .invalidRequest: return "The server didn't accept that."
        case .selfFriend: return "That's your own code."
        case .unknownCode: return "No one has that friend code."
        case .friendLimit: return "You already have 50 friends."
        case .theirFriendLimit: return "They already have 50 friends."
        case .partyNotFound: return "That party has ended or the code is wrong."
        case .notFriend: return "You can only join a friend's party."
        case .friendOffline: return "Your friend just went offline."
        case .friendNotInParty: return "Your friend left their party."
        case .partyFull: return "That party is full."
        case .notInParty: return "You're not in a party anymore."
        case .notHost: return "Only the host can change the session."
        case .nameNotAllowed: return "That name isn't allowed. Please pick another."
        case .petNameNotAllowed: return "That pet name isn't allowed. Please pick another."
        case .selfBlock: return "That's your own code."
        case .blockLimit: return "You've blocked too many people. Unblock someone first."
        case .blocked: return "You blocked them. Unblock them in Party options first."
        case .selfReport: return "That's your own code."
        case .reportLimit: return "You've sent a lot of reports today. Try again tomorrow."
        case .banned: return "Party is no longer available for this account."
        case .server: return "The party server reported a problem."
        case .invalidResponse: return "Unexpected reply from the party server."
        case .transport: return "Couldn't reach the party server."
        }
    }
}
