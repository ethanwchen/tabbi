import Foundation

/// Someone I blocked, as `GET /v1/blocks` lists them, so the Blocked list
/// in Party options can name them and offer Unblock.
public struct PartyBlockedUser: Codable, Hashable, Sendable, Identifiable {
    public var code: String
    public var name: String
    public var petName: String
    /// When I blocked them; `nil` in the reply to `POST /v1/blocks`.
    public var since: Date?

    public var id: String { code }

    public init(code: String, name: String, petName: String, since: Date? = nil) {
        self.code = code
        self.name = name
        self.petName = petName
        self.since = since
    }
}

/// Why I report someone; the raw values are the server's `reason` codes.
public enum PartyReportReason: String, Codable, CaseIterable, Hashable, Sendable {
    case inappropriateName = "inappropriate_name"
    case harassment
    case spam
    case other

    /// The label in the reason picker.
    public var title: String {
        switch self {
        case .inappropriateName: return "Inappropriate name"
        case .harassment: return "Harassment"
        case .spam: return "Spam"
        case .other: return "Other"
        }
    }
}

/// A report about another user for `POST /v1/reports`.
public struct PartyReport: Hashable, Sendable {
    /// The longest note the server keeps.
    public static let noteLimit = 280

    public var code: String
    public var reason: PartyReportReason
    /// Optional; trimmed, and left out of the request when empty.
    public var note: String

    public init(code: String, reason: PartyReportReason, note: String = "") {
        self.code = code
        self.reason = reason
        self.note = note
    }

    /// The note as it is sent: trimmed, cut to `noteLimit` characters, or
    /// `nil` when nothing is left, so a typed-in note never fails validation.
    public var sentNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Self.noteLimit))
    }
}

/// What `GET /v1/me` says about my own account.
public struct PartyStanding: Hashable, Sendable {
    public var profile: PartyProfile
    /// The maintainer banned this user: Party stays read-only for them.
    public var banned: Bool

    public init(profile: PartyProfile, banned: Bool = false) {
        self.profile = profile
        self.banned = banned
    }
}
