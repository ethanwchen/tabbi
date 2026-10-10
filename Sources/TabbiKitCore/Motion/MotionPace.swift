import Foundation

/// How lively Tabbi's animations are, chosen in Settings > General.
///
/// It scales every `MotionTokens` value on top of the theme's `ThemeMotion`,
/// so one choice reaches the notch opening, hover, tab switches and every
/// control. Reduce Motion in System Settings still wins over Smooth and
/// Fast: the movement is replaced by a short crossfade (see `isAnimated`).
public enum MotionPace: String, CaseIterable, Sendable {
    /// The motion tokens as designed: springy, with a subtle overshoot on
    /// opening and selection.
    case smooth
    /// Quicker and with no overshoot, for people who find springs slow.
    case fast
    /// No animation at all: every change lands at once.
    case instant

    public static let `default`: MotionPace = .smooth

    /// The share of each duration Fast keeps.
    public static let fastScale: Double = 0.6

    public var title: String {
        switch self {
        case .smooth: "Smooth"
        case .fast: "Fast"
        case .instant: "Instant"
        }
    }

    /// One line for Settings saying what the choice feels like.
    public var caption: String {
        switch self {
        case .smooth: "Springy, with a little bounce."
        case .fast: "Quick and crisp, with no bounce."
        case .instant: "Changes appear at once, with no animation."
        }
    }

    /// `spec` at this pace, or nil when it should not animate.
    public func adjusted(_ spec: SpringSpec) -> SpringSpec? {
        switch self {
        case .smooth: spec
        case .fast: SpringSpec(duration: spec.duration * Self.fastScale, bounce: 0)
        case .instant: nil
        }
    }

    /// A fade's or delay's `seconds` at this pace: 0 for Instant.
    public func duration(_ seconds: Double) -> Double {
        switch self {
        case .smooth: seconds
        case .fast: seconds * Self.fastScale
        case .instant: 0
        }
    }

    /// Whether anything moves: false for Instant, and under Reduce Motion
    /// for every pace, so Reduce Motion behaves like Instant apart from its
    /// short crossfade.
    public func isAnimated(reduceMotion: Bool) -> Bool {
        self != .instant && !reduceMotion
    }
}
