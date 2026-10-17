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
        String(localized: "\(count) tasks left", bundle: .tabbi)
    }

    /// "84 cards left" or "1h 15m left": what remains of a shared goal, in its own unit.
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
        let clock = focusClock(focus.time)
        let line = focus.countsUp ? String(localized: "\(focus.label) \(clock) so far", bundle: .tabbi)
            : "\(focus.label) \(clock)"
        return focus.isRunning ? line : String(localized: "\(line) (paused)", bundle: .tabbi)
    }

    /// Party size, e.g. "4 in party".
    public static func partySize(_ count: Int) -> String {
        String(localized: "\(count) in party", bundle: .tabbi)
    }

    /// The pet's line for tooltips and accessibility, e.g. "Mochi is napping".
    public static func petSummary(_ pet: TickerPet, at now: Date = .now) -> String {
        let name = pet.profile.name
        if let moment = pet.breakMoment {
            let clock = breakCountdown(moment.remaining(at: now))
            let title = moment.move.title(petName: BreakMove.buddyName(for: pet.profile))
            return String(localized: "\(title), \(clock) left", bundle: .tabbi)
        }
        if pet.isSipping { return String(localized: "Your Mac is charging, and \(name) is having a sip", bundle: .tabbi) }
        if pet.adventure?.isExploring(at: now) == true {
            return String(localized: "\(name) is off on a little adventure and will be back as your session ends",
                          bundle: .tabbi)
        }
        if let unlock = pet.unlockHint {
            return String(localized: "\(name) is keeping you company. \(unlock.line)", bundle: .tabbi)
        }
        return switch pet.mood {
        case .studying: String(localized: "\(name) is studying with you", bundle: .tabbi)
        case .onBreak: String(localized: "\(name) is on a break with you", bundle: .tabbi)
        case .awake: String(localized: "\(name) is keeping you company", bundle: .tabbi)
        case .asleep: String(localized: "\(name) is napping until your next session", bundle: .tabbi)
        }
    }

    /// The name beside the pet in the closed notch: only one the user chose.
    /// A pet still going by a name the app gave it (its breed, "Biscuit")
    /// shows no name, so "British Shorthair" doesn't stretch the notch to
    /// its widest; the tooltip still names it.
    public static func petLabel(_ pet: TickerPet) -> String? {
        pet.profile.hasDefaultName ? nil : pet.profile.name
    }

    /// Shown beside the pet while it sips because the Mac started charging.
    public static var charging: String { String(localized: "Charging", bundle: .tabbi) }

    /// The time left of a break move beside the closed notch's pet, digits
    /// only ("0:42"), so it fits any language; the tooltip names the move.
    public static func breakCountdown(_ remaining: TimeInterval) -> String {
        StudyTimerFormat.clock(remaining)
    }

    /// A same-width stand-in for `breakCountdown`, which sizes the wing so
    /// it doesn't breathe as the digits change (moments last at most a
    /// minute, so "1:00" is as wide as "0:00").
    public static let breakCountdownSample = "0:00"

    /// Shown after the name while the pet sleeps.
    public static let petSleeping = "zzz"

    /// Beside the pet's name while it is off on an adventure mid-session.
    public static var petExploring: String { String(localized: "exploring", bundle: .tabbi) }
}
