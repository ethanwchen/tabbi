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
    /// The friend request to accept is gone (cancelled, declined or expired).
    case noRequest
    /// 50 friend requests already wait for an answer.
    case pendingLimit
    /// 50 new friend requests in one day.
    case requestLimit
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
        case "no_request": return .noRequest
        case "pending_limit": return .pendingLimit
        case "request_limit": return .requestLimit
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
        case .unreachable: return String(localized: "Can't reach the party server.", bundle: .tabbi)
        case .timedOut: return String(localized: "The party server didn't answer in time.", bundle: .tabbi)
        case .unauthorized: return String(localized: "Your party profile was reset. Reconnecting…", bundle: .tabbi)
        case .rateLimited: return String(localized: "Too many requests. Trying again shortly.", bundle: .tabbi)
        case .serverUnavailable: return String(localized: "The party server is busy. Trying again shortly.", bundle: .tabbi)
        case .invalidRequest: return String(localized: "The server didn't accept that.", bundle: .tabbi)
        case .selfFriend: return String(localized: "That's your own code.", bundle: .tabbi)
        case .unknownCode: return String(localized: "No one has that friend code.", bundle: .tabbi)
        case .friendLimit: return String(localized: "You already have 50 friends.", bundle: .tabbi)
        case .theirFriendLimit: return String(localized: "They already have 50 friends.", bundle: .tabbi)
        case .noRequest: return String(localized: "That friend request is no longer there.", bundle: .tabbi)
        case .pendingLimit: return String(localized: "You have 50 friend requests waiting. Cancel some first.", bundle: .tabbi)
        case .requestLimit: return String(localized: "You've sent a lot of friend requests today. Try again tomorrow.", bundle: .tabbi)
        case .partyNotFound: return String(localized: "That party has ended or the code is wrong.", bundle: .tabbi)
        case .notFriend: return String(localized: "You can only join a friend's party.", bundle: .tabbi)
        case .friendOffline: return String(localized: "Your friend just went offline.", bundle: .tabbi)
        case .friendNotInParty: return String(localized: "Your friend left their party.", bundle: .tabbi)
        case .partyFull: return String(localized: "That party is full.", bundle: .tabbi)
        case .notInParty: return String(localized: "You're not in a party anymore.", bundle: .tabbi)
        case .notHost: return String(localized: "Only the host can change the session.", bundle: .tabbi)
        case .nameNotAllowed: return String(localized: "That name isn't allowed. Please pick another.", bundle: .tabbi)
        case .petNameNotAllowed: return String(localized: "That pet name isn't allowed. Please pick another.", bundle: .tabbi)
        case .selfBlock: return String(localized: "That's your own code.", bundle: .tabbi)
        case .blockLimit: return String(localized: "You've blocked too many people. Unblock someone first.", bundle: .tabbi)
        case .blocked: return String(localized: "You blocked them. Unblock them in Party options first.", bundle: .tabbi)
        case .selfReport: return String(localized: "That's your own code.", bundle: .tabbi)
        case .reportLimit: return String(localized: "You've sent a lot of reports today. Try again tomorrow.", bundle: .tabbi)
        case .banned: return String(localized: "Party is no longer available for this account.", bundle: .tabbi)
        case .server: return String(localized: "The party server reported a problem.", bundle: .tabbi)
        case .invalidResponse: return String(localized: "Unexpected reply from the party server.", bundle: .tabbi)
        case .transport: return String(localized: "Couldn't reach the party server.", bundle: .tabbi)
        }
    }
}
