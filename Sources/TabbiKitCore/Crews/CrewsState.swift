import Foundation

/// What the Party tab's Crews mode shows, kept apart from the network so it
/// can be tested and rendered in demo snapshots. The navigation follows the
/// Crews UI spec: four sections in a pill row, and at most one pushed
/// screen (a crew's page or the crest editor) over the section that opened it.
public struct CrewsState: Equatable, Sendable {
    /// The sections of the pill row, in order.
    public enum Section: String, CaseIterable, Equatable, Sendable {
        case mine, week, hall, find
    }

    /// A screen pushed over a section; one level deep.
    public enum Pushed: Equatable, Sendable {
        /// A crew's page, opened from `from`.
        case crew(CrewDetail, from: Section)
        /// The crest editor: a new crew, or the owner editing theirs.
        case editor(editing: Bool, from: Section)

        public var from: Section {
            switch self {
            case .crew(_, let from), .editor(_, let from): from
            }
        }
    }

    public var section: Section
    public var pushed: Pushed?
    /// The current week, from the last reply (or computed until one comes).
    public var week: CrewWeek
    /// My crew; nil when I am in none. Only meaningful once `mineLoaded`.
    public var mine: CrewDetail?
    public var mineLoaded: Bool
    /// My pending request to join a public crew, while I am in none.
    public var myRequest: CrewMyRequest?
    /// The weekly board, with every page of rows loaded so far.
    public var board: CrewBoard?
    /// The Hall of Fame, every page loaded so far, and the next cursor.
    public var hall: [CrewHallEntry]?
    public var hallNext: String?
    /// My crew's standing in the Hall of Fame, from its first page.
    public var hallMine: CrewHallStanding?
    public var query: String
    /// Find's results for `query`; nil until the first answer.
    public var results: [CrewSummary]?
    /// An invite link's code, waiting for the user to confirm joining.
    public var invite: String?
    /// The last failure to load, shown in place of the section's content.
    public var loadError: PartyError?

    public init(section: Section = .week, pushed: Pushed? = nil, week: CrewWeek = .containing(Date()),
                mine: CrewDetail? = nil, mineLoaded: Bool = false, myRequest: CrewMyRequest? = nil,
                board: CrewBoard? = nil, hall: [CrewHallEntry]? = nil, hallNext: String? = nil, query: String = "",
                results: [CrewSummary]? = nil, invite: String? = nil, loadError: PartyError? = nil) {
        self.section = section
        self.pushed = pushed
        self.week = week
        self.mine = mine
        self.mineLoaded = mineLoaded
        self.myRequest = myRequest
        self.board = board
        self.hall = hall
        self.hallNext = hallNext
        self.query = query
        self.results = results
        self.invite = invite
        self.loadError = loadError
    }

    public var inCrew: Bool { mine != nil }

    /// Whether I asked to join `crew` and wait for its owner.
    public func hasRequested(_ crew: String) -> Bool { myRequest?.crew.id == crew }

    /// Goes to a section, closing any pushed screen.
    public mutating func show(_ section: Section) {
        self.section = section
        pushed = nil
    }

    /// Back from a pushed screen to the section that opened it.
    public mutating func pop() {
        guard let pushed else { return }
        section = pushed.from
        self.pushed = nil
    }

    /// My crew came back from the server (or I left it).
    public mutating func didLoadMine(_ crew: CrewDetail?, week: CrewWeek, request: CrewMyRequest? = nil) {
        mine = crew
        self.week = week
        myRequest = crew == nil ? request : nil
        mineLoaded = true
        loadError = nil
        if crew == nil, case .editor(true, _) = pushed { pushed = nil }
        // A page of my own crew follows the fresh copy.
        if case .crew(let shown, let from) = pushed, let crew, shown.id == crew.id { pushed = .crew(crew, from: from) }
    }

    /// The first page of the board, or a further page of rows when `appending`.
    public mutating func didLoadBoard(_ page: CrewBoard, appending: Bool = false) {
        if appending, var board {
            board.rows += page.rows.filter { row in !board.rows.contains { $0.id == row.id } }
            board.next = page.next
            self.board = board
        } else {
            board = page
        }
        week = page.week
        loadError = nil
    }

    public mutating func didLoadHall(_ page: CrewHallPage, appending: Bool = false) {
        if appending, let loaded = hall {
            hall = loaded + page.entries.filter { entry in !loaded.contains { $0.id == entry.id } }
        } else {
            hall = page.entries
            hallMine = page.mine
        }
        hallNext = page.next
        loadError = nil
    }

    /// The week has no minutes yet: the sleeping-pet state.
    public var isQuietWeek: Bool {
        guard let board else { return false }
        return board.top.isEmpty && board.rows.isEmpty
    }

    /// Every crew on the weekly board loaded so far, in place order.
    public var weekEntries: [CrewBoardEntry] { (board?.top ?? []) + (board?.rows ?? []) }

    /// My crew's entry on the weekly board, when loaded.
    public var myWeekEntry: CrewBoardEntry? {
        guard let id = mine?.id else { return nil }
        return weekEntries.first { $0.id == id }
    }

    /// My crew in the Hall of Fame, when it has a medal and is loaded.
    public var myHallEntry: CrewHallEntry? {
        guard let id = mine?.id else { return nil }
        return hall?.first { $0.id == id }
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
        case "request_not_found": return String(localized: "That request is no longer waiting.", bundle: .tabbi)
        case "requests_full": return String(localized: "That crew has a lot of requests waiting. Try again later.", bundle: .tabbi)
        case "request_limit": return String(localized: "You've asked a lot of crews today. Try again tomorrow.", bundle: .tabbi)
        case "crew_limit": return String(localized: "You've made a lot of crews today. Try again tomorrow.", bundle: .tabbi)
        default: return error.message
        }
    }
}
