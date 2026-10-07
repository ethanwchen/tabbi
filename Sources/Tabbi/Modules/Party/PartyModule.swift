import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Party: study with friends on the Tabbi friends server. The module
/// owns the store, so presence keeps flowing while the notch is closed; it
/// connects when the module is enabled and goes offline when it's turned
/// off. Presence follows the shared focus timer.
@MainActor
final class PartyModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .party, title: "Party", symbol: "person.3.fill",
        summary: "Study with friends and see who is focusing now.", category: .study,
        accent: ModuleAccent(red: 1.00, green: 0.42, blue: 0.62),
        network: [ModuleNetworkAccess(host: PartyServer.productionURL.host() ?? "", purpose: "your presence and parties")],
        setup: [.party]
    )
    let store: PartyStore

    init(context: ModuleContext) {
        store = PartyStore(runMode: context.runMode)
        store.followFocus(from: context.providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        store.follow(pet: context.studyPet.profiles)
        let settings = context.settings
        store.follow(name: settings.$settings.map(\.displayName).eraseToAnyPublisher(),
                     save: { [weak settings] name in settings?.settings.displayName = name })
        shareConnection(pet: context.studyPet)
    }

    /// Lets the Connections hub show Party's row and start it from its
    /// setup sheet with just a name and a pet.
    private func shareConnection(pet: ClosetStore) {
        let store = store
        ConnectionsStore.shared.follow(
            party: store.$state.combineLatest(store.$settings)
                .map { PartyConnectionState.resolve($0.connection, friendCode: $0.friendCode,
                                                    hasChosenName: $1.cleanedName != nil) }
                .eraseToAnyPublisher(),
            name: store.$settings.combineLatest(store.$state)
                .map { $0.cleanedName ?? $1.profile?.name ?? "" }
                .eraseToAnyPublisher(),
            species: pet.profiles.map(\.species).eraseToAnyPublisher(),
            start: { [weak store, weak pet] name, species in
                pet?.setSpecies(species)
                guard let store else { return }
                var settings = store.settings
                settings.name = name
                store.update(settings)
            },
            retry: { [weak store] in store?.retry() }
        )
    }

    func makePanel() -> AnyView {
        AnyView(PartyPanel(store: store))
    }

    /// Onboarding's party step: the name friends see, my code to share,
    /// and going invisible, right in the notch.
    func makeSetupView(for step: OnboardingSetupStep, done: @escaping () -> Void) -> AnyView? {
        step == .party ? AnyView(PartyOnboardingView(store: store)) : nil
    }

    func makeSettingsPane() -> SettingsPane? {
        .party(store: store)
    }

    /// The party I'm in, so the closed notch can show members' pets by mine,
    /// and its shared session: in the Timer tab, and as the shared focus
    /// clock, so the closed notch counts it down for every member.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.provided
            .map { party in
                ModuleProvision(focus: party?.session?.focus(by: Self.descriptor.id), party: party)
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func start() {
        store.start()
    }

    func stop() {
        store.stop()
    }
}
