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
    private var completionSubscription: AnyCancellable?
    private var identitySubscription: AnyCancellable?
    /// Kept alive here: the notification center holds its delegate weakly.
    private let notifications: PartyNotifications?

    init(context: ModuleContext) {
        store = PartyStore(runMode: context.runMode)
        let notifications = PartyNotifications.make(runMode: context.runMode)
        self.notifications = notifications
        store.followFocus(from: context.providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        store.follow(pet: context.studyPet.profiles)
        let settings = context.settings
        store.follow(name: settings.$settings.map(\.displayName).eraseToAnyPublisher(),
                     save: { [weak settings] name in settings?.settings.displayName = name })
        shareConnection(pet: context.studyPet)
        identitySubscription = context.accountSync.identityChanged.sink { [weak store] in
            MainActor.assumeIsolated { store?.identityDidChange() }
        }
        let pet = context.studyPet, log = context.activityLog, celebrations = context.celebrations
        completionSubscription = store.completedSessions.sink { [weak store] completion in
            MainActor.assumeIsolated {
                guard let store else { return }
                // A closed or hidden notch shows no banner or confetti, so
                // macOS tells the user instead.
                let notify = celebrations.isShowing ? nil : notifications?.post
                _ = Self.finish(completion, pet: pet, log: log, party: store, notify: notify)
                celebrations.celebrate(.burst, style: .confetti, accent: Self.descriptor.accentColor,
                                       from: Self.descriptor.id)
            }
        }
    }

    /// A shared session ran to its end with me in it: the pet earns the
    /// shared points, the activity log records the focus stretch, and the
    /// Party panel says "Great job, team!" with the points earned. `notify`
    /// gets the same message when the notch can't show it.
    @discardableResult
    static func finish(_ completion: PartySessionCompletion, pet: ClosetStore, log: ActivityLog,
                       party: PartyStore? = nil, notify: ((PartyTeamCelebration) -> Void)? = nil,
                       at date: Date = Date()) -> PetStudyAward? {
        if let record = completion.activityRecord(source: descriptor.id) { log.record(record) }
        let award = pet.credit(completion)
        let celebration = PartyTeamCelebration(completion: completion, points: award?.points ?? 0,
                                               petName: pet.profile.name, date: date)
        party?.celebrate(celebration)
        notify?(celebration)
        return award
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
