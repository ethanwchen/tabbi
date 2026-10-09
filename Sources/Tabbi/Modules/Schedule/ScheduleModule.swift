import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

extension ModuleID {
    static let schedule: ModuleID = "schedule"
}

/// Schedule: today's calendar and planned blocks on a timeline, with what is
/// on now and what is free, and a Plan button that fills the free time with
/// other modules' open tasks and reviews. Opt in from Add More; no kit turns it on.
@MainActor
final class ScheduleModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .schedule, title: "Schedule", symbol: "calendar.day.timeline.left",
        summary: "Your day on a timeline, with the free time in between.", category: .productivity,
        accent: ModuleAccent(red: 1.00, green: 0.50, blue: 0.42), permissions: [.calendars]
    )
    /// Internal so app tests can check what Schedule shows.
    let store: ScheduleStore
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        store = ScheduleStore(usesClaude: context.edition.runsLocalTools, runMode: context.runMode)
        // Plan uses Today's planning settings, so a kit sizes reviews and
        // buffers the same way in both places.
        store.planSettings = TodayPlanSettings(kit: context.activeKit?.defaults)
        context.kitApplied
            .sink { [store] in store.planSettings = TodayPlanSettings(kit: $0.kit.defaults) }
            .store(in: &cancellables)
        context.providers.$snapshot
            .sink { [store] snapshot in
                store.sharedTasks = snapshot.openTasks
                store.progress = snapshot.progress
            }
            .store(in: &cancellables)
    }

    /// Sets the Day view's day, and a plan for it, for one snapshot.
    func showForSnapshot(_ day: PlannerViewedDay, planning: Bool = false) {
        store.showForSnapshot(day, planning: planning)
    }

    func makePanel() -> AnyView {
        AnyView(SchedulePanel(store: store))
    }
}
