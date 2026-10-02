import Foundation

/// Bar heights for the closed-notch equalizer. A pure function of time, so the
/// view can draw it from a `TimelineView` that simply stops when playback
/// pauses, and the motion stays smooth without any stored animation state.
public enum SpotifyEqualizer {
    /// Bars drawn in the compact wing.
    public static let barCount = 4
    /// Lowest level a bar reaches; keeps every bar visible as a short pill.
    public static let minimumLevel = 0.22

    /// Short, staggered heights shown while paused, so the bars read as
    /// "resting" rather than broken.
    public static func restingLevels(count: Int = barCount) -> [Double] {
        (0..<max(count, 0)).map { minimumLevel + 0.08 * Double($0 % 2) }
    }

    /// Levels in `minimumLevel ... 1` for each bar at `time` seconds. Each bar
    /// mixes two sines at unrelated frequencies so the pattern never visibly
    /// repeats and neighboring bars don't move in lockstep.
    public static func levels(at time: TimeInterval, count: Int = barCount) -> [Double] {
        guard time.isFinite else { return restingLevels(count: count) }
        return (0..<max(count, 0)).map { index in
            let i = Double(index)
            let slow = sin(time * (5.1 + i * 1.3) + i * 1.7)
            let fast = sin(time * (8.3 + i * 0.9) + i * 2.9)
            let mixed = (slow * 0.6 + fast * 0.4 + 1) / 2 // 0 ... 1
            return minimumLevel + (1 - minimumLevel) * min(max(mixed, 0), 1)
        }
    }
}
