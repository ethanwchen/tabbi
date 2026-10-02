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
        "\(item.remaining) \(item.unit) left"
    }

    /// Focus countdown, e.g. "18:42", matching the focus card's clock.
    public static func focusClock(_ remaining: TimeInterval) -> String {
        FocusTimerFormat.clock(remaining)
    }

    /// Usage line, e.g. "5h 84%" or "Week 91%".
    public static func usage(window: TickerUsageWindow, utilization: Double) -> String {
        let label = window == .fiveHour ? "5h" : "Week"
        return "\(label) \(ClaudeUsageFormat.percent(utilization))"
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

    /// Shown after the name while the pet sleeps.
    public static let petSleeping = "zzz"
}
