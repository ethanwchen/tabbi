import Foundation

/// How a control answers the pointer: it sinks a little while pressed and,
/// if it asks to, lifts a little while hovered. `TactileButtonStyle` in
/// `TabbiKit` draws it; docs/design/motion.md lists the presets.
///
/// The amounts are small on purpose. A press shrinks a control by about
/// 2 to 3 pt, so it reads as a physical push without moving its neighbors'
/// edges, and wide controls shrink by a smaller fraction than icons.
/// Under Reduce Motion nothing scales: a press dims the control instead.
public struct TactileFeedback: Sendable, Equatable {
    /// Scale while the pointer holds the control down.
    public let pressedScale: Double
    /// Scale while hovered, for controls that lift.
    public let hoverScale: Double
    /// Opacity while pressed under Reduce Motion, which replaces the scale.
    public let reducedPressedOpacity: Double

    public init(pressedScale: Double, hoverScale: Double, reducedPressedOpacity: Double = 0.7) {
        self.pressedScale = pressedScale
        self.hoverScale = hoverScale
        self.reducedPressedOpacity = reducedPressedOpacity
    }

    /// Small round controls: icon buttons, transport buttons, tabs.
    public static let control = TactileFeedback(pressedScale: 0.92, hoverScale: 1.06)
    /// Wider controls: pills with a label, artwork, rows.
    public static let pill = TactileFeedback(pressedScale: 0.97, hoverScale: 1.03)

    /// The control's scale. Pressing wins over hovering, and a control only
    /// lifts on hover when it `lifts`.
    public func scale(pressed: Bool, hovering: Bool, lifts: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 }
        if pressed { return pressedScale }
        return hovering && lifts ? hoverScale : 1
    }

    /// The control's opacity: only a press under Reduce Motion dims it.
    public func opacity(pressed: Bool, reduceMotion: Bool) -> Double {
        pressed && reduceMotion ? reducedPressedOpacity : 1
    }
}
