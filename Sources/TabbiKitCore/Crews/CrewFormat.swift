import Foundation

/// How Crews write hours, ranks and the week's countdown, the same on the
/// Mac and Windows (`shared/fixtures/crews/crews.json` pins the English).
public enum CrewFormat {
    /// How a number of minutes reads on the board: whole hours from 10
    /// hours up, otherwise tenths of an hour. Hours round down, so the board
    /// never claims time not yet studied.
    public enum Hours: Hashable, Sendable {
        case tenths(Int)
        case whole(Int)
    }

    public static func hoursValue(minutes: Int) -> Hours {
        let minutes = max(minutes, 0)
        return minutes >= 600 ? .whole(minutes / 60) : .tenths(minutes / 6)
    }

    /// A crew's or member's focus time on the board: "0.5 h", "4.2 h", "12 h".
    public static func hours(minutes: Int, locale: Locale = .current) -> String {
        switch hoursValue(minutes: minutes) {
        case .whole(let hours):
            return String(localized: "\(hours) h", bundle: .tabbi)
        case .tenths(let tenths):
            let number = (Double(tenths) / 10).formatted(.number.precision(.fractionLength(1)).locale(locale))
            return String(localized: "\(number) h", bundle: .tabbi,
                          comment: "Focus hours with one decimal, e.g. 4.5 h. The number is already formatted.")
        }
    }

    /// The time left in the week, in the largest two units that matter.
    public enum Remaining: Hashable, Sendable {
        case lessThanAMinute
        case minutes(Int)
        case hoursMinutes(Int, Int)
        case daysHours(Int, Int)
    }

    public static func remainingValue(until end: Date, now: Date) -> Remaining {
        let minutes = Int(max(0, end.timeIntervalSince(now)) / 60)
        if minutes < 1 { return .lessThanAMinute }
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return .daysHours(days, hours) }
        if hours > 0 { return .hoursMinutes(hours, rest) }
        return .minutes(rest)
    }

    /// The time left in the week, short: "2d 5h", "5h 12m", "12m", "<1m".
    public static func remaining(until end: Date, now: Date) -> String {
        switch remainingValue(until: end, now: now) {
        case .lessThanAMinute: String(localized: "<1m", bundle: .tabbi)
        case .minutes(let minutes): String(localized: "\(minutes)m", bundle: .tabbi)
        case .hoursMinutes(let hours, let minutes): String(localized: "\(hours)h \(minutes)m", bundle: .tabbi)
        case .daysHours(let days, let hours): String(localized: "\(days)d \(hours)h", bundle: .tabbi)
        }
    }

    /// "Ends in 2d 5h", the header's countdown.
    public static func countdown(_ week: CrewWeek, now: Date) -> String {
        String(localized: "Ends in \(remaining(until: week.endsAt, now: now))", bundle: .tabbi)
    }

    /// When the countdown text next changes, so a view can tick exactly
    /// then instead of every second.
    public static func nextChange(_ week: CrewWeek, now: Date) -> Date {
        let left = week.endsAt.timeIntervalSince(now)
        guard left > 0 else { return week.endsAt }
        let step: TimeInterval = left >= 86_400 ? 3600 : 60
        let remainder = left.truncatingRemainder(dividingBy: step)
        return now.addingTimeInterval(remainder > 0 ? remainder : step)
    }

    /// "#3" on a crew page.
    public static func rank(_ rank: Int) -> String {
        String(localized: "#\(rank)", bundle: .tabbi, comment: "A place on the weekly crew board, e.g. #3.")
    }

    /// "12 of 20" members.
    public static func members(_ count: Int, of max: Int) -> String {
        String(localized: "\(count) of \(max)", bundle: .tabbi)
    }
}
