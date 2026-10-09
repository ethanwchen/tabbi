import Foundation

/// Short strings for the closed-notch preview, which has room for a few words.
public enum TickerFormat {
    /// Meeting countdown: "in 4 min" or "now". The title is rendered
    /// separately so it can truncate while the countdown stays whole.
    public static func meetingCountdown(_ timing: EventTiming) -> String {
        UpcomingEventFormat.badge(timing)
    }

    /// The whole meeting line, e.g. "Standup in 4 min" or "Design review now",
    /// for tooltips and accessibility.
    public static func meetingSummary(_ meeting: TickerMeeting) -> String {
        "\(meeting.title) \(meetingCountdown(meeting.timing))"
    }

    /// "3 tasks left", "1 task left".
    public static func tasksLeft(_ count: Int) -> String {
        count == 1 ? "1 task left" : "\(count) tasks left"
    }

    /// "84 cards left": what remains of a shared goal, in its own unit.
    public static func progressLeft(_ item: ProgressItem) -> String {
        item.remainingText
    }

    /// Focus countdown, e.g. "18:42", matching the focus card's clock.
    public static func focusClock(_ remaining: TimeInterval) -> String {
        FocusTimerFormat.clock(remaining)
    }

    /// The focus line for tooltips and accessibility, e.g. "Focus 18:42",
    /// "Review 3:10 (paused)" or "Focus 12:05 so far" for a clock counting up.
    public static func focusSummary(_ focus: TickerFocus) -> String {
        let clock = focusClock(focus.time) + (focus.countsUp ? " so far" : "")
        return "\(focus.label) \(clock)\(focus.isRunning ? "" : " (paused)")"
    }

    /// Party size, e.g. "4 in party".
    public static func partySize(_ count: Int) -> String {
        "\(count) in party"
    }

    /// The pet's line for tooltips and accessibility, e.g. "Mochi is napping".
    public static func petSummary(_ pet: TickerPet) -> String {
        switch pet.mood {
        case .studying: "\(pet.profile.name) is studying with you"
        case .onBreak: "\(pet.profile.name) is on a break with you"
        case .awake: "\(pet.profile.name) is keeping you company"
        case .asleep: "\(pet.profile.name) is napping until your next session"
        }
    }

    /// The name beside the pet in the closed notch: only one the user chose.
    /// A pet still going by a name the app gave it (its breed, "Biscuit")
    /// shows no name, so "British Shorthair" doesn't stretch the notch to
    /// its widest; the tooltip still names it.
    public static func petLabel(_ pet: TickerPet) -> String? {
        pet.profile.hasDefaultName ? nil : pet.profile.name
    }

    /// Shown after the name while the pet sleeps.
    public static let petSleeping = "zzz"
}
