import Foundation

/// The clock behind `MarqueeText`, the shared line of text that scrolls to
/// show what does not fit, as pure functions of time.
///
/// A line that fits never moves. One that overflows rests at its start so
/// the opening words can be read, eases across until its end is in view,
/// rests again so the ending can be read, then fades out and back in at the
/// start, which reads calmer than rewinding past every word again. The view
/// draws from a `TimelineView` that only exists while the line overflows and
/// can be seen, so a line that fits costs nothing. docs/design/motion.md
/// describes where it is used.
public enum MarqueeMotion {
    /// Rest at the start of each cycle, long enough to read the opening words.
    public static let startPause: TimeInterval = 2
    /// Rest once the end is in view, long enough to read the ending.
    public static let endPause: TimeInterval = 1.6
    /// The fade out at the end and the fade back in at the start, each.
    public static let fade: TimeInterval = 0.3
    /// Scroll speed in points per second: slow enough to read along.
    public static let speed: Double = 30
    /// The shortest scroll, so a line a few points too long glides instead
    /// of twitching.
    public static let minimumTravel: TimeInterval = 0.8
    /// The line redraws at most this often while it scrolls; slow text
    /// looks smooth at 60 fps and costs half of a 120 Hz display's rate.
    public static let frameRate: Double = 60
    /// Width of the soft fade at an edge where text is cut off.
    public static let edgeFade: Double = 12
    /// Measured widths are rounded, so a line this close to its room
    /// counts as fitting.
    public static let slack: Double = 0.5

    /// How far the text overflows its room, in points: zero when it fits.
    public static func overflow(contentWidth: Double, containerWidth: Double) -> Double {
        guard contentWidth.isFinite, containerWidth.isFinite, containerWidth > 0,
              contentWidth > containerWidth + slack else { return 0 }
        return contentWidth - containerWidth
    }

    /// Whether the line should scroll: only when it overflows, motion is
    /// allowed and someone can see it. Otherwise it stays a still line,
    /// truncated with a tooltip if it does not fit.
    public static func scrolls(overflow: Double, reduceMotion: Bool, isVisible: Bool = true) -> Bool {
        overflow > 0 && !reduceMotion && isVisible
    }

    /// How long the scroll from start to end takes for `overflow` points.
    public static func travel(overflow: Double) -> TimeInterval {
        max(overflow / speed, minimumTravel)
    }

    /// One whole cycle: rest, scroll, rest, fade out, fade in.
    public static func cycle(overflow: Double) -> TimeInterval {
        startPause + travel(overflow: overflow) + endPause + 2 * fade
    }

    /// Where the line is drawn at one moment.
    public struct Pose: Equatable, Sendable {
        /// How far the text has moved toward its end, in points (0 at the
        /// start, `overflow` at the end). The view turns it into a leftward
        /// shift, or a rightward one for right-to-left text.
        public var offset: Double
        /// The text's opacity, below 1 only while it fades back to the start.
        public var opacity: Double

        public init(offset: Double, opacity: Double) {
            self.offset = offset
            self.opacity = opacity
        }

        public static let rest = Pose(offset: 0, opacity: 1)
    }

    /// The pose `elapsed` seconds after the line started scrolling. The
    /// scroll eases in and out (smoothstep), so it starts and stops gently.
    public static func pose(elapsed: TimeInterval, overflow: Double) -> Pose {
        guard overflow > 0, elapsed.isFinite, elapsed > 0 else { return .rest }
        let travel = travel(overflow: overflow)
        var t = elapsed.truncatingRemainder(dividingBy: cycle(overflow: overflow))
        if t < startPause { return .rest }
        t -= startPause
        if t < travel {
            let progress = t / travel
            return Pose(offset: overflow * progress * progress * (3 - 2 * progress), opacity: 1)
        }
        t -= travel
        if t < endPause { return Pose(offset: overflow, opacity: 1) }
        t -= endPause
        if t < fade { return Pose(offset: overflow, opacity: 1 - t / fade) }
        t -= fade
        return Pose(offset: 0, opacity: min(t / fade, 1))
    }

    /// The pose a fraction of the way through the scroll (0 at the start, 1
    /// at the end), for still renders such as snapshots of a line mid-scroll.
    public static func pose(scrolled fraction: Double, overflow: Double) -> Pose {
        guard overflow > 0, fraction.isFinite else { return .rest }
        return Pose(offset: overflow * min(max(fraction, 0), 1), opacity: 1)
    }
}
