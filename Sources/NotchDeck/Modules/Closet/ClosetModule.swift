import SwiftUI
import NotchKitCore
import NotchKit

/// Closet: preview the study pet, rename and recolor it, and dress it in
/// items unlocked with study points. The pet itself lives in `ClosetStore`,
/// which `AppServices` owns so the notch and the coach show the same pet.
/// The pet's study coach runs while this module is on, and its Settings
/// pane shows with it.
@MainActor
final class ClosetModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .closet)
    private let store: ClosetStore
    private let coach: PetCoachController

    init(store: ClosetStore, coach: PetCoachController) {
        self.store = store
        self.coach = coach
    }

    func start() { coach.start() }
    func stop() { coach.stop() }

    func makeSettingsPane() -> SettingsPane? { .petCoach(coach) }

    func makePanel() -> AnyView {
        AnyView(ClosetPanel(store: store))
    }
}
