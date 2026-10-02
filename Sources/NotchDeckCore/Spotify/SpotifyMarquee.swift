import Foundation

/// Scroll position for a title that doesn't fit its line. The view draws the
/// text twice, `gap` apart, and shifts both left by `offset`; one cycle moves
/// exactly one text width plus the gap, so the second copy lands where the
/// first started and the loop has no visible seam. A pure function of time,
/// so a `TimelineView` can drive it without stored animation state.
public enum SpotifyMarquee {
    /// Space between the end of the text and the start of its repeat.
    public static let gap: Double = 32
    /// Scroll speed in points per second; slow enough to read along.
    public static let speed: Double = 28
    /// Rest at the start of each cycle, so the opening words can be read.
    public static let pause: TimeInterval = 1.2

    /// Whether `textWidth` overflows `containerWidth` and so should scroll.
    /// Half a point of slack absorbs rounding in measured widths.
    public static func needsScrolling(textWidth: Double, containerWidth: Double) -> Bool {
        textWidth.isFinite && containerWidth.isFinite && textWidth > containerWidth + 0.5
    }

    /// Horizontal offset (zero or negative) `elapsed` seconds after scrolling
    /// started. Each cycle rests for `pause`, then eases in and out over the
    /// full distance, so the text starts and stops gently instead of jerking.
    public static func offset(elapsed: TimeInterval, textWidth: Double, containerWidth: Double) -> Double {
        guard elapsed.isFinite, elapsed > 0,
              needsScrolling(textWidth: textWidth, containerWidth: containerWidth) else { return 0 }
        let distance = textWidth + gap
        let travel = distance / speed
        let t = elapsed.truncatingRemainder(dividingBy: pause + travel)
        guard t > pause else { return 0 }
        let progress = (t - pause) / travel
        let eased = progress * progress * (3 - 2 * progress)
        return -distance * eased
    }
}
