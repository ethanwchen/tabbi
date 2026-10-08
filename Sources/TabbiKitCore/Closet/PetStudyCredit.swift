import Foundation

/// Points the pet earned from study sessions that just ended, for the
/// celebration: the pet hops with a heart, and when the points make a new
/// wardrobe item affordable (a "level-up") the bubble says which.
public struct PetStudyAward: Hashable, Sendable {
    /// Focus phases that ran to their end.
    public var completedSessions: Int
    /// Minutes studied across the credited sessions.
    public var minutes: Int
    public var points: Int
    /// Items that were out of reach before this award and are affordable
    /// now, cheapest first.
    public var unlocked: [PetItem]

    public init(completedSessions: Int, minutes: Int, points: Int, unlocked: [PetItem] = []) {
        self.completedSessions = completedSessions
        self.minutes = minutes
        self.points = points
        self.unlocked = unlocked
    }

    /// Whether this award is a level-up moment: something new to buy.
    public var isLevelUp: Bool { !unlocked.isEmpty }
}

extension PetCloset {
    /// Credits study points for what changed between two observations of
    /// the shared focus clock at `now`, and returns the award to celebrate.
    ///
    /// - A focus phase that ran out earns its full length plus the
    ///   completion bonus (`PetPointsRules`). Completions are counted from
    ///   `ProvidedFocus.completedFocusCount` against `PetSave.creditedFocusCount`,
    ///   so sessions that ended while the app was closed are paid once, and
    ///   the first timer the pet ever sees only sets the baseline. The
    ///   baseline belongs to one clock (`PetSave.creditedFocusSource`): when
    ///   the shared clock switches to another module's, its count only sets
    ///   a new baseline, since one clock's total says nothing about another's.
    /// - A focus phase cut short (skipped or reset) earns the minutes
    ///   actually studied, without the bonus; short ones earn nothing.
    ///
    /// Returns nil when nothing earned points.
    public mutating func credit(from old: ProvidedFocus?, to new: ProvidedFocus?, at now: Date) -> PetStudyAward? {
        guard let new else { return nil }
        let count = new.completedFocusCount
        let sameClock = save.creditedFocusSource.map { $0 == new.source } ?? true
        save.creditedFocusSource = new.source
        guard sameClock, let credited = save.creditedFocusCount, credited <= count else {
            // First sight of a timer, another clock, or its history was reset: start over.
            save.creditedFocusCount = count
            return nil
        }
        save.creditedFocusCount = count
        let before = Set(PetCloset.wardrobe.filter { state(of: $0) == .affordable })

        var award = PetStudyAward(completedSessions: 0, minutes: 0, points: 0)
        if count > credited {
            let minutes = Int((new.focusLength ?? 0) / 60)
            for _ in credited..<count {
                award.points += recordStudy(minutes: minutes, completed: true)
            }
            award.completedSessions = count - credited
            award.minutes = minutes * award.completedSessions
        } else if let old, old.source == new.source, Self.focusWasCutShort(old, by: new) {
            let minutes = Int(old.elapsed(at: now) / 60)
            award.points = recordStudy(minutes: minutes, completed: false)
            award.minutes = minutes
        }
        guard award.points > 0 else { return nil }
        award.unlocked = PetCloset.wardrobe.filter { state(of: $0) == .affordable && !before.contains($0) }
        return award
    }

    /// Credits a Party shared session that ran to its end with the user in
    /// it (`PetPointsRules.sharedPoints`), and returns the award to
    /// celebrate. The shared clock never counts completions, so this is the
    /// only way a shared session pays. Nil when the stay was too short.
    public mutating func credit(_ session: PartySessionCompletion) -> PetStudyAward? {
        let before = Set(PetCloset.wardrobe.filter { state(of: $0) == .affordable })
        let points = save.ledger.recordSharedSession(minutes: session.minutes, friends: session.friendCount)
        guard points > 0 else { return nil }
        let unlocked = PetCloset.wardrobe.filter { state(of: $0) == .affordable && !before.contains($0) }
        return PetStudyAward(completedSessions: 1, minutes: session.minutes, points: points, unlocked: unlocked)
    }

    /// A focus phase under way in `old` that `new` left without completing
    /// it: skipped to the break, or reset to idle.
    private static func focusWasCutShort(_ old: ProvidedFocus, by new: ProvidedFocus) -> Bool {
        guard old.phase == .focus, old.isActive else { return false }
        return new.phase != .focus || !new.isActive
    }
}

extension PetStudyAward {
    /// The celebration bubble's first line. Kind and plain, and it never
    /// names a subject, so any kit can use it.
    public var headline: String {
        switch completedSessions {
        case 0: "\(minutes) minutes in the bank."
        case 1: Self.cheers[minutes % Self.cheers.count]
        default: "\(completedSessions) sessions done. Wow!"
        }
    }

    private static let cheers = ["Session done. Nice work!", "That's a wrap. Well done!", "Done! You stuck with it."]

    /// The second line on a level-up, e.g. "Enough for the Beanie now.";
    /// nil otherwise.
    public var unlockLine: String? {
        let names = unlocked.prefix(2).map { "the \($0.displayName)" }
        guard let first = names.first else { return nil }
        let list = names.count == 2 ? "\(first) and \(names[1])" : first
        return "Enough for \(list) now."
    }

    /// The points pill, e.g. "+35".
    public var pointsText: String { "+\(points)" }
}
