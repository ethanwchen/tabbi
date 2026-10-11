import Foundation

/// A span of days in the locale's own order and words: "Oct 5 - 11" or
/// "Sep 28 - Oct 4" in English, "5.-11. Okt." in German, "10月5日～11日"
/// in Japanese. The locale's interval pattern decides what repeats, so no
/// language gets an English template. Its en and em dashes become a plain
/// hyphen, the one Tabbi writes everywhere.
public enum DateRangeFormat {
    /// The days from `first` to `last` (both shown), as month and day, with
    /// the years only when they differ.
    public static func days(from first: Date, to last: Date,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
        var calendar = calendar
        calendar.locale = locale
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = "MMMd"
        return plain(formatter.string(from: first, to: max(first, last)))
    }

    /// Thin and narrow spaces as plain ones, en and em dashes as hyphens.
    static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
    }
}
