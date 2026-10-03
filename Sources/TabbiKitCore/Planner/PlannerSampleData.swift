import Foundation

/// Which realistic day demo mode (`TABBI_DEMO=1`) shows on Today: the
/// checklist, calendar and wrap-up summary. A kit picks one with
/// `moduleSettings.planner.sampleDay`, so a study kit's screenshots show
/// its users' day instead of an office one.
public enum PlannerSampleDay: String, Hashable, Sendable, CaseIterable {
    /// Pull requests, a design standup and a beta review.
    case work
    /// A medical student's day: a lecture, a lab, clinical skills and question banks.
    case medicine
}

public extension PlannerDay {
    /// A realistic, partly finished day for demo mode (`TABBI_DEMO=1`),
    /// used for snapshots and screenshots. Never touches disk. The first
    /// unfinished item always has the same id, so the demo focus timer links
    /// to it whichever day `kind` is.
    static func sample(
        on date: PlannerDayKey,
        kind: PlannerSampleDay = .work,
        calendar: Calendar = .current
    ) -> PlannerDay {
        let start = date.startDate(calendar: calendar)
        func at(_ hour: Int, _ minute: Int) -> Date {
            start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        let entries: [(title: String, created: Date, completed: Date?)] = switch kind {
        case .work: [
            ("Review Ana's pull request", at(8, 40), at(9, 25)),
            ("Reply to design feedback on the onboarding flow", at(8, 45), at(10, 5)),
            ("Ship notch planner beta", at(9, 0), nil),
            ("Book flights for the offsite", at(9, 10), at(11, 30)),
            ("30-minute run", at(9, 15), nil),
        ]
        case .medicine: [
            ("Read First Aid: cardiac pathology", at(7, 30), at(9, 40)),
            ("Watch the heart failure lecture recording", at(7, 35), at(11, 15)),
            ("UWorld cardio Qs", at(7, 40), nil),
            ("Email Dr. Patel about Friday's shift", at(7, 45), at(12, 5)),
            ("Renal notes", at(7, 50), nil),
        ]
        }
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
}

public extension UpcomingEvent {
    /// Realistic events around `now` for demo mode: one meeting under way
    /// with a Meet link, a Zoom call shortly after, and a plain block later.
    /// Times are relative to `now` so badges always read naturally, and land
    /// on five-minute marks like real meetings do. `kind` picks the titles:
    /// a work day's standup and review, or a medical student's lecture, lab
    /// and clinical skills session.
    static func samples(now: Date, kind: PlannerSampleDay = .work) -> [UpcomingEvent] {
        let minute: TimeInterval = 60
        let slotLength = 5 * minute
        let slot = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate / slotLength).rounded(.down) * slotLength)
        let work = EventColor(red: 0.20, green: 0.55, blue: 0.98)
        let personal = EventColor(red: 0.98, green: 0.62, blue: 0.20)
        if kind == .medicine {
            let school = EventColor(red: 0.36, green: 0.78, blue: 0.47)
            let clinical = EventColor(red: 0.93, green: 0.35, blue: 0.38)
            return [
                UpcomingEvent(
                    id: "demo-lecture",
                    title: "Cardiology lecture",
                    start: slot.addingTimeInterval(-10 * minute),
                    end: slot.addingTimeInterval(20 * minute),
                    calendarColor: school,
                    meetingLink: MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/5551234567")!)
                ),
                UpcomingEvent(
                    id: "demo-lab",
                    title: "Anatomy lab: thorax",
                    start: slot.addingTimeInterval(30 * minute),
                    end: slot.addingTimeInterval(90 * minute),
                    calendarColor: school
                ),
                UpcomingEvent(
                    id: "demo-skills",
                    title: "Clinical skills session",
                    start: slot.addingTimeInterval(200 * minute),
                    end: slot.addingTimeInterval(260 * minute),
                    calendarColor: clinical
                ),
            ]
        }
        return [
            UpcomingEvent(
                id: "demo-standup",
                title: "Design standup",
                start: slot.addingTimeInterval(-10 * minute),
                end: slot.addingTimeInterval(20 * minute),
                calendarColor: work,
                meetingLink: MeetingLink(provider: .googleMeet, url: URL(string: "https://meet.google.com/abc-defg-hij")!)
            ),
            UpcomingEvent(
                id: "demo-review",
                title: "Notch planner beta review",
                start: slot.addingTimeInterval(15 * minute),
                end: slot.addingTimeInterval(45 * minute),
                calendarColor: work,
                meetingLink: MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/5551234567")!)
            ),
            UpcomingEvent(
                id: "demo-run",
                title: "30-minute run",
                start: slot.addingTimeInterval(95 * minute),
                end: slot.addingTimeInterval(125 * minute),
                calendarColor: personal
            ),
        ]
    }
}
