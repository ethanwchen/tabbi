import Foundation

/// How a round checkbox turns on, as pure functions of one progress value:
/// the accent fill pops in from the center, then the check stroke draws on
/// from its short leg to the tip of its long one. `CheckGlyph` in `TabbiKit`
/// animates `progress` from 0 to 1 with the `MotionTokens.check` spring, so
/// the spring's small overshoot is the toggle's bounce.
///
/// Progress past 1 (the overshoot) swells the fill a little and is capped,
/// while the stroke never draws past its end. Under Reduce Motion nothing
/// grows or draws: the finished checkbox crossfades in.
public struct CheckDraw: Sendable, Equatable {
    /// Ring opacity: the outline fades out as the fill arrives.
    public let ringOpacity: Double
    /// Fill opacity.
    public let fillOpacity: Double
    /// Fill scale, from `startScale` to 1, a little above 1 while the spring overshoots.
    public let fillScale: Double
    /// How much of the check stroke is drawn, 0 to 1.
    public let checkTrim: Double
    /// Check opacity, so a half-drawn stroke never shows on an empty box.
    public let checkOpacity: Double

    /// The fill starts at this fraction of the box and grows to full size.
    public static let startScale = 0.4
    /// Progress by which the fill reaches full size.
    public static let fillEnd = 0.55
    /// Progress at which the check starts drawing, while the fill still grows.
    public static let checkStart = 0.3
    /// The fill never swells past this while the spring overshoots.
    public static let maxSwell = 1.08

    /// The checkbox at `progress` (0 off, 1 on). With `reduceMotion` the
    /// finished checkbox fades in as a whole instead.
    public init(progress: Double, reduceMotion: Bool = false) {
        let p = progress.isFinite ? max(progress, 0) : 0
        if reduceMotion {
            let fade = min(p, 1)
            ringOpacity = 1 - fade
            fillOpacity = fade
            fillScale = 1
            checkTrim = 1
            checkOpacity = fade
            return
        }
        let grow = min(p / Self.fillEnd, 1)
        ringOpacity = 1 - min(p / Self.checkStart, 1)
        fillOpacity = min(p / 0.2, 1)
        fillScale = p <= 1
            ? Self.startScale + (1 - Self.startScale) * grow
            : min(1 + (p - 1), Self.maxSwell)
        checkTrim = min(max((p - Self.checkStart) / (1 - Self.checkStart), 0), 1)
        checkOpacity = checkTrim > 0 ? 1 : 0
    }
}
