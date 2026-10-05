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
