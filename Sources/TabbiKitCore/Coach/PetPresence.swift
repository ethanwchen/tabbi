import Foundation

/// What the study pet is doing beside the closed notch.
public enum PetMood: String, Hashable, Sendable {
    /// A focus phase is running: the pet studies along.
    case studying
    /// A break is running.
    case onBreak
    /// No session right now, but one ran recently (or the app just started).
    case awake
    /// No session for `PetPresence.sleepAfter`: the pet dozes off.
    case asleep
}

/// The study pet as the closed notch shows it: its look plus the last time a
/// study session ran, so the notch can tell when the pet should doze off.
///
/// The Closet module publishes it through `ModuleProvision.pet`, and the
/// ticker reads it from `ProviderSnapshot`, so the notch shows the pet
/// without knowing which module owns it.
public struct PetPresence: Hashable, Sendable {
    /// Quiet time after a session (or launch) before the pet falls asleep.
    /// Long enough that a short coffee run between sessions keeps it awake.
    public static let sleepAfter: TimeInterval = 20 * 60

    public var profile: PetProfile
    /// When a session last ran, or when the pet came on screen.
    public private(set) var lastActive: Date
    /// Whether the last observed timer was mid-session, so the moment a
    /// session ends counts as activity too.
    private var sessionWasActive = false

    public init(profile: PetProfile, lastActive: Date) {
        self.profile = profile
        self.lastActive = lastActive
    }

    /// Records the shared focus clock at `now`. Running or paused sessions
    /// keep the pet awake, and so does the moment one ends.
    public mutating func observe(_ focus: ProvidedFocus?, at now: Date) {
        let active = Self.isActive(focus)
        if active || sessionWasActive { lastActive = max(lastActive, now) }
        sessionWasActive = active
    }

    /// The pet's mood at `now` for the shared focus clock.
    public func mood(focus: ProvidedFocus?, at now: Date) -> PetMood {
        if let focus, focus.isRunning {
            return focus.phase == .focus ? .studying : .onBreak
        }
        if Self.isActive(focus) { return .awake }
        return now.timeIntervalSince(lastActive) < Self.sleepAfter ? .awake : .asleep
    }

    /// When the pet falls asleep if nothing else happens: nil while a
    /// session runs and once the pet is already asleep at `now`.
    public func sleepsAt(focus: ProvidedFocus?, after now: Date) -> Date? {
        guard !Self.isActive(focus) else { return nil }
        let date = lastActive.addingTimeInterval(Self.sleepAfter)
        return date > now ? date : nil
    }

    private static func isActive(_ focus: ProvidedFocus?) -> Bool {
        focus?.isActive ?? false
    }
}
