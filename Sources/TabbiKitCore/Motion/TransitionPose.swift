import Foundation

/// How a view looks while it enters or leaves: scale, offset and opacity.
/// `MotionTransition` in `TabbiKit` applies it; docs/design/motion.md lists
/// the presets.
///
/// The shared presets keep inserts and removals small and fast: a view
/// fades while it moves at most 8 pt or shrinks to at most 80%, so a list
/// that changes never sends rows flying across the 150 pt canvas.
/// Under Reduce Motion a transition only fades.
public struct TransitionPose: Sendable, Equatable {
    /// Scale while the view is outside the hierarchy.
    public let scale: Double
    /// Offset while the view is outside the hierarchy, in points.
    public let offsetX: Double
    public let offsetY: Double
    /// Where the scale grows from, as a unit point (0.5, 0.5 is the center).
    public let anchorX: Double
    public let anchorY: Double

    public init(scale: Double = 1, offsetX: Double = 0, offsetY: Double = 0,
                anchorX: Double = 0.5, anchorY: Double = 0.5) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.anchorX = anchorX
        self.anchorY = anchorY
    }

    /// A small control or badge appearing in place: hover buttons, a clear
    /// button, a pill that swaps with another.
    public static let pop = TransitionPose(scale: 0.8)
    /// One content state replacing another in the same space (a checklist
    /// becoming a day plan): a slight grow from the top edge.
    public static let swap = TransitionPose(scale: 0.98, anchorY: 0)
    /// A list row arriving from or leaving toward `edge`.
    public static func row(from edge: Edge) -> TransitionPose {
        let distance = 8.0
        switch edge {
        case .top: return TransitionPose(offsetY: -distance)
        case .bottom: return TransitionPose(offsetY: distance)
        case .leading: return TransitionPose(offsetX: -distance)
        case .trailing: return TransitionPose(offsetX: distance)
        }
    }

    /// The edge a row enters from, without depending on SwiftUI.
    public enum Edge: Sendable { case top, bottom, leading, trailing }

    /// What the view shows: neutral once inserted, the pose while outside.
    public struct Resolved: Sendable, Equatable {
        public let scale: Double
        public let offsetX: Double
        public let offsetY: Double
        public let opacity: Double
    }

    /// The pose to draw. `isIdentity` is true once the view is in place;
    /// Reduce Motion drops the scale and offset and keeps only the fade.
    public func resolved(isIdentity: Bool, reduceMotion: Bool) -> Resolved {
        if isIdentity { return Resolved(scale: 1, offsetX: 0, offsetY: 0, opacity: 1) }
        if reduceMotion { return Resolved(scale: 1, offsetX: 0, offsetY: 0, opacity: 0) }
        return Resolved(scale: scale, offsetX: offsetX, offsetY: offsetY, opacity: 0)
    }
}
