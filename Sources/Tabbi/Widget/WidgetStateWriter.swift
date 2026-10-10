import Combine
import Foundation
import TabbiKitCore
import WidgetKit

/// Keeps the desktop widget's shared state (`WidgetState` in the App Group
/// container) in step with the app: the pet's look from the Closet, the
/// shared focus clock and the streak and today's minutes from the activity
/// log. It writes only when what the widget shows changes and only then
/// reloads the widget's timeline, so the widget never polls (docs/widget.md).
///
/// Demo and snapshot runs write nothing, so they never show sample data in
/// the real widget.
@MainActor
final class WidgetStateWriter {
    private let file: WidgetStateFile
    private let pet: ClosetStore
    private let activityLog: ActivityLog
    private let calendar: Calendar
    private let reload: () -> Void
    private var focus: WidgetState.Timer?
    private var isScheduled = false
    private var cancellables: Set<AnyCancellable> = []

    /// Writes into `folder` and calls `reload` after each change.
    init(folder: URL, pet: ClosetStore, focus: AnyPublisher<ProvidedFocus?, Never>, activityLog: ActivityLog,
         calendar: Calendar = .current, reload: @escaping () -> Void) {
        file = WidgetStateFile(folder: folder)
        self.pet = pet
        self.activityLog = activityLog
        self.calendar = calendar
        self.reload = reload
        focus
            .map { $0.flatMap(WidgetState.Timer.init) }
            .removeDuplicates()
            .sink { [weak self] timer in
                MainActor.assumeIsolated {
                    self?.focus = timer
                    self?.scheduleWrite()
                }
            }
            .store(in: &cancellables)
        pet.profiles
            .dropFirst()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleWrite() } }
            .store(in: &cancellables)
        activityLog.recorded
            .filter(WidgetState.isFocus)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleWrite() } }
            .store(in: &cancellables)
        scheduleWrite()
    }

    /// The App Group container's writer for a live run; nil in demo and
    /// snapshot runs or when macOS has no container for the group.
    static func live(context: ModuleContext) -> WidgetStateWriter? {
        guard !context.isDemo, !context.isSnapshot, let folder = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetState.appGroup
        ) else { return nil }
        return WidgetStateWriter(
            folder: folder, pet: context.studyPet,
            focus: context.providers.$snapshot.map(\.focus).eraseToAnyPublisher(),
            activityLog: context.activityLog
        ) {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetState.widgetKind)
        }
    }

    /// Coalesces the changes one event brings (a session ending changes the
    /// clock and logs its minutes) into one write.
    private func scheduleWrite() {
        guard !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.isScheduled = false
                self?.write()
            }
        }
    }

    /// Writes the current state now; returns whether the file changed.
    @discardableResult
    func write(now: Date = Date()) -> Bool {
        let today = PlannerDayKey(date: now, calendar: calendar)
        let focusDays = WidgetState.focusDays(endingOn: today, calendar: calendar) { [activityLog] day in
            activityLog.records(on: day)
        }
        let state = WidgetState(pet: pet.profile, timer: focus, todayRecords: activityLog.records(on: today),
                                focusDays: focusDays, now: now, calendar: calendar)
        guard (try? file.write(state)) == true else { return false }
        reload()
        return true
    }
}
