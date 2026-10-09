import Foundation

/// A small touch at a turning point of a focus session, smaller than a
/// celebration: a light trackpad tap and, for some, a soft sound. Each
/// follows the same Settings as celebrations (haptics, celebration sound).
public enum SessionCue: Equatable, Sendable {
    /// A fresh focus block began (not a resume after a pause).
    case focusStarted
    /// A break ran out and it is time to focus again.
    case breakOver

    /// The cue for pressing start, or nil for a resume or a break: only a
    /// new focus block gets one, so pausing and resuming stays quiet.
    public static func start(wasIdle: Bool, isFocus: Bool) -> SessionCue? {
        wasIdle && isFocus ? .focusStarted : nil
    }

    /// The cue for a phase that just ran out, or nil when it was a focus
    /// phase (that one celebrates instead).
    public static func phaseEnded(wasBreak: Bool) -> SessionCue? {
        wasBreak ? .breakOver : nil
    }

    /// The soft sound, or nil when sounds are off. A break that runs out
    /// already chimes, so it adds none.
    public func sound(isEnabled: Bool) -> CelebrationSound? {
        guard isEnabled else { return nil }
        switch self {
        case .focusStarted: return CelebrationSound(name: "Tink", volume: 0.18)
        case .breakOver: return nil
        }
    }
}
