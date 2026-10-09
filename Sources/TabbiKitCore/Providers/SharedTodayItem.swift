import Foundation

/// One row Today shows for another module's task or progress goal, such as
/// "Anki reviews, 320 cards left". Today lists these above its own checklist,
/// so a new provider (Anki, later LeetCode or LSAT) appears there without
/// Today knowing about it.
public struct SharedTodayItem: Identifiable, Hashable, Sendable {
    /// Unique across modules: the source id plus the item's own id.
    public var id: String
    /// The module to open when the row is clicked.
    public var source: ModuleID
    public var title: String
    /// A short count such as "320 cards left", or nil for a plain task.
    public var detail: String?
    /// Share done, 0...1, for a progress bar; nil for a plain task.
    public var fraction: Double?
    public var isDone: Bool
    /// What a click runs besides opening `source`, e.g. Anki's "Study
    /// Pharm Sketchy".
    public var action: ProvidedAction?

    public init(id: String, source: ModuleID, title: String, detail: String?, fraction: Double?, isDone: Bool,
                action: ProvidedAction? = nil) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.fraction = fraction
        self.isDone = isDone
        self.action = action
    }
}

extension ProviderSnapshot {
    /// What modules other than `module` share for today: progress goals
    /// first (they are the day's big blocks), then tasks, each in tab order.
    /// Goals with nothing to do today are left out, since they would only
    /// add a finished row the user never saw open. A goal's detail is what
    /// is left ("320 cards left") until it is met, then the day's total.
    public func sharedTodayItems(excluding module: ModuleID) -> [SharedTodayItem] {
        let goals = progress
            .filter { $0.source != module && $0.target > 0 }
            .map { item in
                SharedTodayItem(
                    id: "\(item.source.rawValue)/progress/\(item.id)", source: item.source, title: item.title,
                    detail: item.isComplete
                        ? item.amount(item.target)
                        : item.remainingText,
                    fraction: item.fraction, isDone: item.isComplete, action: item.action
                )
            }
        let tasks = tasks
            .filter { $0.source != module }
            .map { task in
                SharedTodayItem(
                    id: "\(task.source.rawValue)/task/\(task.id)", source: task.source, title: task.title,
                    detail: task.estimatedMinutes.map(DurationFormat.minutes), fraction: nil, isDone: task.isDone
                )
            }
        return goals + tasks
    }
}

extension ProviderSnapshot {
    /// Unfinished work that modules other than `module` share, phrased for
    /// Plan My Day's prompt, e.g. "Anki reviews (320 cards left)" or
    /// "LeetCode daily (about 30 min)". Same order as `sharedTodayItems`,
    /// so Claude sees the day's big goals first.
    public func plannableWork(excluding module: ModuleID) -> [String] {
        let goals = progress
            .filter { $0.source != module && !$0.isComplete }
            .map { "\($0.title) (\($0.remainingText))" }
        let tasks = openTasks
            .filter { $0.source != module }
            .map { task in task.estimatedMinutes.map { "\(task.title) (about \($0) min)" } ?? task.title }
        return goals + tasks
    }
}
