import Foundation

/// Decides when the main thread has hung, from a watchdog that pings it
/// once per tick and asks on the next tick whether the ping was answered.
///
/// It counts unanswered ticks rather than measuring wall-clock time, so a
/// Mac waking from sleep (when no tick fired for hours) never reads as a
/// hang. A hang begins after `ticksToHang` unanswered ticks in a row and
/// ends with the first answer after that; a hang that never ends is one the
/// person force-quit, which is the one worth a report.
public struct HangDetector: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// The main thread has not answered for `ticksToHang` ticks.
        case began
        /// The main thread answered again after a hang.
        case ended
    }

    public let ticksToHang: Int
    public private(set) var unansweredTicks = 0
    public private(set) var isHanging = false

    public init(ticksToHang: Int) {
        self.ticksToHang = max(1, ticksToHang)
    }

    /// Call once per tick with whether the main thread answered the last
    /// ping. Returns the change this tick brings, if any.
    public mutating func tick(answered: Bool) -> Event? {
        if answered {
            unansweredTicks = 0
            guard isHanging else { return nil }
            isHanging = false
            return .ended
        }
        unansweredTicks += 1
        guard !isHanging, unansweredTicks >= ticksToHang else { return nil }
        isHanging = true
        return .began
    }
}
