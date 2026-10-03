import Combine
import Foundation
import NotchKitCore

/// The shared, append-only log of what happened (focus stretches, breaks,
/// cards reviewed, tasks done), for gamification, insights and the pet.
///
/// A module logs its own events with `record`, stamped with its own id, and
/// anyone reads them back by day or follows `recorded`, so nothing reaches
/// into another module's store to learn what the user did. Records persist
/// in the edition's `Activity` folder through `ActivityLogRepository` and
/// never leave the Mac. In demo and snapshot runs nothing touches disk: the
/// log lives in memory for the run.
@MainActor
final class ActivityLog {
    private let repository: ActivityLogRepository?
    private let calendar: Calendar
    /// Every record in demo and snapshot runs; otherwise only those a day
    /// file refused (unreadable on disk), so reads in this run still see them.
    private var unsaved: [ActivityRecord] = []
    private let subject = PassthroughSubject<ActivityRecord, Never>()

    /// A log saved by `repository`, or kept in memory when it is nil.
    init(repository: ActivityLogRepository?, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    /// Each record as it is logged, on the main actor.
    var recorded: AnyPublisher<ActivityRecord, Never> { subject.eraseToAnyPublisher() }

    /// Appends records and tells followers about each.
    func record(_ records: [ActivityRecord]) {
        guard !records.isEmpty else { return }
        if let repository {
            do {
                try repository.append(records)
            } catch {
                unsaved += records
            }
        } else {
            unsaved += records
        }
        records.forEach(subject.send)
    }

    func record(_ record: ActivityRecord) {
        self.record([record])
    }

    /// The records that count toward `day`, oldest first.
    func records(on day: PlannerDayKey) -> [ActivityRecord] {
        records(from: day, through: day)
    }

    /// The records of every day from `first` through `last`, oldest first.
    func records(from first: PlannerDayKey, through last: PlannerDayKey) -> [ActivityRecord] {
        let stored = repository?.records(from: first, through: last) ?? []
        let known = Set(stored.map(\.id))
        let pending = unsaved.filter {
            let day = $0.day(calendar: calendar)
            return day >= first && day <= last && !known.contains($0.id)
        }
        return (stored + pending).sorted { $0.end < $1.end }
    }
}

extension ModuleContext {
    /// The one activity log. Log what this module did with records whose
    /// `source` is `id`; read anyone's records by day.
    var activityLog: ActivityLog {
        shared.resolve {
            ActivityLog(repository: isDemo || isSnapshot ? nil : ActivityLogRepository(storage: storage))
        }
    }
}
