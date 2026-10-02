import EventKit
import NotchKitCore

/// Writes accepted Plan My Day blocks into the user's default calendar, so
/// any account added in Internet Accounts (iCloud, Google, Exchange) works
/// without setup. All events are committed together or not at all.
struct EventKitPlanWriter: PlanCalendarWriting {
    enum Failure: LocalizedError {
        case noDefaultCalendar

        var errorDescription: String? { "There's no default calendar to add events to." }
    }

    let store: EKEventStore

    func write(_ events: [PlannedCalendarEvent]) throws {
        guard let calendar = store.defaultCalendarForNewEvents else { throw Failure.noDefaultCalendar }
        do {
            for planned in events {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = planned.title
                event.startDate = planned.start
                event.endDate = planned.end
                event.notes = planned.notes
                try store.save(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }
    }
}

/// Accepts blocks without touching the calendar: demo mode, and
/// `NOTCHDECK_PLAN_DRY_RUN=1` runs that print what would be written.
struct DryRunPlanWriter: PlanCalendarWriting {
    let logs: Bool

    func write(_ events: [PlannedCalendarEvent]) throws {
        guard logs else { return }
        for event in events {
            print("[plan dry run] \(event.start.formatted(date: .omitted, time: .shortened))-"
                + "\(event.end.formatted(date: .omitted, time: .shortened)) \(event.title) (\(event.notes))")
        }
    }
}
