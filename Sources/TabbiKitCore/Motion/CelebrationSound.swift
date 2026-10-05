import Foundation

/// The optional soft sound under a celebration: a quiet macOS system sound,
/// chosen by tier, that plays only when the user allows it and the event
/// has no sound of its own (a finished focus session already chimes).
public struct CelebrationSound: Equatable, Sendable {
    /// The system sound's name, as `NSSound(named:)` takes it.
    public let name: String
    /// Kept well under the chimes' 0.5, so it sits under the particles
    /// instead of announcing them.
    public let volume: Float

    public init(name: String, volume: Float) {
        self.name = name
        self.volume = volume
    }

    /// The sound for an admitted celebration, or nil when it should be
    /// silent: sounds are off in Settings, or the event already played one.
    public static func cue(for tier: CelebrationTier, isEnabled: Bool, eventHasSound: Bool) -> CelebrationSound? {
        guard isEnabled, !eventHasSound else { return nil }
        switch tier {
        case .burst: return CelebrationSound(name: "Pop", volume: 0.25)
        case .milestone: return CelebrationSound(name: "Hero", volume: 0.2)
        }
    }
}
