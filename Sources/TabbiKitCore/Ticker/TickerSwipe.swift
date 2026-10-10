/// Turns vertical scroll events over the closed notch into "next live
/// activity" steps: a two-finger swipe down cycles once, however long it
/// runs, like pulling the next card off a stack.
///
/// Works like `TabSwipe` turned on its side: a gesture steps once, when its
/// downward travel passes `threshold`, and nothing else in that gesture (or
/// its momentum) steps again. A mouse wheel has no gestures, so each
/// `threshold` of its downward travel is a step. Upward and mostly
/// horizontal travel never cycles.
public struct TickerSwipe: Sendable {
    /// Points of downward travel that make a step.
    public static let threshold = 40.0

    private var travel = 0.0
    private var hasStepped = false

    public init() {}

    /// Feeds one scroll event and returns true when it completes a step.
    ///
    /// `fingersDown` is the vertical travel with the user's scroll direction
    /// taken out: positive when the fingers (or the wheel) move toward the
    /// user, whatever the natural scrolling setting.
    public mutating func feed(deltaX: Double, fingersDown: Double, phase: TabSwipe.Phase) -> Bool {
        switch phase {
        case .momentum:
            return false
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
        guard !hasStepped, abs(fingersDown) > abs(deltaX) else { return false }
        travel = max(travel + fingersDown, 0)
        guard travel > Self.threshold else { return false }
        travel = 0
        hasStepped = phase != .none
        return true
    }
}
