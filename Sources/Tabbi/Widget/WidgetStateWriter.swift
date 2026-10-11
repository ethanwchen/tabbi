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
///
/// The file itself is read and written on a background queue: macOS can
/// hold an open in the App Group container until the user answers its
/// "access data from other apps" prompt (an ad-hoc signed build always
/// asks), and that wait must never freeze the notch.
@MainActor
final class WidgetStateWriter {
    private let file: WidgetStateFile
    private let pet: ClosetStore
    private let activityLog: ActivityLog
    private let calendar: Calendar
    private let reload: () -> Void
    private var focus: WidgetState.Timer?
    private var isScheduled = false
    private let io = DispatchQueue(label: "dev.tabbi.widget-state", qos: .utility)
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

    /// Saves the current state off the main thread and reloads the widget
    /// once the file changed.
    func write(now: Date = Date()) {
        let today = PlannerDayKey(date: now, calendar: calendar)
        let focusDays = WidgetState.focusDays(endingOn: today, calendar: calendar) { [activityLog] day in
            activityLog.records(on: day)
        }
        let state = WidgetState(pet: pet.profile, timer: focus, todayRecords: activityLog.records(on: today),
                                focusDays: focusDays, now: now, calendar: calendar)
        let file = self.file
        io.async { [weak self] in
            guard (try? file.write(state)) == true else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    /// Returns once every write asked for so far has finished and reloaded
    /// the widget, for tests.
    func settle() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        await withCheckedContinuation { continuation in
            io.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
