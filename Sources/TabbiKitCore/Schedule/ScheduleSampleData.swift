import Foundation

/// The Schedule's demo day: a few meetings, a run and two blocks Tabbi
/// planned, at fixed times on the day containing `date`, seen from 11:20.
///
/// Fixed clock times (rather than ones relative to now, as Up next uses)
/// keep the timeline realistic whatever hour a demo or snapshot runs.
public enum ScheduleSampleData {
    /// The moment the demo day is seen from: 11:20 on `date`'s day.
    public static func now(on date: Date, calendar: Calendar = .current) -> Date {
        time(11 * 60 + 20, on: date, calendar: calendar)
    }

    public static func items(on date: Date, calendar: Calendar = .current) -> [ScheduleItem] {
        let work = EventColor(red: 0.20, green: 0.55, blue: 0.98)
        let personal = EventColor(red: 0.98, green: 0.62, blue: 0.20)
        func item(_ id: String, _ title: String, _ start: Int, _ end: Int, kind: ScheduleItem.Kind = .event,
                  color: EventColor? = nil, reason: String? = nil, link: MeetingLink? = nil) -> ScheduleItem {
            ScheduleItem(id: "demo-\(id)", title: title, start: time(start, on: date, calendar: calendar),
                         end: time(end, on: date, calendar: calendar), kind: kind, calendarColor: color,
                         reason: reason, meetingLink: link)
        }
        return [
            item("reviews", "Anki reviews", 9 * 60 + 15, 9 * 60 + 50, kind: .planned,
                 reason: "Reviews first while you're fresh"),
            item("standup", "Design standup", 10 * 60, 10 * 60 + 30, color: work,
                 link: MeetingLink(provider: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)),
            item("deck", "Draft the launch deck", 10 * 60 + 45, 12 * 60, kind: .planned,
                 reason: "High priority, due today"),
            item("lunch", "Lunch with Sam", 12 * 60 + 30, 13 * 60 + 30, color: personal),
            item("review", "Beta review", 14 * 60, 15 * 60, color: work,
                 link: MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/5551234567")!)),
            item("sync", "Partner sync", 14 * 60 + 30, 15 * 60 + 15, color: work),
            item("run", "30-minute run", 17 * 60 + 15, 17 * 60 + 45, color: personal),
            ScheduleItem(id: "demo-holiday", title: "Payday", start: time(0, on: date, calendar: calendar),
                         end: time(24 * 60, on: date, calendar: calendar), isAllDay: true),
        ]
    }

    static func time(_ minutes: Int, on date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: date)) ?? date
    }
}
