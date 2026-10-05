import Foundation

/// The clock behind Tabbi's loaders, as pure functions of time.
///
/// Loaders draw from a `TimelineView` instead of a `repeatForever`
/// animation, so they stop ticking the moment they leave the screen and
/// render the same frame for the same date (which is what snapshots and
/// frame strips need). docs/design/motion.md lists where each value is used.
public enum LoaderClock {
    /// One full turn of a spinner, in seconds.
    public static let spinPeriod: Double = 1
    /// One breath of the Reduce Motion fallback (dim, bright, dim), in seconds.
    public static let breathPeriod: Double = 1.6
    /// The dimmest a breathing loader gets, so it never disappears.
    public static let breathFloor: Double = 0.35
    /// Loaders redraw at most this often. A small arc looks smooth at 30 fps
    /// and costs half of what the display rate would.
    public static let frameRate: Double = 30

    /// The spinner's rotation in degrees at `time`, in `0..<360`.
    public static func spinAngle(at time: TimeInterval, period: Double = spinPeriod) -> Double {
        guard period > 0 else { return 0 }
        let turns = (time / period).truncatingRemainder(dividingBy: 1)
        return (turns < 0 ? turns + 1 : turns) * 360
    }

    /// The opacity of a loader that breathes instead of spinning (the Reduce
    /// Motion fallback): a smooth cosine between `breathFloor` and 1, fully
    /// bright at whole periods.
    public static func breathingOpacity(at time: TimeInterval, period: Double = breathPeriod) -> Double {
        guard period > 0 else { return 1 }
        let wave = (1 + cos(2 * Double.pi * time / period)) / 2
        return breathFloor + (1 - breathFloor) * wave
    }
}
