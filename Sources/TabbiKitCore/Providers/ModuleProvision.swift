import Foundation

/// Something to do today that a module contributes to Today and the ticker:
/// a checklist item, "Review 84 Anki cards", or later a LeetCode daily
/// problem. The `TaskSource` role of a module.
public struct ProvidedTask: Identifiable, Hashable, Sendable {
    /// Stable within its source module, so a refresh updates the same row.
    public var id: String
    /// The module that provided it; set by `ProviderSnapshot` when merging.
    public var source: ModuleID
    public var title: String
    public var isDone: Bool
    /// A rough size for Plan My Day, when the source knows one.
    public var estimatedMinutes: Int?

    public init(id: String, source: ModuleID, title: String, isDone: Bool = false, estimatedMinutes: Int? = nil) {
        self.id = id
        self.source = source
        self.title = title
        self.isDone = isDone
        self.estimatedMinutes = estimatedMinutes
    }
}

/// A one-click action a module offers on something it shares, such as
/// Anki's "Study Pharm Sketchy" on its reviews goal. Today's row and the
/// closed notch's preview run it on click (and still open the module, which
/// shows how it goes), so a module's most common action works from anywhere
/// without the shared views knowing what it does. The app hands `id` back
/// to the module that shared the item.
public struct ProvidedAction: Hashable, Sendable {
    /// Meaningful only to the module that offered it.
    public var id: String
    /// What a click does, e.g. "Study Pharm Sketchy", for tooltips.
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// A countable goal for today, such as Anki cards due or practice questions
/// answered. The `ProgressSource` role of a module: Today and the ticker can
/// show it without knowing which module it came from.
public struct ProgressItem: Identifiable, Hashable, Sendable {
    /// Stable within its source module.
    public var id: String
    /// The module that provided it; set by `ProviderSnapshot` when merging.
    public var source: ModuleID
    public var title: String
    public var completed: Int
    /// Today's goal; 0 means there is nothing to do today.
    public var target: Int
    /// Plural noun for the counts, e.g. "cards".
    public var unit: String
    /// What a click on the goal does, beyond opening its module.
    public var action: ProvidedAction?

    public init(id: String, source: ModuleID, title: String, completed: Int, target: Int, unit: String,
                action: ProvidedAction? = nil) {
        self.id = id
        self.source = source
        self.title = title
        self.completed = completed
        self.target = target
        self.unit = unit
        self.action = action
    }

    public var remaining: Int { max(target - completed, 0) }
    public var isComplete: Bool { remaining == 0 }
    /// Share of the goal done, clamped to 0...1; a goal of 0 counts as done.
    public var fraction: Double {
        target > 0 ? min(max(Double(completed) / Double(target), 0), 1) : 1
    }
}

/// Today's study time and rewards so far, such as a study timer's log. The
/// `StudySource` role of a module: Wrap Up shows it without knowing which
/// module ran the sessions.
public struct StudyDayTally: Hashable, Codable, Sendable {
    /// Minutes studied today, finished or not.
    public var minutes: Int
    /// Study sessions that ran to their end today.
    public var sessions: Int
    /// Points earned today (see `PetPointsRules`).
    public var points: Int

    public init(minutes: Int = 0, sessions: Int = 0, points: Int = 0) {
        self.minutes = minutes
        self.sessions = sessions
        self.points = points
    }

    /// Demo data: three finished 50-minute blocks and an unfinished 35, with
    /// points worked out by the real `PetPointsRules`.
    public static let sample: StudyDayTally = {
        let blocks = [(50, true), (50, true), (50, true), (35, false)]
        return StudyDayTally(
            minutes: blocks.reduce(0) { $0 + $1.0 },
            sessions: blocks.filter(\.1).count,
            points: blocks.reduce(0) { $0 + PetPointsRules.points(forMinutes: $1.0, completed: $1.1) }
        )
    }()

    /// Adds two modules' tallies.
    public static func + (lhs: StudyDayTally, rhs: StudyDayTally) -> StudyDayTally {
        StudyDayTally(minutes: lhs.minutes + rhs.minutes, sessions: lhs.sessions + rhs.sessions,
                      points: lhs.points + rhs.points)
    }
}

/// One pet in a `ProvidedParty`.
public struct ProvidedPartyPet: Identifiable, Hashable, Sendable {
    /// Stable for the person, e.g. their friend code.
    public var id: String
    public var name: String
    public var pet: PetProfile
    /// Offline, so their pet dozes.
    public var isAway: Bool

    public init(id: String, name: String, pet: PetProfile, isAway: Bool = false) {
        self.id = id
        self.name = name
        self.pet = pet
        self.isAway = isAway
    }
}

/// The study party the user is in, so the closed notch can show the other
/// members' pets beside the user's own. The `PartySource` role.
public struct ProvidedParty: Hashable, Sendable {
    /// The user's pet first, then the other members' in roster order.
    public var pets: [ProvidedPartyPet]

    public init(pets: [ProvidedPartyPet]) {
        self.pets = pets
    }

    /// Everyone in the party, the user included.
    public var memberCount: Int { pets.count }
}

/// What one module offers the rest of the app right now. Each field is one
/// provider role; a module fills only the ones it has:
/// - `tasks`: TaskSource, things to do today.
/// - `events`: EventSource, calendar events.
/// - `progress`: ProgressSource, today's study or practice goals.
/// - `focus`: FocusState, the focus or break clock the module runs, in
///   the engine-neutral `ProvidedFocus` shape.
/// - `study`: StudySource, today's study minutes, sessions and points.
/// - `pet`: PetSource, the study pet the closed notch shows.
/// - `party`: PartySource, the study party the user is in.
/// - `highlights`: HighlightSource, short lines for the closed-notch ticker.
/// - `isPlaying`: MediaSource, music is playing, so the closed notch shows
///   the music wings (artwork and equalizer).
///
/// Modules publish a new value whenever their data changes, and
/// `ProviderSnapshot` merges all enabled modules' values, so consumers such
/// as the ticker never depend on a specific module.
public struct ModuleProvision: Equatable, Sendable {
    public var tasks: [ProvidedTask]
    public var events: [UpcomingEvent]
    public var progress: [ProgressItem]
    public var focus: ProvidedFocus?
    public var study: StudyDayTally?
    public var pet: PetPresence?
    public var party: ProvidedParty?
    public var highlights: [TickerHighlight]
    public var isPlaying: Bool

    public init(
        tasks: [ProvidedTask] = [],
        events: [UpcomingEvent] = [],
        progress: [ProgressItem] = [],
        focus: ProvidedFocus? = nil,
        study: StudyDayTally? = nil,
        pet: PetPresence? = nil,
        party: ProvidedParty? = nil,
        highlights: [TickerHighlight] = [],
        isPlaying: Bool = false
    ) {
        self.tasks = tasks
        self.events = events
        self.progress = progress
        self.focus = focus
        self.study = study
        self.pet = pet
        self.party = party
        self.highlights = highlights
        self.isPlaying = isPlaying
    }

    public static let empty = ModuleProvision()
}

/// Everything the enabled modules provide, merged into one value.
///
/// Built from provisions in tab order, so the user's ordering decides whose
/// tasks come first; which focus clock wins when two run is `focus`'s rule.
public struct ProviderSnapshot: Equatable, Sendable {
    /// Tasks in tab order, then each module's own order.
    public private(set) var tasks: [ProvidedTask] = []
    /// Events from every module, by start time. Unlike tasks and progress,
    /// events are keyed by id alone, across modules: an event id is the
    /// calendar's own identifier, so two modules that read the same
    /// calendar list a meeting once, and the first in tab order wins. Ids
    /// that are not calendar identifiers should carry a module prefix so
    /// they never merge by accident.
    public private(set) var events: [UpcomingEvent] = []
    public private(set) var progress: [ProgressItem] = []
    /// The one clock the app shows when several modules run one (say the
    /// Pomodoro and a Study block): a running clock beats a paused one,
    /// which beats an idle one. Among running clocks the most recently
    /// started or resumed one wins (`focusStarts`), since that is the one
    /// the user just turned to; the rest, and clocks with no known start,
    /// go by tab order. Its `source` is the module running it, so a click
    /// on its preview opens that module and consumers can tell one
    /// module's clock from another's.
    public private(set) var focus: ProvidedFocus?
    /// Every module's study tally added up; nil when no module keeps one.
    public private(set) var study: StudyDayTally?
    /// The first pet in tab order.
    public private(set) var pet: PetPresence?
    /// The first party in tab order.
    public private(set) var party: ProvidedParty?
    /// Highlights in tab order, then each module's own order.
    public private(set) var highlights: [TickerHighlight] = []
    /// Whether any module is playing music.
    public private(set) var isPlaying = false

    public init() {}

    /// Merges `provisions` from modules listed in tab order. Each item's
    /// `source` is set to the module that provided it, and a repeated
    /// `(source, id)` keeps only its first occurrence. Events are the one
    /// exception: they merge by id across modules (see `events`).
    /// `focusStarts` says when each module's focus clock last started or
    /// resumed running, which decides between two running clocks.
    public init(
        _ provisions: [(module: ModuleID, provision: ModuleProvision)],
        focusStarts: [ModuleID: Date] = [:]
    ) {
        var taskKeys = Set<[String]>()
        var progressKeys = Set<[String]>()
        var highlightKeys = Set<[String]>()
        var eventIDs = Set<String>()
        var clocks: [ProvidedFocus] = []
        for (module, provision) in provisions {
            for var task in provision.tasks where taskKeys.insert([module.rawValue, task.id]).inserted {
                task.source = module
                tasks.append(task)
            }
            for var item in provision.progress where progressKeys.insert([module.rawValue, item.id]).inserted {
                item.source = module
                progress.append(item)
            }
            for var highlight in provision.highlights
            where highlightKeys.insert([module.rawValue, highlight.id]).inserted {
                highlight.source = module
                highlights.append(highlight)
            }
            if provision.isPlaying { isPlaying = true }
            if pet == nil { pet = provision.pet }
            events += provision.events.filter { eventIDs.insert($0.id).inserted }
            if let tally = provision.study { study = (study ?? StudyDayTally()) + tally }
            if party == nil { party = provision.party }
            if var clock = provision.focus {
                clock.source = module
                clocks.append(clock)
            }
        }
        focus = Self.leadingClock(clocks, focusStarts: focusStarts)
        // Stable, so events with equal starts keep their tab order.
        events = events.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// The clock `focus` picks from `clocks`, which are in tab order.
    private static func leadingClock(_ clocks: [ProvidedFocus], focusStarts: [ModuleID: Date]) -> ProvidedFocus? {
        func rank(_ clock: ProvidedFocus) -> Int {
            clock.isRunning ? 2 : clock.isPaused ? 1 : 0
        }
        func start(_ clock: ProvidedFocus) -> Date {
            clock.isRunning ? focusStarts[clock.source] ?? .distantPast : .distantPast
        }
        // The negated offset makes an earlier tab win a tie.
        return clocks.enumerated().max { lhs, rhs in
            (rank(lhs.element), start(lhs.element), -lhs.offset) < (rank(rhs.element), start(rhs.element), -rhs.offset)
        }?.element
    }

    /// Tasks not done yet, in order.
    public var openTasks: [ProvidedTask] { tasks.filter { !$0.isDone } }
}
