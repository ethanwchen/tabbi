import SwiftUI
import NotchKitCore

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
}
