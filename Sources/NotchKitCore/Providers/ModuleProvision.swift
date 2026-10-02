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

/// What one module offers the rest of the app right now. Each field is one
/// provider role; a module fills only the ones it has:
/// - `tasks`: TaskSource, things to do today.
/// - `events`: EventSource, calendar events.
/// - `progress`: ProgressSource, today's study or practice goals.
/// - `focus`: FocusState, the focus timer the module runs, and
///   `focusIsDeep`, whether the user asked for deep focus with it.
///
/// Modules publish a new value whenever their data changes, and
/// `ProviderSnapshot` merges all enabled modules' values, so consumers such
/// as the ticker never depend on a specific module.
public struct ModuleProvision: Equatable, Sendable {
    public var tasks: [ProvidedTask]
    public var events: [UpcomingEvent]
    public var progress: [ProgressItem]
    public var focus: FocusTimer?
    /// The user turned on deep focus for `focus` (Study's switch), so
    /// followers such as the pet coach can save their nudges for it.
    public var focusIsDeep: Bool

    public init(
        tasks: [ProvidedTask] = [],
        events: [UpcomingEvent] = [],
        progress: [ProgressItem] = [],
        focus: FocusTimer? = nil,
        focusIsDeep: Bool = false
    ) {
        self.tasks = tasks
        self.events = events
        self.progress = progress
        self.focus = focus
        self.focusIsDeep = focusIsDeep
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
    /// The module running `focus`, so a click on its preview opens that
    /// module and consumers can tell one module's timer from another's.
    public private(set) var focusSource: ModuleID?
    /// Whether `focus` runs in deep focus, as its module reported it.
    public private(set) var focusIsDeep = false

    public init() {}

    /// Merges `provisions` from modules listed in tab order. Each item's
    /// `source` is set to the module that provided it, and a repeated
    /// `(source, id)` keeps only its first occurrence.
    public init(_ provisions: [(module: ModuleID, provision: ModuleProvision)]) {
        var taskKeys = Set<[String]>()
        var progressKeys = Set<[String]>()
        var eventIDs = Set<String>()
        var activeFocus: (timer: FocusTimer, module: ModuleID, isDeep: Bool)?
        for (module, provision) in provisions {
            for var task in provision.tasks where taskKeys.insert([module.rawValue, task.id]).inserted {
                task.source = module
                tasks.append(task)
            }
            for var item in provision.progress where progressKeys.insert([module.rawValue, item.id]).inserted {
                item.source = module
                progress.append(item)
            }
            events += provision.events.filter { eventIDs.insert($0.id).inserted }
            if let timer = provision.focus {
                if focus == nil { (focus, focusSource, focusIsDeep) = (timer, module, provision.focusIsDeep) }
                if activeFocus == nil, timer.isRunning || timer.isPaused {
                    activeFocus = (timer, module, provision.focusIsDeep)
                }
            }
        }
        if let activeFocus { (focus, focusSource, focusIsDeep) = activeFocus }
        // Stable, so events with equal starts keep their tab order.
        events = events.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// Tasks not done yet, in order.
    public var openTasks: [ProvidedTask] { tasks.filter { !$0.isDone } }
}
