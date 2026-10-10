import Foundation

/// Party's age screen. Party (and a Tabbi account) is for people 13 and
/// older: the Terms and Privacy Policy say so, and COPPA forbids collecting
/// a child's data without a parent's verifiable consent, which Tabbi has
/// no way to get. So before Party talks to the friends server for the first
/// time, it asks for the month and year the user was born.
///
/// The question is neutral, as the FTC's COPPA guidance asks: it doesn't
/// say which answer lets you in, and someone told they are too young can't
/// just answer again. Only the day the user is surely old enough
/// (`eligibleFrom`) is kept, in `PartySettings` on this Mac; neither the
/// birth date nor the answer ever goes to the server.
public enum PartyAgeCheck {
    public static let minimumAge = 13

    /// The calendar the question is asked and answered in. Birth years are
    /// Gregorian whatever the Mac's calendar is: a Japanese, Hebrew,
    /// Islamic or Persian system calendar would offer years (and, for
    /// Hebrew, 13 months) that `eligibleFrom` can't read, so nobody using
    /// one could ever pass.
    public static var birthCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        return calendar
    }

    /// The month picker's names, January first, in the user's language.
    public static func monthNames(locale: Locale = .current) -> [String] {
        var calendar = birthCalendar
        calendar.locale = locale
        return calendar.monthSymbols
    }

    /// The answer as picked: a month (1 to 12) and a year.
    public struct Birth: Equatable, Sendable {
        public let month: Int
        public let year: Int

        public init(month: Int, year: Int) {
            self.month = month
            self.year = year
        }
    }

    public enum Status: Equatable, Sendable {
        /// Not asked yet: Party waits for the answer.
        case unanswered
        /// Under 13 when asked; Party stays off on this Mac until `until`.
        case tooYoung(until: Date)
        /// Old enough: Party may connect.
        case passed
    }

    /// The first day someone born in `month` of `year` is surely
    /// `minimumAge`: the first of the month after their 13th birthday's
    /// month, since the day isn't asked. Nil for a month or year that
    /// can't be a birth date.
    public static func eligibleFrom(birthMonth month: Int, year: Int, calendar: Calendar = birthCalendar) -> Date? {
        guard (1...12).contains(month), year > 1900 else { return nil }
        guard let birthMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        return calendar.date(byAdding: DateComponents(year: minimumAge, month: 1), to: birthMonth)
    }

    /// Where someone stands at `now`, from what `eligibleFrom` saved.
    public static func status(eligibleFrom: Date?, at now: Date) -> Status {
        guard let eligibleFrom else { return .unanswered }
        return eligibleFrom <= now ? .passed : .tooYoung(until: eligibleFrom)
    }

    /// The years the birth year picker offers, newest first: this year
    /// back a century, so every answer is possible and none is suggested.
    public static func birthYears(at now: Date, calendar: Calendar = birthCalendar) -> [Int] {
        let year = calendar.component(.year, from: now)
        return Array(stride(from: year, through: year - 100, by: -1))
    }

    /// When Party opens for someone too young, as the panel says it
    /// ("May 2028").
    public static func opensText(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
            .month(.wide).year(.defaultDigits)
        return date.formatted(style)
    }
}
