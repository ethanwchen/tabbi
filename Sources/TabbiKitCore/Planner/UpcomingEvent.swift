import Foundation

/// A calendar color as plain sRGB components, so Core stays free of AppKit.
public struct EventColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One calendar event as the Today panel's "Up next" card sees it.
///
/// The app maps `EKEvent`s into this value type so selection, badges, and
/// join-link detection can be tested without EventKit.
public struct UpcomingEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarColor: EventColor?
    /// Video call to join, found by `MeetingLink.detect` in the event's fields.
    public var meetingLink: MeetingLink?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarColor: EventColor? = nil,
        meetingLink: MeetingLink? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.meetingLink = meetingLink
    }

    /// Whether the event is under way at `now` (started, not yet ended).
    public func isInProgress(at now: Date) -> Bool {
        start <= now && now < end
    }
}

/// Where an upcoming event stands relative to now, for the row badge.
public enum EventTiming: Hashable, Sendable {
    /// Under way right now.
    case now
    /// Starts in this many whole minutes (rounded up, at least 1).
    case startsIn(minutes: Int)
}

public extension UpcomingEvent {
    /// Picks the events worth showing under "Up next": timed events that
    /// haven't ended yet, soonest first, capped at `limit`.
    ///
    /// All-day events are skipped because they have no "next" moment and
    /// would push real meetings off a three-row card. Events in progress sort
    /// first since they start earliest.
    static func upNext(from events: [UpcomingEvent], at now: Date, limit: Int = 3) -> [UpcomingEvent] {
        Array(
            events
                .filter { !$0.isAllDay && $0.end > now }
                .sorted { ($0.start, $0.end, $0.title, $0.id) < ($1.start, $1.end, $1.title, $1.id) }
                .prefix(max(limit, 0))
        )
    }

    func timing(at now: Date) -> EventTiming {
        if start <= now { return .now }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return .startsIn(minutes: max(minutes, 1))
    }
}

/// Short strings for the "Up next" card.
public enum UpcomingEventFormat {
    /// Badge text: "now", "in 12 min", "in 1h", "in 2h 5m".
    public static func badge(_ timing: EventTiming) -> String {
        switch timing {
        case .now: "now"
        case .startsIn(let minutes): DurationFormat.countdown(minutes: minutes)
        }
    }

    /// Start time in the user's clock style, e.g. "9:30" or "21:30".
    ///
    /// The AM/PM marker is dropped because a same-day list reads fine without
    /// it and the row is narrow; 24-hour locales keep their format.
    public static func startTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        let template = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: locale) ?? "HH:mm"
        let uses12Hour = template.contains("a") || template.contains("h") || template.contains("K")
        formatter.dateFormat = uses12Hour ? "h:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    /// Empty-title events (common for quick-adds) still need a readable row.
    public static func title(_ event: UpcomingEvent) -> String {
        let trimmed = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled event" : trimmed
    }
}
