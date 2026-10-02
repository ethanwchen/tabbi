import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Today: the daily checklist, Up Next calendar card, focus timer, and
/// Plan my day / Wrap up.
@MainActor
final class TodayModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .planner)
    private let store: PlannerStore

    init(store: PlannerStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(PlannerPanel(store: store))
    }

    /// Focus mode follows Today's focus timer, so its settings live here.
    func makeSettingsPane() -> SettingsPane? {
        SettingsPane(id: "focus", title: "Focus", symbol: "moon", view: AnyView(FocusSettingsPane()))
    }

    /// The checklist, today's calendar events, and the focus timer.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        let id = descriptor.id
        return store.$day
            .combineLatest(store.upNext.$events, store.focus.$timer)
            .map { day, events, timer in
                ModuleProvision(tasks: day.items.map { $0.provided(by: id) }, events: events, focus: timer)
            }
            .eraseToAnyPublisher()
    }
}
