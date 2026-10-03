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

    public init(id: String, source: ModuleID, title: String, completed: Int, target: Int, unit: String) {
        self.id = id
        self.source = source
        self.title = title
        self.completed = completed
        self.target = target
        self.unit = unit
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

/// What one module offers the rest of the app right now. Each field is one
/// provider role; a module fills only the ones it has:
/// - `tasks`: TaskSource, things to do today.
/// - `events`: EventSource, calendar events.
/// - `progress`: ProgressSource, today's study or practice goals.
/// - `focus`: FocusState, the focus timer the module runs.
/// - `study`: StudySource, today's study minutes, sessions and points.
/// - `pet`: PetSource, the study pet the closed notch shows.
///
/// Modules publish a new value whenever their data changes, and
/// `ProviderSnapshot` merges all enabled modules' values, so consumers such
/// as the ticker never depend on a specific module.
public struct ModuleProvision: Equatable, Sendable {
    public var tasks: [ProvidedTask]
    public var events: [UpcomingEvent]
    public var progress: [ProgressItem]
    public var focus: FocusTimer?
    public var study: StudyDayTally?
    public var pet: PetPresence?

    public init(
        tasks: [ProvidedTask] = [],
        events: [UpcomingEvent] = [],
        progress: [ProgressItem] = [],
        focus: FocusTimer? = nil,
        study: StudyDayTally? = nil,
        pet: PetPresence? = nil
    ) {
        self.tasks = tasks
        self.events = events
        self.progress = progress
        self.focus = focus
        self.study = study
        self.pet = pet
    }

    public static let empty = ModuleProvision()
}

/// Everything the enabled modules provide, merged into one value.
///
/// Built from provisions in tab order, so the user's ordering decides whose
/// tasks come first and whose focus timer wins when two are active.
public struct ProviderSnapshot: Equatable, Sendable {
    /// Tasks in tab order, then each module's own order.
    public private(set) var tasks: [ProvidedTask] = []
    /// Events from every module, by start time; a repeated id keeps the first.
    public private(set) var events: [UpcomingEvent] = []
    public private(set) var progress: [ProgressItem] = []
    /// A running or paused timer beats an idle one; ties go to tab order.
    public private(set) var focus: FocusTimer?
    /// Every module's study tally added up; nil when no module keeps one.
    public private(set) var study: StudyDayTally?
    /// The first pet in tab order.
    public private(set) var pet: PetPresence?

    public init() {}

    /// Merges `provisions` from modules listed in tab order. Each item's
    /// `source` is set to the module that provided it, and a repeated
    /// `(source, id)` keeps only its first occurrence.
    public init(_ provisions: [(module: ModuleID, provision: ModuleProvision)]) {
        var taskKeys = Set<[String]>()
        var progressKeys = Set<[String]>()
        var eventIDs = Set<String>()
        var activeFocus: FocusTimer?
        for (module, provision) in provisions {
            for var task in provision.tasks where taskKeys.insert([module.rawValue, task.id]).inserted {
                task.source = module
                tasks.append(task)
            }
            for var item in provision.progress where progressKeys.insert([module.rawValue, item.id]).inserted {
                item.source = module
                progress.append(item)
            }
            if pet == nil { pet = provision.pet }
            events += provision.events.filter { eventIDs.insert($0.id).inserted }
            if let tally = provision.study { study = (study ?? StudyDayTally()) + tally }
            if let timer = provision.focus {
                if focus == nil { focus = timer }
                if activeFocus == nil, timer.isRunning || timer.isPaused { activeFocus = timer }
            }
        }
        focus = activeFocus ?? focus
        // Stable, so events with equal starts keep their tab order.
        events = events.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// Tasks not done yet, in order.
    public var openTasks: [ProvidedTask] { tasks.filter { !$0.isDone } }
}
