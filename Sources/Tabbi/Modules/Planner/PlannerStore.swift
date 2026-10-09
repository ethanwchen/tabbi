import Combine
import Foundation
import TabbiKitCore
import SwiftUI

/// Today's checklist for the Today panel. Wraps `PlannerRepository` on the
/// main actor, saves after every edit, and rolls over to a new day (carrying
/// unfinished items) when the calendar day changes.
///
/// The panel can also step to yesterday (to see what was left and move it
/// to today) or tomorrow (to plan ahead). `day` is always today, which is
/// what other modules, Plan my day and Wrap up see; `shownDay` is the one on
/// screen, and the list's edits go there.
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

    /// Today's list, whichever day the panel shows.
    @Published private(set) var day: PlannerDay
    /// Why today's list can't be shown or saved.
    @Published private(set) var problem: Problem?
    /// The day the checklist shows. Back to today when the day changes.
    @Published private(set) var viewing: PlannerViewedDay = .today
    /// Yesterday's or tomorrow's list while `viewing` names it.
    @Published private(set) var otherDay: PlannerDay?
    /// Why `otherDay` can't be shown or saved.
    @Published private(set) var otherProblem: Problem?
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
    private(set) lazy var plan = DayPlanStore(upNext: upNext, settings: planSettings, usesClaude: usesClaude,
                                              runMode: runMode)
    /// The End-of-Day Review; its card replaces the checklist while open.
    let review: DayReviewStore

    /// The list on screen: today's, or the day `viewing` steps to.
    var shownDay: PlannerDay {
        viewing == .today ? day : otherDay ?? PlannerDay(date: viewing.key(today: day.date))
    }
    /// The shown day's items, which the checklist lists.
    var items: [PlannerItem] { shownDay.items }
    /// Why the shown day's list can't be shown or saved.
    var shownProblem: Problem? { viewing == .today ? problem : otherProblem }
    /// Yesterday's unfinished items that aren't on today's list yet, which
    /// the panel offers to move there. Empty unless yesterday is shown.
    var leftovers: [PlannerItem] {
        viewing == .yesterday ? shownDay.unfinished(missingFrom: day) : []
    }
    /// Whether Plan My Day has anything to schedule. The study planner
    /// always does: it fills free time with study blocks.
    var hasPlannableWork: Bool {
        planSettings.planMode == .study || day.items.contains { !$0.isDone } || !sharedWork.isEmpty
    }
    /// Whether the shown list can change: not yesterday's, which is a
    /// record, and not while its file is unreadable, so a bad file is never
    /// overwritten.
    var canEdit: Bool { viewing.isEditable && !shownProblem.isUnreadable }

    private let repository: PlannerRepository?
    private let runMode: RunMode
    /// Whether Plan my day and Wrap up may ask the `claude` CLI
    /// (`Edition.runsLocalTools`).
    private let usesClaude: Bool
    /// Where checked-off tasks are logged, as Today's.
    private let activity: ActivityLog?
    /// Demo mode's yesterday and tomorrow, so edits to them last the session.
    private var demoDays: [PlannerDayKey: PlannerDay] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(focus: FocusStore, storage: EditionStorage, planSettings: TodayPlanSettings = TodayPlanSettings(),
         activity: ActivityLog? = nil, usesClaude: Bool = true, runMode: RunMode) {
        self.focus = focus
        self.activity = activity
        self.runMode = runMode
        self.usesClaude = usesClaude
        self.planSettings = planSettings
        upNext = UpNextStore(sampleDay: planSettings.sampleDay, runMode: runMode)
        review = DayReviewStore(storage: storage, studyPreview: planSettings.planMode == .study,
                                sampleDay: planSettings.sampleDay, usesClaude: usesClaude, runMode: runMode)
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
        demoDays = [:]
        upNext.showSampleDay(kind)
        loadOtherDay()
    }

    /// Switches to the current calendar day if it has changed (or retries a
    /// failed load), and then shows today. Cheap to call whenever the panel
    /// appears.
    func refreshDay() {
        let today = PlannerDayKey(date: Date())
        guard repository != nil, today != day.date || problem.isUnreadable else { return }
        load(today)
        viewing = .today
        loadOtherDay()
    }

    /// Shows `viewed` in the checklist, reading its list fresh. Plan my day
    /// and Wrap up close, since both are about today.
    func show(_ viewed: PlannerViewedDay) {
        refreshDay()
        if viewed != .today {
            plan.cancel()
            review.close()
        }
        viewing = viewed
        loadOtherDay()
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
        show(.today)
        plan.plan(tasks: day.items, sharedWork: sharedWork, sharedTasks: sharedTasks, progress: sharedProgress)
    }

    /// Opens the End-of-Day Review of today's list, the focus sessions in
    /// the activity log, and what other modules share (study time, points,
    /// cards reviewed).
    func wrapUp() {
        plan.cancel()
        show(.today)
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
        editToday { added = $0.addStarterTasks(titles); return !added.isEmpty }
        return added
    }

    /// Removes starter tasks `addStarterTasks` returned that the user hasn't
    /// renamed or checked off since.
    func takeBackStarterTasks(_ added: [PlannerItem]) {
        editToday { $0.removeUntouched(added) }
    }

    /// Moves yesterday's leftovers with these ids (all of them when nil) to
    /// the end of today's list. Yesterday's file keeps them as they were, so
    /// it still tells what happened that day.
    func moveToToday(_ ids: Set<PlannerItem.ID>? = nil) {
        let moving = leftovers.filter { ids?.contains($0.id) ?? true }
        guard !moving.isEmpty else { return }
        editToday { !$0.adopt(moving).isEmpty }
    }

    /// Checks an item off or back on. Checking one off logs `taskCompleted`
    /// with the item's id as the subject.
    func toggle(_ id: PlannerItem.ID) {
        guard edit({ $0.toggle(id); return true }),
              let item = shownDay.items.first(where: { $0.id == id }), item.isDone, let completedAt = item.completedAt
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

    /// Applies `change` to a copy of the shown day and publishes + saves it
    /// when it reports a change.
    @discardableResult
    private func edit(_ change: (inout PlannerDay) -> Bool) -> Bool {
        // A new day since the panel opened shows today again, so an edit never lands on a stale day.
        refreshDay()
        guard canEdit else { return false }
        var updated = shownDay
        guard change(&updated), updated != shownDay else { return false }
        if viewing == .today { day = updated } else { otherDay = updated }
        save(updated)
        return true
    }

    /// Like `edit`, but always on today's list, whichever day is shown.
    @discardableResult
    private func editToday(_ change: (inout PlannerDay) -> Bool) -> Bool {
        refreshDay()
        guard !problem.isUnreadable else { return false }
        var updated = day
        guard change(&updated), updated != day else { return false }
        day = updated
        save(updated)
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

    /// Reads the day `viewing` names other than today, without creating its
    /// file: `peek` gives tomorrow as a planned-ahead day, so it still takes
    /// in today's leftovers when it comes.
    private func loadOtherDay() {
        otherProblem = nil
        guard viewing != .today else {
            otherDay = nil
            return
        }
        let date = viewing.key(today: day.date)
        guard let repository else {
            otherDay = demoDays[date] ?? .sample(viewing, today: day.date, kind: planSettings.sampleDay)
            return
        }
        do {
            otherDay = try repository.peek(date, today: day.date)
        } catch {
            otherDay = PlannerDay(date: date)
            otherProblem = .unreadable(fileName: repository.fileURL(for: date).lastPathComponent)
        }
    }

    /// Writes `updated` to its file (or demo mode's memory) and records
    /// whether that worked for the list it belongs to.
    private func save(_ updated: PlannerDay) {
        let isToday = updated.date == day.date
        guard let repository else {
            if !isToday { demoDays[updated.date] = updated }
            return
        }
        let result: Problem?
        do {
            try repository.save(updated)
            result = nil
        } catch {
            result = .saveFailed
        }
        if isToday { problem = result } else { otherProblem = result }
    }
}

extension PlannerStore.Problem? {
    /// True for a file that can't be read, which is never overwritten.
    var isUnreadable: Bool {
        if case .unreadable = self { return true }
        return false
    }
}
