import Foundation

/// How a progress ring moves between two values, as pure functions.
///
/// A ring fills smoothly as work advances and unwinds when a little is
/// taken back (a timer reset early on), but a big drop is a new start (a
/// Pomodoro phase change, a usage window that rolled over, a new day): the
/// ring snaps back to empty instead of sweeping backwards across the dial,
/// which would read as progress being undone.
public enum RingProgress {
    /// A drop larger than this fraction of the ring is a restart, not an unwind.
    public static let restartDrop: Double = 0.5

    /// What a ring does when its value changes.
    public enum Change: Equatable, Sendable {
        /// The value didn't move (after clamping).
        case none
        /// The ring fills further.
        case advance
        /// The ring gives back a little, animated.
        case unwind
        /// The ring starts over: jump to the new value without animating.
        case restart
    }

    /// `value` as a ring fraction in `0...1`. Missing or non-finite values
    /// (an unknown total, a division by zero) draw an empty ring.
    public static func clamped(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// How the ring should move from `old` to `new`.
    public static func change(from old: Double?, to new: Double?) -> Change {
        let from = clamped(old)
        let to = clamped(new)
        if to == from { return .none }
        if to > from { return .advance }
        return from - to > restartDrop ? .restart : .unwind
    }
}
