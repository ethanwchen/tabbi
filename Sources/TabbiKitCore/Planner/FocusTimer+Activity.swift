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

extension FocusStop {
    /// The activity record for a focus phase stopped early: the minutes
    /// actually focused, ending when it was stopped. Its outcome is
    /// `abandoned`, so it adds study time without counting as a finished
    /// session. Nil under `StudyPhaseRecord.minimumLoggedDuration`, like a
    /// start tapped by mistake.
    public func activityRecord(source: ModuleID) -> ActivityRecord? {
        guard focused.isFinite, focused >= StudyPhaseRecord.minimumLoggedDuration else { return nil }
        return ActivityRecord(
            source: source, kind: .focusCompleted,
            start: endedAt.addingTimeInterval(-focused), end: endedAt,
            quantity: focused / 60, unit: .minutes,
            metadata: [ActivityMetadata.method: "pomodoro", ActivityMetadata.outcome: StudyPhaseOutcome.abandoned.rawValue]
        )
    }
}
