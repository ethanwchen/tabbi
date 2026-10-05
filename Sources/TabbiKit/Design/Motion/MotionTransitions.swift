import SwiftUI

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
