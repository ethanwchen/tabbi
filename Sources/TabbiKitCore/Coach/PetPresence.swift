import Foundation

/// What the study pet is doing beside the closed notch.
public enum PetMood: String, Hashable, Sendable {
    /// A focus phase is running: the pet studies along.
    case studying
    /// A break is running.
    case onBreak
    /// No session right now, but one ran recently (or the app just started).
    case awake
    /// No session for `PetPresence.sleepAfter`, or a quiet spell late at
    /// night (`PetPresence.night`): the pet dozes off.
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
    /// Progress toward the next shop item, from the pet's real points, so
    /// the closed notch can hint at an unlock that is near
    /// (`TickerPet.unlock`); nil when everything is owned.
    public var nextUnlock: UnlockProgress?
    /// When a session last ran, or when the pet came on screen.
    public private(set) var lastActive: Date
    /// Whether the last observed timer was mid-session, so the moment a
    /// session ends counts as activity too.
    private var sessionWasActive = false
    /// The pet's night, or nil for a pet that only sleeps after
    /// `sleepAfter`. Late at night it dozes after the shorter wake spell
    /// even if a session ran recently, and opening the notch wakes it.
    public var night: PetNightRhythm?
    /// The calendar whose time zone places the night. The app passes
    /// `.autoupdatingCurrent`, so the night follows a time zone change.
    public var calendar: Calendar
    /// When the user last opened the notch, which wakes a dozing pet at night.
    public private(set) var lastWoken: Date?
    /// The break move the pet is modeling right now (the break buddy), or
    /// nil. The Closet sets it from the shared break buddy, so the closed
    /// notch's pet plays the move with its countdown.
    public var breakMoment: BreakMoment?

    public init(profile: PetProfile, lastActive: Date, nextUnlock: UnlockProgress? = nil,
                night: PetNightRhythm? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.profile = profile
        self.lastActive = lastActive
        self.nextUnlock = nextUnlock
        self.night = night
        self.calendar = calendar
    }

    /// Records the shared focus clock at `now`. Running or paused sessions
    /// keep the pet awake, and so does the moment one ends.
    public mutating func observe(_ focus: ProvidedFocus?, at now: Date) {
        let active = Self.isActive(focus)
        if active || sessionWasActive { lastActive = max(lastActive, now) }
        sessionWasActive = active
    }

    /// Records that the user opened or closed the notch at `now`: at night the pet
    /// wakes for a wake spell. By day it changes nothing, so a napping pet
    /// still waits for the next session.
    public mutating func wake(at now: Date) {
        lastWoken = max(lastWoken ?? now, now)
    }

    /// The pet's mood at `now` for the shared focus clock.
    public func mood(focus: ProvidedFocus?, at now: Date) -> PetMood {
        if let focus, focus.isRunning {
            return focus.phase == .focus ? .studying : .onBreak
        }
        if Self.isActive(focus) { return .awake }
        if let night, night.isNight(at: now, calendar: calendar) {
            return night.dozes(at: now, focus: focus, lastWoken: lastStirred, calendar: calendar) ? .asleep : .awake
        }
        return now.timeIntervalSince(lastActive) < Self.sleepAfter ? .awake : .asleep
    }

    /// When the mood can next change if nothing else happens: the pet
    /// falling asleep, and with a `night`, also the night starting or
    /// ending and a wake spell running out. Nil while a session runs and,
    /// without a night, once the pet is already asleep at `now`.
    public func sleepsAt(focus: ProvidedFocus?, after now: Date) -> Date? {
        guard !Self.isActive(focus) else { return nil }
        var dates = [lastActive.addingTimeInterval(Self.sleepAfter)]
        if let night {
            dates.append(lastStirred.addingTimeInterval(night.wakeSpell))
            if let boundary = night.nextBoundary(after: now, calendar: calendar) { dates.append(boundary) }
        }
        return dates.filter { $0 > now }.min()
    }

    /// The last session or notch opening, whichever came later.
    private var lastStirred: Date {
        max(lastActive, lastWoken ?? lastActive)
    }

    private static func isActive(_ focus: ProvidedFocus?) -> Bool {
        focus?.isActive ?? false
    }
}
