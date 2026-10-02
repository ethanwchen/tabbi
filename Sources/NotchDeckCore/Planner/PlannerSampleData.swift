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
