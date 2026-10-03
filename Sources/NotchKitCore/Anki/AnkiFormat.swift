import Foundation

/// Text and scales for the Anki tab, kept here so the panel's wording and
/// heatmap shading are testable without SwiftUI.
public enum AnkiFormat {
    /// Heatmap shades, from no reviews (0) to the busiest day (4).
    public static let heatLevels = 4

    /// One shade per day of `history`, scaled to the busiest day so a light
    /// week still shows its shape. Any day with reviews gets at least 1, so
    /// a short session never looks like a missed day.
    public static func heatLevels(for history: [AnkiDayCount]) -> [Int] {
        let busiest = history.map(\.count).max() ?? 0
        guard busiest > 0 else { return history.map { _ in 0 } }
        return history.map { entry in
            guard entry.count > 0 else { return 0 }
            let scaled = Int((Double(entry.count) / Double(busiest) * Double(heatLevels)).rounded(.up))
            return min(max(scaled, 1), heatLevels)
        }
    }

    /// "12-day streak", "1-day streak", or "No streak yet".
    public static func streak(_ days: Int) -> String {
        days > 0 ? "\(days)-day streak" : "No streak yet"
    }

    /// Tooltip for one heatmap cell: "Today · 112 reviews", "Mon, Sep 30 · No reviews".
    public static func dayHelp(_ entry: AnkiDayCount, today: AnkiDay, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let count: String
        switch entry.count {
        case 0: count = "No reviews"
        case 1: count = "1 review"
        default: count = "\(entry.count) reviews"
        }
        return "\(dayName(entry.day, today: today, calendar: calendar, locale: locale)) · \(count)"
    }

    /// "Today", "Yesterday", or a short weekday and date.
    public static func dayName(_ day: AnkiDay, today: AnkiDay, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if day == today { return "Today" }
        if day == today.adding(days: -1) { return "Yesterday" }
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return day.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }

    /// The ring's tooltip: "112 of 432 cards reviewed today".
    public static func progressHelp(_ summary: AnkiSummary) -> String {
        if summary.dueTotal == 0 {
            return summary.reviewedToday > 0 ? "All \(summary.reviewedToday) cards done for today" : "Nothing due today"
        }
        return "\(summary.reviewedToday) of \(summary.reviewedToday + summary.dueTotal) cards reviewed today"
    }

    /// How old the numbers are: "just now", "5m ago", "2h ago", "3d ago".
    public static func age(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
