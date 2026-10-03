import Foundation

extension StudyPhaseRecord {
    /// Phases shorter than this (a start tapped by mistake, an instant skip)
    /// are not worth logging.
    public static let minimumLoggedDuration: TimeInterval = 60

    /// The activity record for this phase: study time (focus or question
    /// review) as `focusCompleted`, a break as `breakTaken`, with the minutes
    /// the clock ran. Nil for phases under a minute. Sprint cards go in the
    /// metadata only, since the Anki module logs the cards themselves.
    public func activityRecord(source: ModuleID) -> ActivityRecord? {
        guard activeDuration.isFinite, activeDuration >= Self.minimumLoggedDuration else { return nil }
        var metadata = [ActivityMetadata.method: method.rawValue, ActivityMetadata.outcome: outcome.rawValue,
                        "phase": phase.rawValue]
        if let cards { metadata["cards"] = String(cards) }
        return ActivityRecord(
            source: source, kind: phase.isBreak ? .breakTaken : .focusCompleted,
            start: startedAt, end: endedAt, quantity: activeDuration / 60, unit: .minutes, metadata: metadata
        )
    }
}
