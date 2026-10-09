/// Turns horizontal scroll events into tab steps: a two-finger swipe across
/// the open notch moves one tab, however long the swipe runs.
///
/// A gesture steps once, when its travel passes `threshold`, and nothing
/// else in that gesture (or the momentum scrolling after it) steps again,
/// so a long swipe can't step back and forth and land where it started. A
/// mouse's horizontal wheel has no gestures; each `threshold` of its travel
/// is a step.
public struct TabSwipe: Sendable {
    public enum Step: Sendable, Equatable {
        /// Swiping right, back to the tab on the left.
        case previous
        /// Swiping left, on to the tab on the right.
        case next
    }

    /// Where a scroll event sits in its gesture (AppKit's `phase`).
    public enum Phase: Sendable, Equatable {
        case began, changed, ended
        /// Momentum scrolling after the fingers lifted.
        case momentum
        /// A mouse wheel, which has no gestures.
        case none
    }

    /// Points of horizontal travel that make a step.
    public static let threshold = 60.0

    private var travel = 0.0
    private var hasStepped = false

    public init() {}

    /// Feeds one scroll event and returns the step it completes, if any.
    /// Mostly vertical events (scrolling a list) are ignored.
    public mutating func feed(deltaX: Double, deltaY: Double, phase: Phase) -> Step? {
        switch phase {
        case .momentum:
            return nil
        case .began:
            travel = 0
            hasStepped = false
        case .changed, .ended, .none:
            break
        }
        defer {
            if phase == .ended {
                travel = 0
                hasStepped = false
            }
        }
        guard !hasStepped, abs(deltaX) > abs(deltaY) else { return nil }
        travel += deltaX
        guard abs(travel) > Self.threshold else { return nil }
        let step: Step = travel > 0 ? .previous : .next
        travel = 0
        hasStepped = phase != .none
        return step
    }
}
