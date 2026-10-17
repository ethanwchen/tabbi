import Foundation

/// The move the pet models at the start of one break, and when.
///
/// A plain value carried from the break buddy to the closed notch
/// (`PetPresence.breakMoment`, `TickerPet.breakMoment`) and the open break
/// card, so every view counts down the same wall-clock moment.
public struct BreakMoment: Hashable, Sendable {
    public var move: BreakMove
    /// The module whose clock runs the break (Study or Focus).
    public var source: ModuleID
    /// When the break began, which names the break for the planner's history.
    public var breakStartedAt: Date
    /// When the pet started modeling the move.
    public var startedAt: Date
    /// When the moment is over and the pet goes back to its break.
    public var endsAt: Date

    public init(move: BreakMove, source: ModuleID, breakStartedAt: Date, startedAt: Date, endsAt: Date) {
        self.move = move
        self.source = source
        self.breakStartedAt = breakStartedAt
        self.startedAt = startedAt
        self.endsAt = max(endsAt, startedAt)
    }

    /// The moment's whole length in seconds.
    public var length: TimeInterval { endsAt.timeIntervalSince(startedAt) }

    /// Seconds left at `now`, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        max(endsAt.timeIntervalSince(now), 0)
    }

    /// How much of the moment has passed at `now`, 0 to 1.
    public func progress(at now: Date) -> Double {
        guard length > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startedAt) / length, 0), 1)
    }

    /// Whether the pet is modeling the move at `now`.
    public func isShowing(at now: Date) -> Bool {
        now >= startedAt && now < endsAt
    }

    /// A sample moment for demo runs and snapshots: the pet stretching,
    /// twelve seconds in.
    public static func sample(at now: Date, move: BreakMove = .stretch, source: ModuleID = .study) -> BreakMoment {
        let started = now.addingTimeInterval(-12)
        return BreakMoment(move: move, source: source, breakStartedAt: started, startedAt: started,
                           endsAt: started.addingTimeInterval(move.length))
    }
}
