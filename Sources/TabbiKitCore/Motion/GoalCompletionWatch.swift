import Foundation

/// Notices the moment a goal for today is reached, so the pet can put on a
/// crown (`PetCheer.Kind.crown`) for it.
///
/// It follows the `ProgressItem`s every module shares (Anki reviews, a
/// daily focus time goal) and reports a goal only when it was seen with
/// work left and is now done. So a launch, a module switched on, or a day
/// that starts with nothing due never crowns anything, and a goal crowns
/// once until it has work left again (the next day's reviews).
public struct GoalCompletionWatch: Sendable {
    private struct Key: Hashable, Sendable {
        let source: ModuleID
        let id: String
    }

    /// Whether each goal seen last time was done; nil before the first look.
    private var done: [Key: Bool]?

    public init() {}

    /// Takes the goals shared now and returns the ones reached since the
    /// last call. The first call only sets the baseline.
    public mutating func reached(in progress: [ProgressItem]) -> [ProgressItem] {
        let previous = done
        var next: [Key: Bool] = [:]
        var reached: [ProgressItem] = []
        for item in progress {
            let key = Key(source: item.source, id: item.id)
            // A goal of 0 has nothing to reach: it counts as done, quietly.
            let isDone = item.isComplete
            next[key] = isDone
            if isDone, item.target > 0, previous?[key] == false { reached.append(item) }
        }
        done = next
        return reached
    }
}
