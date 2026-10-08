import Combine
import Foundation
import TabbiKitCore
import SwiftUI

/// Today's checklist for the Today panel. Wraps `PlannerRepository` on the
/// main actor, saves after every edit, and rolls over to a new day (carrying
/// unfinished items) when the calendar day changes.
///
/// With `TABBI_DEMO=1` it shows `PlannerDay.sample` and never touches disk.
@MainActor
final class PlannerStore: ObservableObject {
    /// Why today's list can't be shown or saved. Kept short for the UI.
    enum Problem: Equatable {
        /// Today's file exists but can't be read; editing is disabled so it isn't overwritten.
        case unreadable(fileName: String)
        /// The last edit is visible but didn't reach disk.
        case saveFailed
    }

    @Published private(set) var day: PlannerDay
    @Published private(set) var problem: Problem?
    /// Unfinished work other modules share (say, Anki reviews), which Plan
    /// My Day schedules along with the checklist. See `followSharedWork`.
    @Published private(set) var sharedWork: [String] = []
    /// Other modules' open tasks with their estimates, for the local planner.
    private(set) var sharedTasks: [ProvidedTask] = []
    /// Other modules' goals for today (say, Anki reviews), which the study
    /// planner turns into review blocks.
    private(set) var sharedProgress: [ProgressItem] = []
    /// Today's study minutes, sessions and points from the modules that keep
    /// them, for Wrap Up. Nil when no enabled module does.
    private(set) var sharedStudy: StudyDayTally?
    /// How Plan My Day works for the active kit.
    @Published var planSettings: TodayPlanSettings {
        didSet {
            plan.settings = planSettings
            if planSettings.sampleDay != oldValue.sampleDay { showSampleDay(planSettings.sampleDay) }
        }
    }
    /// Today's remaining calendar events, shown beside the checklist.
    let upNext: UpNextStore
    /// The Pomodoro timer, shared with the Focus tab; Today shows it as a
    /// card and links checklist items to it.
    let focus: FocusStore
    /// An enabled module that runs its own focus clock (Study in the Med
    /// School kit). While set, Today shows that clock instead of the
    /// Pomodoro, so the layout has one timer.
    @Published var focusClockOwner: ModuleID?
    /// The app-wide name from Settings > General, which the fresh-day
    /// message greets. Nil while the user hasn't given one.
    @Published var displayName: String?
    /// Plan My Day; its proposal replaces the checklist while active.
    private(set) lazy var plan = DayPlanStore(upNext: upNext, settings: planSettings, runMode: runMode)
    /// The End-of-Day Review; its card replaces the checklist while open.
    let review: DayReviewStore

    var items: [PlannerItem] { day.items }
    /// Whether Plan My Day has anything to schedule. The study planner
    /// always does: it fills free time with study blocks.
    var hasPlannableWork: Bool {
        planSettings.planMode == .study || items.contains { !$0.isDone } || !sharedWork.isEmpty
    }
    /// False while today's file is unreadable, so a bad file is never overwritten.
    var canEdit: Bool { !isUnreadable }

    private let repository: PlannerRepository?
    private let runMode: RunMode
    /// Where checked-off tasks are logged, as Today's.
    private let activity: ActivityLog?
    private var cancellables: Set<AnyCancellable> = []

    init(focus: FocusStore, storage: EditionStorage, planSettings: TodayPlanSettings = TodayPlanSettings(),
         activity: ActivityLog? = nil, runMode: RunMode) {
        self.focus = focus
        self.activity = activity
        self.runMode = runMode
        self.planSettings = planSettings
        upNext = UpNextStore(sampleDay: planSettings.sampleDay, runMode: runMode)
        review = DayReviewStore(storage: storage, studyPreview: planSettings.planMode == .study,
                                sampleDay: planSettings.sampleDay, runMode: runMode)
        let today = PlannerDayKey(date: Date())
        if runMode.isDemo {
            repository = nil
            day = .sample(on: today, kind: planSettings.sampleDay)
            return
        }
        repository = PlannerRepository(storage: storage)
        day = PlannerDay(date: today)
        load(today)

        // Posted at midnight, after waking past midnight, and on time zone changes.
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDay() }
            }
            .store(in: &cancellables)
    }

    /// Demo mode only: shows the sample day of a newly applied kit.
    private func showSampleDay(_ kind: PlannerSampleDay) {
        guard repository == nil else { return }
        day = .sample(on: PlannerDayKey(date: Date()), kind: kind)
        upNext.showSampleDay(kind)
    }

    /// Switches to the current calendar day if it has changed (or retries a
    /// failed load). Cheap to call whenever the panel appears.
    func refreshDay() {
        let today = PlannerDayKey(date: Date())
        guard repository != nil, today != day.date || isUnreadable else { return }
        load(today)
    }

    /// Keeps `sharedWork` in step with what other modules provide, so Today
    /// reads the merged snapshot instead of any one module's store.
    func followSharedWork(from snapshots: some Publisher<ProviderSnapshot, Never>, excluding module: ModuleID) {
        snapshots
            .map { $0.progress.filter { $0.source != module } }
            .removeDuplicates()
            .sink { [weak self] progress in
                MainActor.assumeIsolated { self?.sharedProgress = progress }
            }
            .store(in: &cancellables)
        snapshots
            .map(\.study)
            .removeDuplicates()
            .sink { [weak self] study in
                MainActor.assumeIsolated { self?.sharedStudy = study }
            }
            .store(in: &cancellables)
        snapshots
            .map { $0.openTasks.filter { $0.source != module } }
            .removeDuplicates()
            .sink { [weak self] tasks in
                MainActor.assumeIsolated { self?.sharedTasks = tasks }
            }
            .store(in: &cancellables)
        snapshots
            .map { $0.plannableWork(excluding: module) }
            .removeDuplicates()
            .sink { [weak self] work in
                MainActor.assumeIsolated { self?.sharedWork = work }
            }
            .store(in: &cancellables)
    }

    /// Schedules today's unfinished items around the calendar.
    func planMyDay() {
        review.close()
        refreshDay()
        plan.plan(tasks: items, sharedWork: sharedWork, sharedTasks: sharedTasks, progress: sharedProgress)
    }

    /// Opens the End-of-Day Review of today's list, the focus sessions in
    /// the activity log, and what other modules share (study time, points,
    /// cards reviewed).
    func wrapUp() {
        plan.cancel()
        refreshDay()
        review.wrapUp(day: day, activity: activity?.records(on: day.date) ?? [], study: sharedStudy,
                      progress: sharedProgress, isStudyDay: planSettings.planMode == .study,
                      sampleDay: planSettings.sampleDay)
    }

    // MARK: Edits

    /// Adds a task; returns false for blank titles so the field can keep its text.
    @discardableResult
    func add(_ title: String) -> Bool {
        edit { $0.add(title) != nil }
    }

    /// Adds a kit's starter tasks that aren't on today's list yet and
    /// returns them, so undoing the kit switch can take them back.
    @discardableResult
    func addStarterTasks(_ titles: [String]) -> [PlannerItem] {
        var added: [PlannerItem] = []
        edit { added = $0.addStarterTasks(titles); return !added.isEmpty }
        return added
    }

    /// Removes starter tasks `addStarterTasks` returned that the user hasn't
    /// renamed or checked off since.
    func takeBackStarterTasks(_ added: [PlannerItem]) {
        edit { $0.removeUntouched(added) }
    }

    /// Checks an item off or back on. Checking one off logs `taskCompleted`
    /// with the item's id as the subject.
    func toggle(_ id: PlannerItem.ID) {
        guard edit({ $0.toggle(id); return true }),
              let item = day.items.first(where: { $0.id == id }), item.isDone, let completedAt = item.completedAt
        else { return }
        activity?.record(ActivityRecord(source: TodayModule.descriptor.id, kind: .taskCompleted, start: completedAt,
                                        quantity: 1, subject: id.uuidString))
    }

    func rename(_ id: PlannerItem.ID, to title: String) {
        edit { $0.rename(id, to: title) }
    }

    func delete(_ id: PlannerItem.ID) {
        edit { $0.delete(id); return true }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        edit { $0.move(fromOffsets: offsets, toOffset: destination); return true }
    }

    func move(_ id: PlannerItem.ID, to index: Int) {
        edit { $0.move(id, to: index); return true }
    }

    func clearCompleted() {
        edit { $0.clearCompleted(); return true }
    }

    // MARK: Private

    private var isUnreadable: Bool {
        if case .unreadable = problem { return true }
        return false
    }

    /// Applies `change` to a copy and publishes + saves it when it reports a change.
    @discardableResult
    private func edit(_ change: (inout PlannerDay) -> Bool) -> Bool {
        guard !isUnreadable else { return false }
        // Edits always target the current day, even if midnight passed while the panel was closed.
        refreshDay()
        var updated = day
        guard change(&updated), updated != day else { return false }
        day = updated
        save()
        return true
    }

    private func load(_ date: PlannerDayKey) {
        guard let repository else { return }
        do {
            day = try repository.open(date)
            problem = nil
        } catch {
            day = PlannerDay(date: date)
            problem = .unreadable(fileName: repository.fileURL(for: date).lastPathComponent)
        }
    }

    private func save() {
        guard let repository else { return }
        do {
            try repository.save(day)
            problem = nil
        } catch {
            problem = .saveFailed
        }
    }
}
