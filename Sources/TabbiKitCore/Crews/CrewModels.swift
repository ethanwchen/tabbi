import Foundation

// The Study Crews wire models (protocol 3). The shapes are written down in
// `shared/schemas/crews.v1.schema.json` and the design in
// `docs/design/crews.md`. Like the Party models, every id stays a string on
// the wire, so a newer server's frame, emblem, color or laurel never breaks
// decoding; the app falls back to the first frame, emblem and color it knows.

/// A crew week: Monday 00:00 UTC up to (not including) the next Monday.
public struct CrewWeek: Codable, Hashable, Sendable {
    /// The ISO week key, such as `2026-W46`.
    public var id: String
    public var startsAt: Date
    /// Exclusive: the moment the board freezes.
    public var endsAt: Date

    public init(id: String, startsAt: Date, endsAt: Date) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    /// The week that contains `date`, computed the way the server does, for
    /// demo data and for a countdown before the first reply.
    public static func containing(_ date: Date) -> CrewWeek {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)!
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return CrewWeek(id: String(format: "%04d-W%02d", year, week), startsAt: interval.start, endsAt: interval.end)
    }
}

/// The laurel a crew wears for the week after it finished in the top 3.
public enum CrewLaurel: String, Codable, CaseIterable, Hashable, Sendable {
    case gold, silver, bronze

    /// The laurel for a final rank: 1 gold, 2 silver, 3 bronze.
    public init?(rank: Int) {
        switch rank {
        case 1: self = .gold
        case 2: self = .silver
        case 3: self = .bronze
        default: return nil
        }
    }
}

/// Who can find and join a crew. Both kinds can be ranked and featured.
public enum CrewVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case `public`
    case `private`
}

/// A member's pet as crew pages show it: the same fields and ids as a Party
/// profile, so `PartyPetAppearance` draws it.
public struct CrewPet: Codable, Hashable, Sendable {
    public var petName: String
    public var species: String
    public var breed: String
    public var colors: [String]
    public var costume: String
    public var accessories: [String]

    public init(petName: String, species: String, breed: String, colors: [String] = [], costume: String = "none",
                accessories: [String] = []) {
        self.petName = petName
        self.species = species
        self.breed = breed
        self.colors = colors
        self.costume = costume
        self.accessories = accessories
    }
}

/// One member on a crew page. Members are addressed by an opaque `ref`, never
/// a friend code, so a crew on the board is not a directory of codes.
public struct CrewMember: Codable, Hashable, Sendable, Identifiable {
    public var ref: String
    public var name: String
    /// Nil when the member hid their pet from crew pages.
    public var pet: CrewPet?
    /// The member's Study Level, once the server sends it.
    public var studyLevel: Int?
    public var badges: [String]
    public var weekMinutes: Int
    public var owner: Bool
    public var me: Bool

    public var id: String { ref }

    public init(ref: String, name: String, pet: CrewPet?, studyLevel: Int? = nil, badges: [String] = [],
                weekMinutes: Int = 0, owner: Bool = false, me: Bool = false) {
        self.ref = ref
        self.name = name
        self.pet = pet
        self.studyLevel = studyLevel
        self.badges = badges
        self.weekMinutes = weekMinutes
        self.owner = owner
        self.me = me
    }

    private enum CodingKeys: String, CodingKey {
        case ref, name, pet, studyLevel, badges, weekMinutes, owner, me
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ref = try container.decode(String.self, forKey: .ref)
        name = try container.decode(String.self, forKey: .name)
        pet = try container.decodeIfPresent(CrewPet.self, forKey: .pet)
        studyLevel = try container.decodeIfPresent(Int.self, forKey: .studyLevel)
        badges = try container.decodeIfPresent([String].self, forKey: .badges) ?? []
        weekMinutes = try container.decodeIfPresent(Int.self, forKey: .weekMinutes) ?? 0
        owner = try container.decodeIfPresent(Bool.self, forKey: .owner) ?? false
        me = try container.decodeIfPresent(Bool.self, forKey: .me) ?? false
    }

    /// The member's pet as a Party profile, so the shared Party appearance
    /// code draws it; nil when hidden.
    public var partyProfile: PartyProfile? {
        guard let pet else { return nil }
        return PartyProfile(code: ref, name: name, petName: pet.petName, species: pet.species, breed: pet.breed,
                            colors: pet.colors, costume: pet.costume, accessories: pet.accessories, badges: badges)
    }
}

/// What every list shows of a crew.
public struct CrewSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    /// The crest's frame, a `CrewCatalog.frames` id; unknown ids draw as the first frame.
    public var frame: String
    /// The crest's emblem, a `CrewCatalog.emblems` id; unknown ids draw as the first emblem.
    public var emblem: String
    /// The crest's color, a `CrewCatalog.colors` id; unknown ids draw as the first color.
    public var color: String
    public var visibility: CrewVisibility
    /// What the crew wears this week, or, on the featured board, the tier it won.
    public var laurel: CrewLaurel?
    /// Every top 3 finish ever.
    public var trophies: Int
    public var memberCount: Int
    public var maxMembers: Int
    public var weekMinutes: Int

    public init(id: String, name: String, description: String = "", frame: String, emblem: String, color: String,
                visibility: CrewVisibility, laurel: CrewLaurel? = nil, trophies: Int = 0, memberCount: Int,
                maxMembers: Int = CrewCatalog.maxMembers, weekMinutes: Int = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.frame = frame
        self.emblem = emblem
        self.color = color
        self.visibility = visibility
        self.laurel = laurel
        self.trophies = trophies
        self.memberCount = memberCount
        self.maxMembers = maxMembers
        self.weekMinutes = weekMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, frame, emblem, color, visibility, laurel, trophies, memberCount, maxMembers, weekMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        frame = try container.decode(String.self, forKey: .frame)
        emblem = try container.decode(String.self, forKey: .emblem)
        color = try container.decode(String.self, forKey: .color)
        // An unknown visibility from a newer server reads as private: never
        // offer a Join button the server would refuse.
        visibility = (try? container.decode(CrewVisibility.self, forKey: .visibility)) ?? .private
        laurel = try? container.decodeIfPresent(CrewLaurel.self, forKey: .laurel)
        trophies = try container.decodeIfPresent(Int.self, forKey: .trophies) ?? 0
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        maxMembers = try container.decodeIfPresent(Int.self, forKey: .maxMembers) ?? CrewCatalog.maxMembers
        weekMinutes = try container.decodeIfPresent(Int.self, forKey: .weekMinutes) ?? 0
    }

    public var isFull: Bool { memberCount >= maxMembers }

    public var crest: CrewCrest { CrewCrest(self) }

    /// Trophy pips on the crest: one per top 3 finish, at most three.
    public var pips: Int { min(trophies, CrewCrestArt.maxPips) }
}

/// Gold, silver and bronze finishes so far.
public struct CrewMedals: Codable, Hashable, Sendable {
    public var gold: Int
    public var silver: Int
    public var bronze: Int

    public init(gold: Int = 0, silver: Int = 0, bronze: Int = 0) {
        self.gold = gold
        self.silver = silver
        self.bronze = bronze
    }
}

/// A crew page: the summary, its members and what I may do there.
public struct CrewDetail: Codable, Hashable, Sendable, Identifiable {
    public var summary: CrewSummary
    public var createdAt: Date
    public var medals: CrewMedals
    /// This week's live rank among all crews; nil with no minutes yet.
    public var rank: Int?
    public var members: [CrewMember]
    /// I belong to it.
    public var mine: Bool
    /// I own it.
    public var owner: Bool
    /// Only members get it.
    public var inviteCode: String?
    /// The maintainer hid it from the board and Find; only members are told.
    public var hidden: Bool

    public var id: String { summary.id }

    public init(summary: CrewSummary, createdAt: Date, medals: CrewMedals = CrewMedals(), rank: Int? = nil,
                members: [CrewMember], mine: Bool, owner: Bool, inviteCode: String? = nil, hidden: Bool = false) {
        self.summary = summary
        self.createdAt = createdAt
        self.medals = medals
        self.rank = rank
        self.members = members
        self.mine = mine
        self.owner = owner
        self.inviteCode = inviteCode
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt, medals, rank, members, mine, owner, inviteCode, hidden
    }

    public init(from decoder: any Decoder) throws {
        summary = try CrewSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        medals = try container.decodeIfPresent(CrewMedals.self, forKey: .medals) ?? CrewMedals()
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        members = try container.decode([CrewMember].self, forKey: .members)
        mine = try container.decodeIfPresent(Bool.self, forKey: .mine) ?? false
        owner = try container.decodeIfPresent(Bool.self, forKey: .owner) ?? false
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        try summary.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(medals, forKey: .medals)
        try container.encode(rank, forKey: .rank)
        try container.encode(members, forKey: .members)
        try container.encode(mine, forKey: .mine)
        try container.encode(owner, forKey: .owner)
        try container.encode(inviteCode, forKey: .inviteCode)
        try container.encode(hidden, forKey: .hidden)
    }

    /// My own member row, when I belong.
    public var me: CrewMember? { members.first(where: \.me) }
}

/// One place on the board.
public struct CrewBoardEntry: Codable, Hashable, Sendable, Identifiable {
    public var rank: Int
    public var minutes: Int
    public var crew: CrewSummary

    public var id: String { crew.id }

    public init(rank: Int, minutes: Int, crew: CrewSummary) {
        self.rank = rank
        self.minutes = minutes
        self.crew = crew
    }
}

/// A finished week's frozen top 3.
public struct CrewFeatured: Codable, Hashable, Sendable {
    public var week: CrewWeek
    public var entries: [CrewBoardEntry]

    public init(week: CrewWeek, entries: [CrewBoardEntry]) {
        self.week = week
        self.entries = entries
    }
}

/// `GET /v1/crews/board`: this week's live top 3 and last week's winners.
public struct CrewBoard: Codable, Hashable, Sendable {
    public var week: CrewWeek
    public var top: [CrewBoardEntry]
    public var featured: CrewFeatured?

    public init(week: CrewWeek, top: [CrewBoardEntry], featured: CrewFeatured?) {
        self.week = week
        self.top = top
        self.featured = featured
    }
}

/// What I send to create or edit a crew. Every field of an edit is
/// optional: nil keeps the server's value.
public struct CrewDraft: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public var frame: String?
    public var emblem: String?
    public var color: String?
    public var visibility: CrewVisibility?

    public init(name: String? = nil, description: String? = nil, frame: String? = nil, emblem: String? = nil,
                color: String? = nil, visibility: CrewVisibility? = nil) {
        self.name = name
        self.description = description
        self.frame = frame
        self.emblem = emblem
        self.color = color
        self.visibility = visibility
    }
}

/// One finished focus stretch, as the server credits it.
public struct CrewSession: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var minutes: Int

    public init(start: Date, end: Date, minutes: Int) {
        self.start = start
        self.end = end
        self.minutes = minutes
    }
}

/// What the server did with one reported session.
public enum CrewSessionStatus: Hashable, Sendable, Codable {
    case credited, capped, duplicate, overlap, future, invalid, weekClosed, noCrew
    /// A status this app does not know; treated as answered.
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "credited": self = .credited
        case "capped": self = .capped
        case "duplicate": self = .duplicate
        case "overlap": self = .overlap
        case "future": self = .future
        case "invalid": self = .invalid
        case "week_closed": self = .weekClosed
        case "no_crew": self = .noCrew
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .credited: "credited"
        case .capped: "capped"
        case .duplicate: "duplicate"
        case .overlap: "overlap"
        case .future: "future"
        case .invalid: "invalid"
        case .weekClosed: "week_closed"
        case .noCrew: "no_crew"
        case .other(let raw): raw
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct CrewSessionResult: Codable, Hashable, Sendable {
    public var status: CrewSessionStatus
    public var credited: Int

    public init(status: CrewSessionStatus, credited: Int) {
        self.status = status
        self.credited = credited
    }
}

/// `POST /v1/crews/sessions`.
public struct CrewSessionsReply: Codable, Hashable, Sendable {
    public var results: [CrewSessionResult]
    public var week: CrewWeek
    public var crewMinutes: Int?
    public var myMinutes: Int

    public init(results: [CrewSessionResult], week: CrewWeek, crewMinutes: Int?, myMinutes: Int) {
        self.results = results
        self.week = week
        self.crewMinutes = crewMinutes
        self.myMinutes = myMinutes
    }
}

/// Why I report a crew or one of its members.
public enum CrewReportReason: String, Codable, CaseIterable, Hashable, Sendable {
    case inappropriateName = "inappropriate_name"
    case harassment
    case spam
    case cheating
    case other

    public var title: String {
        switch self {
        case .inappropriateName: String(localized: "Inappropriate name", bundle: .tabbi)
        case .harassment: String(localized: "Harassment", bundle: .tabbi)
        case .spam: String(localized: "Spam", bundle: .tabbi)
        case .cheating: String(localized: "Cheating", bundle: .tabbi)
        case .other: String(localized: "Other", bundle: .tabbi)
        }
    }
}

/// Crew invite codes: 7 characters from the friend code alphabet.
public enum CrewCode {
    public static let inviteLength = 7
    public static let idLength = 10

    public static func invite(_ text: String) -> String? { PartyCode.normalize(text, length: inviteLength) }
    public static func crewID(_ text: String) -> String? { PartyCode.normalize(text, length: idLength) }

    /// The invite code in pasted text (a code, or a whole invite message).
    public static func findInvite(in text: String) -> String? {
        if let link = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let invite = CrewInvite(url: link) {
            return invite.code
        }
        for word in text.split(whereSeparator: \.isWhitespace) {
            if let link = URL(string: String(word)), let invite = CrewInvite(url: link) { return invite.code }
        }
        return PartyCode.find(in: text, length: inviteLength)
    }
}

/// One crew in the all-time Hall of Fame: its medals from every weekly top 3
/// finish, in Olympic order.
public struct CrewHallEntry: Codable, Hashable, Sendable, Identifiable {
    /// Competition rank over the whole order; equal tallies reached at the same time share it.
    public var rank: Int
    public var medals: CrewMedals
    /// When the crew reached its current tally (the end of that week); earlier wins a tie.
    public var reachedAt: Date
    public var crew: CrewSummary

    public var id: String { crew.id }

    public init(rank: Int, medals: CrewMedals, reachedAt: Date, crew: CrewSummary) {
        self.rank = rank
        self.medals = medals
        self.reachedAt = reachedAt
        self.crew = crew
    }
}

/// `GET /v1/crews/hall`: one page of the Hall of Fame and the cursor for the
/// next, nil at the end.
public struct CrewHallPage: Codable, Hashable, Sendable {
    public var entries: [CrewHallEntry]
    public var next: String?

    public init(entries: [CrewHallEntry], next: String?) {
        self.entries = entries
        self.next = next
    }
}
