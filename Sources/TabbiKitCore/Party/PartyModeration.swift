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

/// Where people report a problem, abuse in Party included. Party options
/// and Settings > About both show it, so a contact point is always one
/// click away (App Review Guideline 1.2).
public enum SupportContact {
    public static let email = "support@tabbinotch.com"
    /// Opens a new message to `email` in the user's mail app.
    public static let mailURL = URL(string: "mailto:\(email)")!
    /// The line both places show.
    public static let reportLine = "Report a problem: \(email)"
}

/// Which of my names the friends server refused (`name_not_allowed`,
/// `pet_name_not_allowed`): one that fails `PartyNameFilter`, or one a
/// maintainer replaced and holds. The app leaves it out of the profile so
/// the rest still syncs, and asks for another.
public struct PartyNameRefusal: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let name = PartyNameRefusal(rawValue: 1 << 0)
    public static let petName = PartyNameRefusal(rawValue: 1 << 1)

    /// The refusal `error` stands for, or nil for any other error.
    public init?(_ error: PartyError) {
        switch error {
        case .nameNotAllowed: self = .name
        case .petNameNotAllowed: self = .petName
        default: return nil
        }
    }

    /// The friendly line shown under the name, or nil when nothing was refused.
    public var message: String? {
        switch (contains(.name), contains(.petName)) {
        case (true, true): return "That name and your pet's name aren't allowed. Please pick others."
        case (true, false): return "That name isn't allowed. Please pick another."
        case (false, true): return "Your pet's name isn't allowed. Rename your pet in the Closet."
        case (false, false): return nil
        }
    }
}

extension PartyProfileUpdate {
    /// The same update without the refused names, so the server keeps the
    /// ones it has.
    public func removing(_ refused: PartyNameRefusal) -> PartyProfileUpdate {
        var update = self
        if refused.contains(.name) { update.name = nil }
        if refused.contains(.petName) { update.petName = nil }
        return update
    }
}
