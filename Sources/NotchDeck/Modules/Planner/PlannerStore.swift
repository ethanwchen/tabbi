import Combine
import Foundation
import NotchKitCore
import SwiftUI

/// Today's checklist for the Today panel. Wraps `PlannerRepository` on the
/// main actor, saves after every edit, and rolls over to a new day (carrying
/// unfinished items) when the calendar day changes.
///
/// With `NOTCHDECK_DEMO=1` it shows `PlannerDay.sample` and never touches disk.
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
    /// Today's remaining calendar events, shown beside the checklist.
    let upNext = UpNextStore()
    /// The Pomodoro timer, shared with the Focus tab; Today shows it as a
    /// card and links checklist items to it.
    let focus: FocusStore
    /// Plan My Day; its proposal replaces the checklist while active.
    private(set) lazy var plan = DayPlanStore(upNext: upNext)
    /// The End-of-Day Review; its card replaces the checklist while open.
    let review = DayReviewStore()

    var items: [PlannerItem] { day.items }
    /// Whether Plan My Day has anything to schedule.
    var hasPlannableWork: Bool { items.contains { !$0.isDone } || !sharedWork.isEmpty }
    /// False while today's file is unreadable, so a bad file is never overwritten.
    var canEdit: Bool { !isUnreadable }

    private let repository: PlannerRepository?
    private var cancellables: Set<AnyCancellable> = []

    init(focus: FocusStore) {
        self.focus = focus
        let today = PlannerDayKey(date: Date())
        if ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1" {
            repository = nil
            day = .sample(on: today)
            return
        }
        repository = PlannerRepository()
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
            .map { $0.plannableWork(excluding: module) }
            .removeDuplicates()
            .sink { [weak self] work in
                MainActor.assumeIsolated { self?.sharedWork = work }
            }
            .store(in: &cancellables)
    }

    /// Asks Claude to schedule today's unfinished items around the calendar.
    func planMyDay() {
        review.close()
        refreshDay()
        plan.plan(tasks: items, sharedWork: sharedWork)
    }

    /// Opens the End-of-Day Review of today's list and focus sessions.
    func wrapUp() {
        plan.cancel()
        refreshDay()
        review.wrapUp(day: day, focusLog: focus.sessionLog)
    }

    // MARK: Edits

    /// Adds a task; returns false for blank titles so the field can keep its text.
    @discardableResult
    func add(_ title: String) -> Bool {
        edit { $0.add(title) != nil }
    }

    /// Adds a kit's starter tasks that aren't on today's list yet.
    func addStarterTasks(_ titles: [String]) {
        edit { !$0.addStarterTasks(titles).isEmpty }
    }

    func toggle(_ id: PlannerItem.ID) {
        edit { $0.toggle(id); return true }
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
