import Foundation

/// What the Party tab's Crew section shows, kept apart from the network so
/// it can be tested and rendered in demo snapshots.
public struct CrewsState: Equatable, Sendable {
    /// What the Crew section's main card shows; the weekly top 3 sits
    /// beside it in every section.
    public enum Section: String, CaseIterable, Equatable, Sendable {
        case mine, find, create
    }

    public var section: Section
    /// The current week, from the last reply (or computed until one comes).
    public var week: CrewWeek
    /// My crew; nil when I am in none. Only meaningful once `mineLoaded`.
    public var mine: CrewDetail?
    public var mineLoaded: Bool
    public var board: CrewBoard?
    /// The top 3 card shows last week's frozen winners instead of the live race.
    public var showsLastWeek: Bool
    public var query: String
    /// Find's results for `query`; nil until the first answer.
    public var results: [CrewSummary]?
    /// A crew page opened from the top 3 or Find, over the section that opened it.
    public var viewing: CrewDetail?
    /// The owner is editing my crew (the create form, filled in).
    public var editing: Bool
    /// An invite link's code, waiting for the user to confirm joining.
    public var invite: String?
    /// The last failure to load, shown in place of the section's content.
    public var loadError: PartyError?

    public init(section: Section = .mine, week: CrewWeek = .containing(Date()), mine: CrewDetail? = nil,
                mineLoaded: Bool = false, board: CrewBoard? = nil, showsLastWeek: Bool = false, query: String = "",
                results: [CrewSummary]? = nil, viewing: CrewDetail? = nil, editing: Bool = false, invite: String? = nil,
                loadError: PartyError? = nil) {
        self.section = section
        self.week = week
        self.mine = mine
        self.mineLoaded = mineLoaded
        self.board = board
        self.showsLastWeek = showsLastWeek
        self.query = query
        self.results = results
        self.viewing = viewing
        self.editing = editing
        self.invite = invite
        self.loadError = loadError
    }

    public var inCrew: Bool { mine != nil }

    /// The entries the top 3 card shows now: the live race, or last week's winners.
    public var boardEntries: [CrewBoardEntry] {
        guard let board else { return [] }
        return showsLastWeek ? board.featured?.entries ?? [] : board.top
    }

    /// Moves to a section, closing any crew page and edit form.
    public mutating func show(_ section: Section) {
        self.section = section
        viewing = nil
        editing = false
    }

    /// My crew came back from the server (or I left it).
    public mutating func didLoadMine(_ crew: CrewDetail?, week: CrewWeek) {
        mine = crew
        self.week = week
        mineLoaded = true
        loadError = nil
        if crew == nil { editing = false }
        // A crew page of my own crew follows the fresh copy.
        if let viewing, viewing.id == crew?.id { self.viewing = crew }
    }

    public mutating func didLoadBoard(_ board: CrewBoard) {
        self.board = board
        week = board.week
        loadError = nil
        // Last week's winners only exist once a week has frozen.
        if board.featured == nil { showsLastWeek = false }
    }
}

/// Checks a crew's name and description as they are typed, with the same
/// filter the server applies (`PartyNameFilter`).
public enum CrewDraftCheck {
    public enum Problem: Equatable, Sendable {
        case nameEmpty
        case nameTooLong
        case nameNotAllowed
        case descriptionTooLong
        case descriptionNotAllowed

        public var message: String {
            switch self {
            case .nameEmpty: String(localized: "Give your crew a name.", bundle: .tabbi)
            case .nameTooLong: String(localized: "Crew names can be up to \(CrewCatalog.nameMaxLength) characters.", bundle: .tabbi)
            case .nameNotAllowed: String(localized: "That crew name isn't allowed. Please pick another.", bundle: .tabbi)
            case .descriptionTooLong:
                String(localized: "Descriptions can be up to \(CrewCatalog.descriptionMaxLength) characters.", bundle: .tabbi)
            case .descriptionNotAllowed: String(localized: "That description isn't allowed. Please change it.", bundle: .tabbi)
            }
        }
    }

    /// The first problem with a name and description, or nil when both are fine.
    public static func problem(name: String, description: String) -> Problem? {
        let name = clean(name), description = clean(description)
        if name.isEmpty { return .nameEmpty }
        if name.count > CrewCatalog.nameMaxLength { return .nameTooLong }
        if !PartyNameFilter.isAllowed(name) { return .nameNotAllowed }
        if description.count > CrewCatalog.descriptionMaxLength { return .descriptionTooLong }
        if !description.isEmpty && !PartyNameFilter.isAllowed(description) { return .descriptionNotAllowed }
        return nil
    }

    /// Text as it is sent: trimmed, with line breaks folded into spaces.
    public static func clean(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Crew errors the server names with codes Party itself does not use, as
/// one friendly sentence each; any other error keeps Party's message.
public enum CrewErrorText {
    public static func message(_ error: PartyError) -> String {
        guard case .server(let code, _) = error else {
            if error == .nameNotAllowed { return CrewDraftCheck.Problem.nameNotAllowed.message }
            return error.message
        }
        switch code {
        case "in_crew": return String(localized: "You're already in a crew. Leave it first.", bundle: .tabbi)
        case "not_in_crew": return String(localized: "You're not in a crew anymore.", bundle: .tabbi)
        case "crew_not_found": return String(localized: "That crew is gone or the code is wrong.", bundle: .tabbi)
        case "crew_full": return String(localized: "That crew is full.", bundle: .tabbi)
        case "not_owner": return String(localized: "Only the crew's owner can do that.", bundle: .tabbi)
        case "name_taken": return String(localized: "Another crew has that name. Please pick another.", bundle: .tabbi)
        case "crew_name_not_allowed": return CrewDraftCheck.Problem.nameNotAllowed.message
        case "description_not_allowed": return CrewDraftCheck.Problem.descriptionNotAllowed.message
        case "removed_from_crew": return String(localized: "You can't join that crew.", bundle: .tabbi)
        case "member_not_found": return String(localized: "That member left the crew.", bundle: .tabbi)
        case "crew_limit": return String(localized: "You've made a lot of crews today. Try again tomorrow.", bundle: .tabbi)
        default: return error.message
        }
    }
}
