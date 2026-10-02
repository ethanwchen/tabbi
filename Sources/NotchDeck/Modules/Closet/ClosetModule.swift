import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Closet: preview the study pet, rename and recolor it, and dress it in
/// items unlocked with study points. The pet itself lives in `ClosetStore`,
/// which `AppServices` owns so the notch and the coach show the same pet.
/// The pet's study coach runs while this module is on, and its Settings
/// pane shows with it. The pet is shared as a provider, so the closed
/// notch shows it too.
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

    /// Shares the pet, so the closed notch can show it.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$presence.map { ModuleProvision(pet: $0) }.eraseToAnyPublisher()
    }

    func makePanel() -> AnyView {
        AnyView(ClosetPanel(store: store))
    }
}
