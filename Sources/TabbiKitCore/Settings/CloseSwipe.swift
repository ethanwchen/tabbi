/// Turns vertical scroll events into "put the notch away": a two-finger
/// swipe up on the open notch closes it, like pushing the panel back into
/// the hardware notch.
///
/// Only trackpad gestures count. A mouse wheel has no gestures and scrolls
/// too casually to close anything, and momentum after the fingers lift is
/// ignored. A gesture that starts over a list that can scroll belongs to the
/// list, so scrolling never closes the notch by accident.
public struct CloseSwipe: Sendable {
    /// Points of upward travel that close the notch. Longer than a tab
    /// swipe's, since closing is the bigger step.
    public static let threshold = 70.0

    private var travel = 0.0
    private var isActive = false

    public init() {}

    /// Feeds one scroll event and returns true when it completes a close.
    ///
    /// `fingersUp` is the vertical travel with the user's scroll direction
    /// taken out: positive when the fingers move away from the user.
    /// `overScrollableList` is read when the gesture begins.
    public mutating func feed(
        deltaX: Double,
        fingersUp: Double,
        phase: TabSwipe.Phase,
        overScrollableList: Bool
    ) -> Bool {
        switch phase {
        case .none, .momentum:
            return false
        case .began:
            travel = 0
            isActive = !overScrollableList
        case .changed:
            break
        case .ended:
            isActive = false
            return false
        }
        guard isActive, abs(fingersUp) > abs(deltaX) else { return false }
        travel = max(travel + fingersUp, 0)
        guard travel > Self.threshold else { return false }
        isActive = false
        return true
    }
}
