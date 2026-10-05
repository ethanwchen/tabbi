import SwiftUI
import TabbiKitCore

/// A plain button that answers the pointer: it sinks while pressed (with
/// the press spring) and, when `lifts` is on, grows a little while hovered
/// (with the hover spring). Under Reduce Motion it dims on press instead of
/// scaling. The label keeps its own hover colors; this only adds the motion.
///
/// Use it in place of `.plain` for controls in the notch:
/// `.buttonStyle(.tactile)` for icons, `.buttonStyle(.tactile(.pill, lifts: true))`
/// for labeled pills that lift.
public struct TactileButtonStyle: ButtonStyle {
    let feedback: TactileFeedback
    let lifts: Bool

    public init(_ feedback: TactileFeedback = .control, lifts: Bool = false) {
        self.feedback = feedback
        self.lifts = lifts
    }

    public func makeBody(configuration: Configuration) -> some View {
        TactileLabel(configuration: configuration, feedback: feedback, lifts: lifts)
    }
}

private struct TactileLabel: View {
    let configuration: ButtonStyleConfiguration
    let feedback: TactileFeedback
    let lifts: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let scale = feedback.scale(pressed: pressed, hovering: hovering && isEnabled,
                                   lifts: lifts, reduceMotion: reduceMotion)
        let opacity = feedback.opacity(pressed: pressed, reduceMotion: reduceMotion)
        // Scoped animation: only the press scale and dim animate here, so
        // the label's own changes keep their own timing.
        configuration.label
            .animation(Motion.adapted(pressed ? Motion.press : Motion.hover, reduceMotion: reduceMotion)) {
                $0.scaleEffect(scale).opacity(opacity)
            }
            .onHover { if lifts { hovering = $0 } }
    }
}

public extension ButtonStyle where Self == TactileButtonStyle {
    /// A small control that sinks when pressed.
    static var tactile: TactileButtonStyle { TactileButtonStyle() }

    /// A control with the given feedback that sinks when pressed and, if
    /// `lifts`, grows a little on hover.
    static func tactile(_ feedback: TactileFeedback, lifts: Bool = false) -> TactileButtonStyle {
        TactileButtonStyle(feedback, lifts: lifts)
    }
}
