import Foundation

extension FocusPhaseCompletion {
    /// The activity record for this phase: a finished focus stretch or a
    /// break taken, lasting the configured length and ending when it ended.
    public func activityRecord(config: FocusTimerConfig, source: ModuleID) -> ActivityRecord {
        let length = config.duration(of: phase)
        return ActivityRecord(
            source: source, kind: phase == .focus ? .focusCompleted : .breakTaken,
            start: endedAt.addingTimeInterval(-length), end: endedAt,
            quantity: length / 60, unit: .minutes,
            metadata: [ActivityMetadata.method: "pomodoro", ActivityMetadata.outcome: "completed"]
        )
    }
}

extension FocusTimer {
    /// How many focus stretches `source` finished among `records` (say, one
    /// day's), for the Focus tab's daily tally. `completedFocusCount` can't
    /// serve there: it is saved with the timer and never starts over, so it
    /// would read "137 sessions" weeks in.
    public static func sessionsDone(in records: [ActivityRecord], source: ModuleID) -> Int {
        records.filter { $0.source == source && $0.kind == .focusCompleted }.count
    }
}
