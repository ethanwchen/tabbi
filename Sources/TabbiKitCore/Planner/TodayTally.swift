import Foundation

/// How much of today is done, counting the user's own checklist and the
/// rows other modules share (say, Anki reviews) alike. A shared goal counts
/// as one item that checks itself once its work hits zero, so finishing the
/// day's reviews moves the header the same way ticking a task does.
public struct TodayTally: Hashable, Sendable {
    public let doneCount: Int
    public let totalCount: Int

    public init(day: PlannerDay, shared: [SharedTodayItem]) {
        doneCount = day.doneCount + shared.lazy.filter(\.isDone).count
        totalCount = day.items.count + shared.count
    }

    /// Fraction of items done, 0 when there is nothing to do.
    public var progress: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }

    /// Short caption for the panel header, e.g. "3 of 6 done".
    public var summary: String {
        if totalCount == 0 { return "Nothing planned" }
        if doneCount == totalCount { return "All \(totalCount) done" }
        return "\(doneCount) of \(totalCount) done"
    }

    /// The summary for a narrow header (Compact panel), e.g. "3/6".
    public var shortSummary: String {
        if totalCount == 0 { return "Nothing planned" }
        return "\(doneCount)/\(totalCount)"
    }
}
