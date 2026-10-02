import Foundation

public extension PlannerDay {
    /// A realistic, partly finished day for demo mode (`NOTCHDECK_DEMO=1`),
    /// used for snapshots and screenshots. Never touches disk.
    static func sample(on date: PlannerDayKey, calendar: Calendar = .current) -> PlannerDay {
        let start = date.startDate(calendar: calendar)
        func at(_ hour: Int, _ minute: Int) -> Date {
            start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        let entries: [(title: String, created: Date, completed: Date?)] = [
            ("Review Ana's pull request", at(8, 40), at(9, 25)),
            ("Reply to design feedback on the onboarding flow", at(8, 45), at(10, 5)),
            ("Ship notch planner beta", at(9, 0), nil),
            ("Book flights for the offsite", at(9, 10), at(11, 30)),
            ("30-minute run", at(9, 15), nil),
        ]
        let items = entries.enumerated().map { index, entry in
            PlannerItem(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                title: entry.title,
                isDone: entry.completed != nil,
                createdAt: entry.created,
                completedAt: entry.completed
            )
        }
        return PlannerDay(date: date, items: items)
    }

    /// Short progress caption for the panel header, e.g. "3 of 5 done".
    var progressSummary: String {
        if items.isEmpty { return "Nothing planned" }
        if doneCount == items.count { return "All \(items.count) done" }
        return "\(doneCount) of \(items.count) done"
    }
}

public extension UpcomingEvent {
    /// Realistic events around `now` for demo mode: one meeting under way
    /// with a Meet link, a Zoom call shortly after, and a plain block later.
    /// Times are relative to `now` so badges always read naturally.
    static func samples(now: Date) -> [UpcomingEvent] {
        let minute: TimeInterval = 60
        let work = EventColor(red: 0.20, green: 0.55, blue: 0.98)
        let personal = EventColor(red: 0.98, green: 0.62, blue: 0.20)
        return [
            UpcomingEvent(
                id: "demo-standup",
                title: "Design standup",
                start: now.addingTimeInterval(-10 * minute),
                end: now.addingTimeInterval(5 * minute),
                calendarColor: work,
                meetingLink: MeetingLink(provider: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)
            ),
            UpcomingEvent(
                id: "demo-review",
                title: "Notch planner beta review",
                start: now.addingTimeInterval(12 * minute),
                end: now.addingTimeInterval(42 * minute),
                calendarColor: work,
                meetingLink: MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/5551234567")!)
            ),
            UpcomingEvent(
                id: "demo-run",
                title: "30-minute run",
                start: now.addingTimeInterval(95 * minute),
                end: now.addingTimeInterval(125 * minute),
                calendarColor: personal
            ),
        ]
    }
}
