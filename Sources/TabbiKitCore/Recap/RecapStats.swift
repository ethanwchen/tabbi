import Foundation

/// One small number on a recap card, such as "18 sessions" or "Thu best day".
public struct RecapStat: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case sessions, bestDay, streak, cards, tasks, points
    }

    public let kind: Kind
    /// The number or day, drawn large: "18", "Thu", "1,240".
    public let value: String
    /// What it counts, drawn small beneath: "sessions", "best day".
    public let label: String

    public var id: Kind { kind }

    public init(kind: Kind, value: String, label: String) {
        self.kind = kind
        self.value = value
        self.label = label
    }
}

public extension WeeklyRecap {
    /// The numbers beside the hours focused, in a fixed order. A stat with
    /// nothing to show is left out, so a light week reads as what it had
    /// rather than a row of zeros, and a one-day streak is not called one.
    func stats(calendar: Calendar = .current, locale: Locale = .current) -> [RecapStat] {
        var stats: [RecapStat] = []
        func count(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        if sessions > 0 {
            stats.append(RecapStat(kind: .sessions, value: count(sessions), label: sessions == 1 ? "session" : "sessions"))
        }
        if let best = bestDay(calendar: calendar) {
            stats.append(RecapStat(kind: .bestDay, value: Self.weekdayName(best.day, calendar: calendar, locale: locale),
                                   label: "best day"))
        }
        if longestStreak >= 2 {
            stats.append(RecapStat(kind: .streak, value: count(longestStreak), label: "day streak"))
        }
        if cardsReviewed > 0 {
            stats.append(RecapStat(kind: .cards, value: count(cardsReviewed), label: cardsReviewed == 1 ? "card" : "cards"))
        }
        if tasksDone > 0 {
            stats.append(RecapStat(kind: .tasks, value: count(tasksDone), label: tasksDone == 1 ? "task" : "tasks"))
        }
        if points > 0 {
            stats.append(RecapStat(kind: .points, value: count(points), label: points == 1 ? "point" : "points"))
        }
        return stats
    }

    /// "Thu": the day's short weekday name.
    private static func weekdayName(_ day: PlannerDayKey, calendar: Calendar, locale: Locale) -> String {
        var calendar = calendar
        calendar.locale = locale
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return calendar.shortWeekdaySymbols[weekday - 1]
    }
}

public extension RecapWeek {
    /// The week's dates for a card's corner: "Oct 5 - 11", or
    /// "Sep 28 - Oct 4" when it spans two months.
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.month(.abbreviated).day()
        let first = start.startDate(calendar: calendar)
        let last = end(calendar: calendar).startDate(calendar: calendar)
        let sameMonth = calendar.component(.month, from: first) == calendar.component(.month, from: last)
        let lastText = sameMonth ? calendar.component(.day, from: last).formatted(.number.locale(locale))
                                 : last.formatted(style)
        return "\(first.formatted(style)) - \(lastText)"
    }

    /// One-letter weekday names, Monday first, for the card's day bars.
    static func dayInitials(calendar: Calendar = .current, locale: Locale = .current) -> [String] {
        var calendar = calendar
        calendar.locale = locale
        let symbols = calendar.veryShortWeekdaySymbols
        // `weekday` 2 is Monday; the symbols start on Sunday.
        return (0..<7).map { symbols[($0 + 1) % 7] }
    }
}
