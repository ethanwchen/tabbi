import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Closet: preview the study pet, rename and recolor it, and dress it in
/// items unlocked with study points. The pet itself lives in `ClosetStore`,
/// which this module owns and hands the coach, so the notch and the coach
/// show the same pet.
/// The pet's study coach runs while this module is on, and its Settings
/// pane shows with it. The pet is shared as a provider, so the closed
/// notch shows it too.
@MainActor
final class ClosetModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .closet, title: "Closet", symbol: "pawprint.fill", category: .fun,
        accent: ModuleAccent(red: 0.98, green: 0.80, blue: 0.30),
        kitSettings: KitSettingsSchema([
            "coachLines": PetCoachMessages.kitSettingType,
            "pet": PetProfile.kitSettingType,
        ])
    )
    let store: ClosetStore
    /// The pet's study coach: nudges from the notch during focus phases.
    let coach: PetCoachController
    private var kitSubscription: AnyCancellable?

    init(context: ModuleContext) {
        let settings = context.settings
        let store = ClosetStore(storage: context.storage, runMode: context.runMode,
                                starter: .starter(kit: context.activeKit?.defaults))
        let focus = context.focusTimer
        coach = PetCoachController(
            storage: context.storage,
            runMode: context.runMode,
            profile: { [store] in store.profile },
            lines: { PetCoachMessages.lines(kitSettings: settings.activeKit?.defaults.settings(for: .closet)) },
            screen: { NotchGeometry.screen(for: settings.settings.preferredDisplay) },
            pauseTimer: { focus.pause() },
            resumeTimer: { focus.start() }
        )
        self.store = store
        let timers = context.providers.$snapshot.map(\.focus).eraseToAnyPublisher()
        coach.follow(focus: timers)
        store.follow(focus: timers)
        coach.follow(awards: store.awards.eraseToAnyPublisher())
        // Until the pet is saved, it is the active kit's starter pet.
        kitSubscription = context.kitApplied
            .sink { [store] in store.useStarter(.starter(kit: $0.kit.defaults)) }
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
