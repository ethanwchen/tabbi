import Foundation

/// Where a hand-drawn slider's knob and fill sit, and which value a pointer
/// at some x picks, for the notch's thin track sliders (focus sound levels,
/// player volume, the playback scrubber).
///
/// The knob's center travels from one radius in from the leading end to one
/// radius in from the trailing end, so the whole knob always stays on the
/// track, at 0 and at 1 alike. The pointer maps through the same inset, so
/// the knob's center sits exactly under the pointer while dragging and
/// only stops at the ends. The fill runs to the knob's center.
public struct TrackSliderGeometry: Equatable, Sendable {
    /// The track's width in points.
    public let width: Double
    /// The knob's diameter in points; 0 for a slider without a knob.
    public let knobDiameter: Double

    public init(width: Double, knobDiameter: Double) {
        self.width = width.isFinite ? max(width, 0) : 0
        self.knobDiameter = knobDiameter.isFinite ? max(knobDiameter, 0) : 0
    }

    /// Half the knob, never more than half the track, so a track narrower
    /// than its knob keeps the knob centered instead of inverting the range.
    public var knobRadius: Double { min(knobDiameter / 2, width / 2) }

    /// How far the knob's center can travel.
    public var travel: Double { width - 2 * knobRadius }

    /// The knob's center for `fraction` (clamped to 0...1), in points from
    /// the leading end.
    public func knobCenter(at fraction: Double) -> Double {
        knobRadius + Self.clamp(fraction) * travel
    }

    /// The knob's leading edge for `fraction`, the offset that places a knob
    /// laid out at the track's leading end.
    public func knobOffset(at fraction: Double) -> Double {
        knobCenter(at: fraction) - knobRadius
    }

    /// How wide the filled part of the track is for `fraction`: up to the
    /// knob's center, and empty at 0.
    public func fillWidth(at fraction: Double) -> Double {
        let fraction = Self.clamp(fraction)
        return fraction > 0 ? knobCenter(at: fraction) : 0
    }

    /// The fraction (0...1) a pointer at `x` picks, so the knob's center
    /// lands under it. Past either end, and for a track with no travel, it
    /// clamps; a non-finite x picks the nearer end.
    public func fraction(atX x: Double) -> Double {
        guard x.isFinite else { return x > 0 ? 1 : 0 }
        guard travel > 0 else { return x >= width / 2 ? 1 : 0 }
        return Self.clamp((x - knobRadius) / travel)
    }

    private static func clamp(_ fraction: Double) -> Double {
        fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }
}
