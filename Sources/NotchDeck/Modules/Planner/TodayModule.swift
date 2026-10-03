import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Today: the daily checklist, Up Next calendar card, focus timer, and
/// Plan my day / Wrap up.
@MainActor
final class TodayModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .planner, title: "Today", symbol: "checklist", category: .productivity,
        accent: ModuleAccent(red: 0.66, green: 0.55, blue: 1.00), permissions: [.calendars, .notifications],
        kitSettings: TodayPlanSettings.kitSchema
    )
    /// Internal so app tests can check what Today shows.
    let store: PlannerStore
    private let providers: ProviderHub
    private let focusMode: FocusController
    /// The starter tasks the last kit switch added, which undoing it takes back.
    private var starterTasksAdded: [PlannerItem] = []
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        let settings = context.settings
        if !context.isDemo {
            // Older builds kept every edition's checklist and reviews in the
            // default edition's folder; bring them along once. Live snapshots
            // too: they open today's file, which would otherwise create the
            // folder empty and skip this for good.
            context.storage.adoptFolders([PlannerRepository.folderName, DayReviewRepository.folderName],
                                         from: EditionStorage(edition: .notchDeck))
        }
        store = PlannerStore(focus: context.focusTimer, storage: context.storage,
                             planSettings: TodayPlanSettings(kit: context.activeKit?.defaults),
                             activity: context.activityLog, runMode: context.runMode)
        providers = context.providers
        focusMode = context.focusMode
        store.followSharedWork(from: context.providers.$snapshot, excluding: context.id)
        // `$settings` emits before the new value is stored, so read the kit
        // id from the emission.
        settings.$settings
            .map(\.kitID)
            .removeDuplicates()
            .sink { [store] id in
                store.planSettings = TodayPlanSettings(kit: settings.kits.kit(id)?.defaults)
            }
            .store(in: &cancellables)
        settings.$settings
            .map { settings.catalog.focusClockOwner(in: $0.modules) }
            .removeDuplicates()
            .sink { [store] in store.focusClockOwner = $0 }
            .store(in: &cancellables)
        context.kitApplied
            .sink { [weak self, store] application in
                // Also when re-applying the same kit, which may have been re-imported.
                store.planSettings = TodayPlanSettings(kit: application.kit.defaults)
                switch application.kind {
                case .switched:
                    self?.starterTasksAdded = store.addStarterTasks(application.kit.starterTasks(answers: application.answers))
                case .undo:
                    store.takeBackStarterTasks(self?.starterTasksAdded ?? [])
                    self?.starterTasksAdded = []
                case .reset:
                    break
                }
            }
            .store(in: &cancellables)
        // Keep the calendar reloading while the closed notch can show the
        // next meeting, so events added since the panel was open show up.
        context.closedNotchPreview.$watchedKinds
            .map { $0.contains(.meeting) }
            .removeDuplicates()
            .sink { [upNext = store.upNext] in upNext.setPreviewWatching($0) }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(PlannerPanel(store: store, providers: providers))
    }

    /// Today embeds the focus timer, so it offers the focus mode settings
    /// too (as the Focus tab does).
    func makeSettingsPane() -> SettingsPane? { .focus(focusMode) }

    /// The checklist, today's calendar events, and the focus timer.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        let id = descriptor.id
        return store.$day
            .combineLatest(store.upNext.$events, store.focus.$timer)
            .map { day, events, timer in
                ModuleProvision(tasks: day.items.map { $0.provided(by: id) }, events: events,
                                 focus: timer.provided(by: id))
            }
            .eraseToAnyPublisher()
    }
}
