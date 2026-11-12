import Foundation

/// How Crews write hours, places and the week's countdown, the same on the
/// Mac and Windows (`shared/fixtures/crews/crews.json` pins the parts).
public enum CrewFormat {
    /// Focus time on the board in tenths of an hour, rounded down, so the
    /// board never claims time not yet studied.
    public static func tenths(minutes: Int) -> Int { max(minutes, 0) / 6 }

    /// A crew's or member's focus time: always one decimal and the localized
    /// unit ("0.5 h", "39.6 h", "39,6 Std."), in the user's own number
    /// format, as every other number in Tabbi.
    public static func hours(minutes: Int, locale: Locale = .current) -> String {
        let number = (Double(tenths(minutes: minutes)) / 10).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return String(localized: "\(number) h", bundle: .tabbi,
                      comment: "Focus hours with one decimal, e.g. 39.6 h. The number is already formatted.")
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

    /// "New week in 3d 4h", the weekly board's countdown.
    public static func countdown(_ week: CrewWeek, now: Date) -> String {
        String(localized: "New week in \(remaining(until: week.endsAt, now: now))", bundle: .tabbi,
               comment: "The weekly crew board's countdown, e.g. New week in 3d 4h.")
    }

    /// The week's end in the user's own time zone, for the countdown's tooltip.
    public static func weekEnd(_ week: CrewWeek, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: .current, timeZone: timeZone)
            .weekday(.wide)
        return week.endsAt.addingTimeInterval(-1).formatted(style)
    }

    /// A place as the language writes it: "1st" and "12th" in English,
    /// "12." in German, "第12" in Japanese, "12" in Arabic.
    public static func ordinal(_ place: Int, locale: Locale = .current) -> String {
        NumberFormatter.localizedOrdinal(place, locale: locale)
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

    /// "12 of 20 members".
    public static func members(_ count: Int, of max: Int) -> String {
        String(localized: "\(count) of \(max) members", bundle: .tabbi)
    }

    /// "9 members".
    public static func members(_ count: Int) -> String {
        String(localized: "\(count) members", bundle: .tabbi)
    }

    /// "Wk 45" (ISO week number) for a crew's history.
    public static func weekLabel(_ week: CrewWeek) -> String {
        let number = Int(week.id.split(separator: "W").last ?? "") ?? 0
        return String(localized: "Wk \(number)", bundle: .tabbi, comment: "A week of the year in a crew's history, e.g. Wk 45. Keep it short.")
    }
}

extension NumberFormatter {
    /// An ordinal ("1st", "2.", "1er") in `locale`.
    static func localizedOrdinal(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Crew and pet names on tiles and rows wrap to two lines; a long word gets
/// soft hyphens at the places the language allows a break, so it breaks
/// with a hyphen ("Bibliotheks-ratten") instead of anywhere or not at all.
public enum CrewHyphenation {
    /// Words this long or longer get break points.
    public static let minimumWord = 9

    public static func hyphenated(_ text: String, locale: Locale = .current) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in word.count >= minimumWord ? hyphenatedWord(String(word), locale: locale) : String(word) }
            .joined(separator: " ")
    }

    static func hyphenatedWord(_ word: String, locale: Locale) -> String {
        let cfWord = word as CFString
        let length = CFStringGetLength(cfWord)
        guard CFStringIsHyphenationAvailableForLocale(locale as CFLocale) else { return word }
        var breaks: [Int] = []
        var index = length
        while index > 0 {
            let found = CFStringGetHyphenationLocationBeforeIndex(cfWord, index, CFRange(location: 0, length: length),
                                                                   0, locale as CFLocale, nil)
            guard found > 1, found < length - 1, found < index else { break }
            breaks.append(found)
            index = found
        }
        guard !breaks.isEmpty else { return word }
        let units = Array(word.utf16)
        var out: [UInt16] = []
        for (offset, unit) in units.enumerated() {
            if breaks.contains(offset) { out.append(0x00AD) }
            out.append(unit)
        }
        return String(decoding: out, as: UTF16.self)
    }
}
