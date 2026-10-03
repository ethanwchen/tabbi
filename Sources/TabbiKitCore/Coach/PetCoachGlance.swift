import Foundation

/// The coach's silent first step (`PetCoachDecision.lookOver`): the pet
/// lowers its head out of the notch's edge, looks at the user for a moment,
/// and pulls back up. No bubble, no sound, nothing to click.
///
/// A pure value of timestamps like `PetCoachStroll`, so the overlay only
/// asks "which clip, and how far into it, at `date`?".
public struct PetCoachGlance: Hashable, Sendable {
    public let startedAt: Date
    /// Length of the `peekIn` clip (lowering into view).
    public let enter: TimeInterval
    /// How long the pet hangs there looking.
    public let hold: TimeInterval
    /// Length of the `peekOut` clip (pulling back up).
    public let leave: TimeInterval

    /// A look long enough to notice and short enough to never be in the way.
    public static let standardHold: TimeInterval = 2.5

    public init(startedAt: Date, enter: TimeInterval, hold: TimeInterval = standardHold, leave: TimeInterval) {
        self.startedAt = startedAt
        self.enter = max(enter, 0)
        self.hold = max(hold, 0)
        self.leave = max(leave, 0)
    }

    /// Timed by `clips`' own peek clips, so the head lowers and lifts at the
    /// sprite's pace.
    public init(startedAt: Date, clips: PetClipSet, hold: TimeInterval = standardHold) {
        self.init(startedAt: startedAt, enter: clips[.peekIn].duration, hold: hold, leave: clips[.peekOut].duration)
    }

    public var duration: TimeInterval { enter + hold + leave }

    /// Back inside the notch; the overlay can close.
    public var endsAt: Date { startedAt.addingTimeInterval(duration) }

    /// The clip to show at `date` and the time into it, or nil while the
    /// pet is tucked inside the notch (before the start and after the end).
    /// The hold keeps `peekIn` past its end, which holds its last frame.
    public func pose(at date: Date) -> (animation: PetAnimation, elapsed: TimeInterval)? {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= 0, elapsed < duration else { return nil }
        if elapsed < enter + hold { return (.peekIn, elapsed) }
        return (.peekOut, elapsed - enter - hold)
    }

    /// A stroll that never leaves the notch edge and lasts as long as the
    /// glance, so the overlay window can size and close itself the same way
    /// for glances and walks.
    public var stroll: PetCoachStroll {
        PetCoachStroll(startedAt: startedAt, distance: 0, talkDuration: duration)
    }
}
