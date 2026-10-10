import os
import SwiftUI
import TabbiKitCore

/// Tabbi's motion system: the `MotionTokens` springs as SwiftUI animations,
/// each with a calm Reduce Motion fallback. See docs/design/motion.md.
///
/// The springs follow the active theme's `ThemeMotion`, so the cozy themes
/// play every token slower and softer, and then the user's `MotionPace`
/// (Smooth, Fast or Instant, from Settings > General).
///
/// Rules: animate state changes with these, never linear; under Reduce
/// Motion use the `reduced` variants (a short crossfade, no scale or slide);
/// motion decorates, it never carries information on its own.
public enum Motion {
    /// The pace every animation below plays at.
    public static var pace: MotionPace { paceState.withLock { $0 } }

    /// Makes `pace` the active pace. Views pick it up the next time they
    /// animate, so nothing needs re-keying.
    public static func apply(_ pace: MotionPace) {
        paceState.withLock { $0 = pace }
    }

    private static let paceState = OSAllocatedUnfairLock(initialState: MotionPace.default)

    /// Notch opening: stretch and settle.
    public static var open: Animation { themed(MotionTokens.open) }
    /// Notch closing: no overshoot, slightly faster than opening.
    public static var close: Animation { themed(MotionTokens.close) }
    /// Hover growth and lift.
    public static var hover: Animation { themed(MotionTokens.hover) }
    /// Selection, toggles, small state changes.
    public static var snappy: Animation { themed(MotionTokens.snappy) }
    /// Content swaps inside the open notch.
    public static var content: Animation { themed(MotionTokens.content) }
    /// Press feedback on controls.
    public static var press: Animation { themed(MotionTokens.press) }
    /// A checkbox turning on, with a small bounce.
    public static var check: Animation { themed(MotionTokens.check) }
    /// Panel content fading in behind the opening shape.
    public static var contentIn: Animation {
        Animation.easeOut(duration: pace.duration(MotionTokens.contentFadeIn))
            .delay(pace.duration(MotionTokens.contentDelay))
    }
    /// Panel content fading out before the shape collapses.
    public static var contentOut: Animation {
        Animation.easeIn(duration: pace.duration(MotionTokens.contentFadeOut))
    }
    /// `spec` adjusted for the active theme and pace.
    private static func themed(_ spec: SpringSpec) -> Animation {
        pace.adjusted(Theme.current.motion.adjusted(spec)).map(Animation.init) ?? instant
    }

    /// Instant's stand-in for every animation: the change lands in the next frame.
    public static let instant = Animation.easeInOut(duration: 0)

    /// The Reduce Motion replacement for every spring above, and nothing at
    /// all at the Instant pace.
    public static var reduced: Animation {
        pace == .instant ? instant : Animation.easeInOut(duration: MotionTokens.reducedCrossfade)
    }

    /// `animation`, or the calm crossfade when Reduce Motion is on.
    public static func adapted(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// `animation` delayed for the item at `index` in a staggered entrance.
    /// No stagger under Reduce Motion or at the Instant pace, where
    /// everything arrives together.
    public static func staggered(_ animation: Animation, index: Int, reduceMotion: Bool) -> Animation {
        guard pace.isAnimated(reduceMotion: reduceMotion) else { return reduced }
        return animation.delay(pace.duration(MotionTokens.stagger(index)))
    }
}

public extension Animation {
    /// A SwiftUI spring from a pure `SpringSpec`.
    init(_ spec: SpringSpec) {
        self = .spring(duration: spec.duration, bounce: spec.bounce)
    }
}

public extension View {
    /// Like `.animation(_:value:)`, but swaps in the Reduce Motion crossfade
    /// when the user asked for less motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AdaptiveAnimation(animation: animation, value: value))
    }
}

private struct AdaptiveAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.adapted(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// `withAnimation` that honors Reduce Motion, for code outside a view body
/// (stores, controllers) that has no environment to read.
@MainActor
@discardableResult
public func withMotion<Result>(_ animation: Animation, _ body: () throws -> Result) rethrows -> Result {
    let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    return try withAnimation(Motion.adapted(animation, reduceMotion: reduce), body)
}
