import Foundation

extension ProviderSnapshot {
    /// The unit a progress goal counts flashcards in, e.g. Anki's reviews.
    public static let cardUnit = "cards"

    /// Cards reviewed today across the card goals that modules other than
    /// `module` share, or nil when none does (e.g. Anki is off or not
    /// connected). An Anki sprint feeds this to
    /// `StudySession.recordReviewedToday(_:at:)`, so the Study timer counts
    /// cards without knowing which module reviews them. Several card
    /// sources add up; one going away just lowers the total, which the
    /// session treats as a new baseline.
    public func cardsReviewedToday(excluding module: ModuleID) -> Int? {
        let goals = progress.filter { $0.source != module && $0.unit == Self.cardUnit }
        guard !goals.isEmpty else { return nil }
        return goals.reduce(0) { $0 + max($1.completed, 0) }
    }
}
