import Foundation

/// What friends and party members see of a user: a name, the pet and two
/// public numbers. Pet fields stay strings on the wire so a newer server
/// catalog never breaks decoding; the app maps them to `PetBreed` itself.
public struct PartyProfile: Codable, Hashable, Sendable {
    public var code: String
    public var name: String
    public var petName: String
    public var species: String
    public var breed: String
    public var colors: [String]
    public var costume: String
    public var accessories: [String]
    public var points: Int
    public var level: Int

    public init(
        code: String,
        name: String,
        petName: String,
        species: String,
        breed: String,
        colors: [String] = [],
        costume: String = "none",
        accessories: [String] = [],
        points: Int = 0,
        level: Int = 1
    ) {
        self.code = code
        self.name = name
        self.petName = petName
        self.species = species
        self.breed = breed
        self.colors = colors
        self.costume = costume
        self.accessories = accessories
        self.points = points
        self.level = level
    }
}

/// The profile fields the app may write. Every field is optional: `nil`
/// keeps the server's value, so a partial edit never blanks the rest.
///
/// It deliberately has no room for anything about cards or decks.
public struct PartyProfileUpdate: Encodable, Hashable, Sendable {
    public var name: String?
    public var petName: String?
    public var species: String?
    public var breed: String?
    public var colors: [String]?
    public var costume: String?
    public var accessories: [String]?
    public var points: Int?
    public var level: Int?

    public init(
        name: String? = nil,
        petName: String? = nil,
        species: String? = nil,
        breed: String? = nil,
        colors: [String]? = nil,
        costume: String? = nil,
        accessories: [String]? = nil,
        points: Int? = nil,
        level: Int? = nil
    ) {
        self.name = name
        self.petName = petName
        self.species = species
        self.breed = breed
        self.colors = colors
        self.costume = costume
        self.accessories = accessories
        self.points = points
        self.level = level
    }
}

/// What a user is doing, as reported by heartbeats.
public enum PartyStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case studying
    case onBreak = "break"
    case idle
    case offline
}

/// A user's presence from their last heartbeat. When they are not online
/// the server reports `offline` and clears the method and phase.
public struct PartyPresence: Codable, Hashable, Sendable {
    public var status: PartyStatus
    /// A catalog study method id, only while studying or on a break.
    public var method: String?
    /// When the current phase ends; count down locally from this.
    public var phaseEndsAt: Date?
    public var sessionMinutes: Int
    public var todayMinutes: Int
    public var streakDays: Int
    /// The local day `todayMinutes` belongs to, `YYYY-MM-DD`.
    public var day: String
    public var lastSeen: Date

    public init(
        status: PartyStatus,
        method: String? = nil,
        phaseEndsAt: Date? = nil,
        sessionMinutes: Int = 0,
        todayMinutes: Int = 0,
        streakDays: Int = 0,
        day: String,
        lastSeen: Date
    ) {
        self.status = status
        self.method = method
        self.phaseEndsAt = phaseEndsAt
        self.sessionMinutes = sessionMinutes
        self.todayMinutes = todayMinutes
        self.streakDays = streakDays
        self.day = day
        self.lastSeen = lastSeen
    }
}

/// A heartbeat body. Only status, timer and minute counters: nothing about
/// cards, decks or what is being studied ever leaves the Mac.
public struct PartyHeartbeat: Encodable, Hashable, Sendable {
    public var status: PartyStatus
    public var method: String?
    public var phaseEndsAt: Date?
    public var sessionMinutes: Int?
    public var todayMinutes: Int?
    public var streakDays: Int?
    public var day: String?

    public init(
        status: PartyStatus,
        method: String? = nil,
        phaseEndsAt: Date? = nil,
        sessionMinutes: Int? = nil,
        todayMinutes: Int? = nil,
        streakDays: Int? = nil,
        day: String? = nil
    ) {
        self.status = status
        self.method = method
        self.phaseEndsAt = phaseEndsAt
        self.sessionMinutes = sessionMinutes
        self.todayMinutes = todayMinutes
        self.streakDays = streakDays
        self.day = day
    }

    /// The `offline` heartbeat sent when quitting, sleeping or going invisible.
    public static let offline = PartyHeartbeat(status: .offline)
}

/// The server's reply to a heartbeat.
public struct PartyHeartbeatReply: Hashable, Sendable {
    public var presence: PartyPresence
    /// When to send the next heartbeat; `nil` after `offline` (stop sending).
    public var nextHeartbeat: TimeInterval?

    public init(presence: PartyPresence, nextHeartbeat: TimeInterval?) {
        self.presence = presence
        self.nextHeartbeat = nextHeartbeat
    }
}

/// The party a friend is in, as seen from the friends list.
public struct PartyRef: Codable, Hashable, Sendable {
    public var code: String
    public var size: Int

    public init(code: String, size: Int) {
        self.code = code
        self.size = size
    }
}

/// One friend in `GET /v1/friends`.
public struct PartyFriend: Codable, Hashable, Sendable, Identifiable {
    public var profile: PartyProfile
    public var since: Date
    public var presence: PartyPresence?
    public var online: Bool
    public var party: PartyRef?

    public var id: String { profile.code }

    /// The contract offers "Join" only for an online friend in a party.
    public var canJoin: Bool { online && party != nil }

    public init(profile: PartyProfile, since: Date, presence: PartyPresence?, online: Bool, party: PartyRef?) {
        self.profile = profile
        self.since = since
        self.presence = presence
        self.online = online
        self.party = party
    }
}

/// The host's shared study session.
public struct PartySession: Codable, Hashable, Sendable {
    public var method: String
    public var phaseEndsAt: Date
    public var startedAt: Date

    public init(method: String, phaseEndsAt: Date, startedAt: Date) {
        self.method = method
        self.phaseEndsAt = phaseEndsAt
        self.startedAt = startedAt
    }
}

/// One party member, in join order.
public struct PartyMember: Codable, Hashable, Sendable, Identifiable {
    public var profile: PartyProfile
    public var joinedAt: Date
    public var host: Bool
    public var presence: PartyPresence?
    public var online: Bool

    public var id: String { profile.code }

    public init(profile: PartyProfile, joinedAt: Date, host: Bool, presence: PartyPresence?, online: Bool) {
        self.profile = profile
        self.joinedAt = joinedAt
        self.host = host
        self.presence = presence
        self.online = online
    }
}

/// A study party: up to eight people sharing a code and, optionally, the
/// host's session timer.
public struct Party: Codable, Hashable, Sendable, Identifiable {
    public var code: String
    /// The host's friend code.
    public var host: String
    public var createdAt: Date
    public var lastActive: Date
    public var expiresAt: Date
    public var maxMembers: Int
    public var session: PartySession?
    public var members: [PartyMember]

    public var id: String { code }

    public init(
        code: String,
        host: String,
        createdAt: Date,
        lastActive: Date,
        expiresAt: Date,
        maxMembers: Int,
        session: PartySession?,
        members: [PartyMember]
    ) {
        self.code = code
        self.host = host
        self.createdAt = createdAt
        self.lastActive = lastActive
        self.expiresAt = expiresAt
        self.maxMembers = maxMembers
        self.session = session
        self.members = members
    }

    /// Whether the user with this friend code hosts the party.
    public func isHost(_ code: String) -> Bool { host == code }

    public var isFull: Bool { members.count >= maxMembers }
}

/// One row of the weekly leaderboard. Ties share a rank.
public struct PartyLeaderboardEntry: Codable, Hashable, Sendable {
    public var rank: Int
    public var minutes: Int
    public var me: Bool
    public var profile: PartyProfile

    public init(rank: Int, minutes: Int, me: Bool, profile: PartyProfile) {
        self.rank = rank
        self.minutes = minutes
        self.me = me
        self.profile = profile
    }
}

/// This ISO week's study minutes for me and my friends.
public struct PartyLeaderboard: Codable, Hashable, Sendable {
    /// e.g. `2026-W40`.
    public var week: String
    public var from: String
    public var to: String
    public var entries: [PartyLeaderboardEntry]

    public init(week: String, from: String, to: String, entries: [PartyLeaderboardEntry]) {
        self.week = week
        self.from = from
        self.to = to
        self.entries = entries
    }
}

/// A fresh registration: the secret token (Keychain only) and the public
/// friend code to share.
public struct PartyRegistration: Hashable, Sendable {
    public var token: String
    public var code: String
    public var profile: PartyProfile

    public init(token: String, code: String, profile: PartyProfile) {
        self.token = token
        self.code = code
        self.profile = profile
    }
}

/// Friend and party codes: `A-Z` and `2-9` without the look-alikes
/// `I`, `O`, `0` and `1`. Friend codes have 8 characters, party codes 6.
public enum PartyCode {
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let friendCodeLength = 8
    public static let partyCodeLength = 6

    /// Upper-cases and strips spaces and dashes so pasted codes like
    /// `k7qw-2mzd` work; returns `nil` unless the result is a valid code
    /// of `length` characters.
    public static func normalize(_ text: String, length: Int) -> String? {
        let cleaned = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy(alphabet.contains) else { return nil }
        return cleaned
    }

    public static func friendCode(_ text: String) -> String? { normalize(text, length: friendCodeLength) }
    public static func partyCode(_ text: String) -> String? { normalize(text, length: partyCodeLength) }
}
