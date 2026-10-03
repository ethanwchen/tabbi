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
        accent: ModuleAccent(red: 0.66, green: 0.55, blue: 1.00), permissions: [.calendars, .notifications]
    )
    private let store: PlannerStore

    init(store: PlannerStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(PlannerPanel(store: store))
    }

    /// Today embeds the focus timer, so it offers the focus mode settings
    /// too (as the Focus tab does).
    func makeSettingsPane() -> SettingsPane? { .focus }

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
