import Foundation

/// Which day Today's checklist shows. Today is the default; the header steps
/// one day back to look at what yesterday left, or one day ahead to plan
/// tomorrow. Further days are out of reach on purpose, so the panel stays a
/// daily tool rather than a calendar.
public enum PlannerViewedDay: Int, CaseIterable, Hashable, Sendable {
    case yesterday = -1
    case today = 0
    case tomorrow = 1

    /// The day this names, counted from `today`.
    public func key(today: PlannerDayKey, calendar: Calendar = .current) -> PlannerDayKey {
        rawValue == 0 ? today : today.adding(days: rawValue, calendar: calendar)
    }

    /// One day earlier, or nil at yesterday.
    public var previous: Self? { Self(rawValue: rawValue - 1) }

    /// One day later, or nil at tomorrow.
    public var next: Self? { Self(rawValue: rawValue + 1) }

    /// The header title for a day other than today; nil for today, which
    /// shows its date.
    public var title: String? {
        switch self {
        case .yesterday: "Yesterday"
        case .today: nil
        case .tomorrow: "Tomorrow"
        }
    }

    /// The caption of the calendar card beside the list: what's next today,
    /// or the whole of the other day.
    public var calendarTitle: String {
        switch self {
        case .yesterday: "Yesterday's calendar"
        case .today: "Up next"
        case .tomorrow: "Tomorrow's calendar"
        }
    }

    /// Whether the list can be changed here. Yesterday is a record of what
    /// happened: its leftovers move to today, but it isn't edited.
    public var isEditable: Bool { self != .yesterday }
}
