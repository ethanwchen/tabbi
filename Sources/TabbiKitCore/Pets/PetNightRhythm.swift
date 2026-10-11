import Foundation

/// The pet's day and night: late at night, when no session runs, the pet
/// beside the closed notch dozes with a tiny "z". Opening the notch or
/// starting a session wakes it, and it nods off again after a quiet spell.
///
/// The window uses local wall-clock hours in `calendar`'s time zone, so it
/// follows the user across a time zone change. Dozing is never a nag: it
/// only changes the pose, and nothing asks the user to stop.
public struct PetNightRhythm: Hashable, Sendable {
    /// The local hour the night starts (23 is 11 PM).
    public let startHour: Int
    /// The local hour the night ends (6 is 6 AM), exclusive.
    public let endHour: Int
    /// How long the pet stays up after something woke it.
    public let wakeSpell: TimeInterval

    public static let standard = PetNightRhythm(startHour: 23, endHour: 6, wakeSpell: 10 * 60)

    public init(startHour: Int, endHour: Int, wakeSpell: TimeInterval) {
        self.startHour = min(max(startHour, 0), 23)
        self.endHour = min(max(endHour, 0), 23)
        self.wakeSpell = max(0, wakeSpell)
    }

    /// Whether `date` falls in the night window, in `calendar`'s time zone.
    /// A window that wraps past midnight (23 to 6) covers both ends.
    public func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour
    }

    /// Whether the pet dozes at `now`: night, no session running or paused,
    /// and no wake (the notch opened, a session started) within `wakeSpell`.
    public func dozes(at now: Date, focus: ProvidedFocus?, lastWoken: Date?,
                      calendar: Calendar = .current) -> Bool {
        guard isNight(at: now, calendar: calendar), !(focus?.isActive ?? false) else { return false }
        guard let lastWoken else { return true }
        return now.timeIntervalSince(lastWoken) >= wakeSpell || now < lastWoken
    }
}
