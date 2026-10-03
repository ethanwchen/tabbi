import Foundation

extension AnkiSummary {
    /// Metadata key holding the Anki day (after the rollover hour) a
    /// `cardsReviewed` record counts toward.
    public static let activityDayKey = "ankiDay"

    /// The current Anki day, the last day of `history`.
    public var today: AnkiDay? { history.last?.day }

    /// A `cardsReviewed` record for the cards answered today that `logged`
    /// doesn't hold yet, or nil when there are none.
    ///
    /// AnkiConnect only reports a running count for the Anki day, so the
    /// module logs the difference from what it logged before for that same
    /// day. Matching on the Anki day, not the calendar day, keeps reviews
    /// done after midnight but before Anki's rollover from being counted
    /// twice, and reading back the log keeps a relaunch from doing so.
    /// Pass the records of the last two calendar days.
    public func reviewActivity(after logged: [ActivityRecord], source: ModuleID, now: Date) -> ActivityRecord? {
        guard let today else { return nil }
        let day = today.description
        let alreadyLogged = logged
            .filter { $0.source == source && $0.kind == .cardsReviewed && $0.metadata[Self.activityDayKey] == day }
            .reduce(0) { $0 + ($1.quantity ?? 0) }
        let new = Double(reviewedToday) - alreadyLogged
        guard new >= 1 else { return nil }
        return ActivityRecord(source: source, kind: .cardsReviewed, start: now, quantity: new, unit: .cards,
                              metadata: [Self.activityDayKey: day])
    }
}
