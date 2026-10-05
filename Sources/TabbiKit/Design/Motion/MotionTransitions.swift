import SwiftUI
import TabbiKitCore

/// Shared transitions, each with a Reduce Motion variant that only fades.
public extension AnyTransition {
    /// The open notch's content: trails the shape in (fade plus a slight
    /// grow from the top edge, so it reads as coming out of the notch) and
    /// leaves quickly before the shape collapses.
    static func notchContent(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(Motion.reduced) }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(Motion.contentIn),
            removal: .opacity.animation(Motion.contentOut)
        )
    }

    /// Switching between tabs: a short slide in the direction of travel.
    static func tabSwitch(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity),
            removal: .offset(x: forward ? -24 : 24).combined(with: .opacity)
        )
    }
}

/// A shared insert and removal transition from a `TransitionPose`. It reads
/// Reduce Motion itself, so call sites write `.transition(.motionPop)` and
/// get a plain fade when the user asked for less motion.
public struct MotionTransition: Transition {
    public let pose: TransitionPose

    public init(_ pose: TransitionPose) {
        self.pose = pose
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(PoseEffect(pose: pose, isIdentity: phase.isIdentity))
    }
}

private struct PoseEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pose: TransitionPose
    let isIdentity: Bool

    func body(content: Content) -> some View {
        let resolved = pose.resolved(isIdentity: isIdentity, reduceMotion: reduceMotion)
        content
            .scaleEffect(resolved.scale, anchor: UnitPoint(x: pose.anchorX, y: pose.anchorY))
            .offset(x: resolved.offsetX, y: resolved.offsetY)
            .opacity(resolved.opacity)
    }
}

public extension Transition where Self == MotionTransition {
    /// A small control appearing in place (`TransitionPose.pop`).
    static var motionPop: MotionTransition { MotionTransition(.pop) }
    /// One content state replacing another (`TransitionPose.swap`).
    static var motionSwap: MotionTransition { MotionTransition(.swap) }
    /// A list row arriving from or leaving toward `edge`.
    static func motionRow(from edge: TransitionPose.Edge) -> MotionTransition {
        MotionTransition(.row(from: edge))
    }
}
