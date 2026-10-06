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

    /// Seven days from `date`'s: today's items, then a plausible week of
    /// meetings, workouts and planned blocks, with work kept off weekends.
    public static func weekItems(from date: Date, calendar: Calendar = .current) -> [ScheduleItem] {
        let work = EventColor(red: 0.20, green: 0.55, blue: 0.98)
        let personal = EventColor(red: 0.98, green: 0.62, blue: 0.20)
        var result = items(on: date, calendar: calendar)
        for offset in 1..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else {
                continue
            }
            func item(_ id: String, _ title: String, _ start: Int, _ end: Int, kind: ScheduleItem.Kind = .event,
                      color: EventColor? = nil) -> ScheduleItem {
                ScheduleItem(id: "demo-\(offset)-\(id)", title: title, start: time(start, on: day, calendar: calendar),
                             end: time(end, on: day, calendar: calendar), kind: kind, calendarColor: color)
            }
            if calendar.isDateInWeekend(day) {
                result += [item("brunch", "Brunch", 11 * 60, 12 * 60 + 30, color: personal),
                           item("hike", "Hike", 14 * 60, 17 * 60, color: personal)]
                continue
            }
            result.append(item("standup", "Design standup", 10 * 60, 10 * 60 + 30, color: work))
            switch offset % 3 {
            case 1:
                result += [item("focus", "Write the spec", 9 * 60, 9 * 60 + 50, kind: .planned),
                           item("1on1", "1:1 with Alex", 11 * 60, 11 * 60 + 30, color: work),
                           item("workshop", "Roadmap workshop", 13 * 60, 15 * 60 + 30, color: work)]
            case 2:
                result += [item("interview", "Interview", 11 * 60 + 30, 12 * 60 + 30, color: work),
                           item("reviews", "Anki reviews", 13 * 60 + 30, 14 * 60, kind: .planned),
                           item("gym", "Gym", 17 * 60 + 30, 18 * 60 + 30, color: personal)]
            default:
                result += [item("planning", "Sprint planning", 13 * 60, 14 * 60 + 30, color: work),
                           item("dentist", "Dentist", 16 * 60, 17 * 60, color: personal)]
            }
        }
        return result
    }

    static func time(_ minutes: Int, on date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: date)) ?? date
    }
}
