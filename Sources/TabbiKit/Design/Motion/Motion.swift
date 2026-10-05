import SwiftUI
import TabbiKitCore

/// Tabbi's motion system: the `MotionTokens` springs as SwiftUI animations,
/// each with a calm Reduce Motion fallback. See docs/design/motion.md.
///
/// Rules: animate state changes with these, never linear; under Reduce
/// Motion use the `reduced` variants (a short crossfade, no scale or slide);
/// motion decorates, it never carries information on its own.
public enum Motion {
    /// Notch opening: stretch and settle.
    public static let open = Animation(MotionTokens.open)
    /// Notch closing: no overshoot, slightly faster than opening.
    public static let close = Animation(MotionTokens.close)
    /// Hover growth and lift.
    public static let hover = Animation(MotionTokens.hover)
    /// Selection, toggles, small state changes.
    public static let snappy = Animation(MotionTokens.snappy)
    /// Content swaps inside the open notch.
    public static let content = Animation(MotionTokens.content)
    /// Press feedback on controls.
    public static let press = Animation(MotionTokens.press)
    /// A checkbox turning on, with a small bounce.
    public static let check = Animation(MotionTokens.check)
    /// Panel content fading in behind the opening shape.
    public static let contentIn = Animation.easeOut(duration: MotionTokens.contentFadeIn).delay(MotionTokens.contentDelay)
    /// Panel content fading out before the shape collapses.
    public static let contentOut = Animation.easeIn(duration: MotionTokens.contentFadeOut)
    /// The Reduce Motion replacement for every spring above.
    public static let reduced = Animation.easeInOut(duration: MotionTokens.reducedCrossfade)

    /// `animation`, or the calm crossfade when Reduce Motion is on.
    public static func adapted(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// The notch shape's animation toward `isOpen`: open stretches, close lands.
    public static func notch(opening isOpen: Bool, reduceMotion: Bool) -> Animation {
        adapted(isOpen ? open : close, reduceMotion: reduceMotion)
    }

    /// `animation` delayed for the item at `index` in a staggered entrance.
    /// No stagger under Reduce Motion, where everything crossfades together.
    public static func staggered(_ animation: Animation, index: Int, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation.delay(MotionTokens.stagger(index))
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
