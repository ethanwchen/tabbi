import Foundation

/// Tabbi's motion values, as pure numbers. `Motion` in `TabbiKit` turns them
/// into SwiftUI animations; docs/design/motion.md explains each one.
///
/// The numbers come from docs/research/motion.md: the notch opens with a
/// little stretch and closes critically damped (no wobble on collapse, a top
/// complaint about other notch apps), content trails the shape, and hover
/// answers within 150 to 300 ms.
public enum MotionTokens {
    /// Notch opening: a calm stretch that settles.
    public static let open = SpringSpec(duration: 0.45, bounce: 0.2)
    /// Notch closing: faster and with no overshoot, so it lands.
    public static let close = SpringSpec(duration: 0.38, bounce: 0)
    /// Hover growth of the closed notch and hover lift of controls.
    public static let hover = SpringSpec(duration: 0.25, bounce: 0.1)
    /// Selection, toggles and other small state changes.
    public static let snappy = SpringSpec(duration: 0.26, bounce: 0.14)
    /// Content swaps inside the open notch (tabs, phases, list changes).
    public static let content = SpringSpec(duration: 0.34, bounce: 0.1)
    /// A short spring for tactile press feedback.
    public static let press = SpringSpec(duration: 0.18, bounce: 0)

    /// How far the panel content trails the notch shape when it opens.
    public static let contentDelay: Double = 0.08
    /// Fade in of the panel content once it starts.
    public static let contentFadeIn: Double = 0.22
    /// Fade out of the panel content when the notch closes, before the shape collapses.
    public static let contentFadeOut: Double = 0.12

    /// The calm fallback under Reduce Motion: a short crossfade, no springs,
    /// no scale or slide.
    public static let reducedCrossfade: Double = 0.18

    /// Delay between items that enter one after another.
    public static let staggerStep: Double = 0.03
    /// Upper bound on the total stagger, so long lists don't feel slow.
    public static let staggerCap: Double = 0.15

    /// Delay for the item at `index` in a staggered entrance, capped so the
    /// last item never waits longer than `cap`.
    public static func stagger(_ index: Int, step: Double = staggerStep, cap: Double = staggerCap) -> Double {
        min(Double(max(index, 0)) * step, cap)
    }
}
