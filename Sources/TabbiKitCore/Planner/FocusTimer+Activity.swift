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
    /// would read "137 sessions" weeks in. A stretch stopped or skipped early
    /// adds study time but is no finished session.
    public static func sessionsDone(in records: [ActivityRecord], source: ModuleID) -> Int {
        records.filter { $0.source == source && $0.kind == .focusCompleted && $0.countsAsFinishedSession }.count
    }
}

extension FocusStop {
    /// The activity record for a focus phase stopped or skipped early: the
    /// minutes actually focused, ending when it was cut short. Its outcome
    /// (`abandoned` or `skipped`) adds study time without counting as a
    /// finished session. Nil under `StudyPhaseRecord.minimumLoggedDuration`, like a
    /// start tapped by mistake.
    public func activityRecord(source: ModuleID) -> ActivityRecord? {
        guard focused.isFinite, focused >= StudyPhaseRecord.minimumLoggedDuration else { return nil }
        return ActivityRecord(
            source: source, kind: .focusCompleted,
            start: endedAt.addingTimeInterval(-focused), end: endedAt,
            quantity: focused / 60, unit: .minutes,
            metadata: [ActivityMetadata.method: "pomodoro", ActivityMetadata.outcome: outcome.rawValue]
        )
    }
}
