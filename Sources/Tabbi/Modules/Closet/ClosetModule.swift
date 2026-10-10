import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Closet: the pet's page, opened from the paw at the far right of the open
/// notch header (or P) rather than a tab. Preview the study pet, rename and recolor it, and dress it in
/// items unlocked with study points. The pet itself is the shared
/// `context.studyPet`, which this module edits and hands the coach, so the
/// notch, the coach, Study and Party show the same pet.
/// The pet's study coach runs while this module is on, and its Settings
/// pane shows with it. The pet is shared as a provider, so the closed
/// notch shows it too, and dances once when a seasonal event starts.
@MainActor
final class ClosetModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .closet, title: "Closet", symbol: "pawprint.fill",
        summary: "Name your pet and dress it in items you earn.", category: .fun,
        accent: ModuleAccent(red: 0.98, green: 0.80, blue: 0.30),
        kitSettings: KitSettingsSchema([
            "coachLines": PetCoachMessages.kitSettingType,
            "pet": PetProfile.kitSettingType,
        ]),
        setup: [.pet],
        headerShortcut: ModuleHeaderShortcut(label: "Your pet", key: "p")
    )
    let store: ClosetStore
    /// The weekly recaps, listed in the Closet's Weeks section.
    let recaps: RecapStore
    /// The pet's study coach: nudges from the notch during focus phases.
    let coach: PetCoachController
    /// The daily study reminder in the pet's voice.
    let reminder: StudyReminderScheduler
    /// The pet's little dance when a seasonal event starts.
    let greeter: SeasonalEventGreeter

    init(context: ModuleContext) {
        let settings = context.settings
        let store = context.studyPet
        let focus = context.focusTimer
        coach = PetCoachController(
            storage: context.storage,
            runMode: context.runMode,
            profile: { [store] in store.profile },
            lines: { PetCoachMessages.lines(kitSettings: settings.activeKit?.defaults.settings(for: .closet)) },
            screen: {
                NotchGeometry.screen(for: settings.settings.preferredDisplay,
                                     showOnExternalDisplays: settings.settings.showOnExternalDisplays)
            },
            pauseTimer: { focus.pause() },
            resumeTimer: { focus.start() }
        )
        self.store = store
        reminder = StudyReminderScheduler(storage: context.storage, runMode: context.runMode, pet: store,
                                          progress: context.providers.$snapshot.map(\.progress).eraseToAnyPublisher())
        recaps = context.weeklyRecaps
        greeter = SeasonalEventGreeter(storage: context.storage, runMode: context.runMode,
                                       celebrations: context.celebrations, now: { [store] in store.seasonNow })
        coach.follow(focus: context.providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        coach.follow(awards: store.awards.eraseToAnyPublisher())
    }

    func start() {
        coach.start()
        reminder.start()
        greeter.start()
    }

    func stop() {
        coach.stop()
        reminder.stop()
        greeter.stop()
    }

    func makeSettingsPane() -> SettingsPane? { .petCoach(coach, reminder: reminder) }

    /// Shares the pet, so the closed notch can show it.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$presence.map { ModuleProvision(pet: $0) }.eraseToAnyPublisher()
    }

    func makePanel() -> AnyView {
        AnyView(ClosetPanel(store: store, recaps: recaps))
    }

    /// Onboarding's pet step: species, breed and name on the shared pet.
    func makeSetupView(for step: OnboardingSetupStep, done: @escaping () -> Void) -> AnyView? {
        step == .pet ? AnyView(ClosetSetupView(store: store)) : nil
    }
}

extension ModuleContext {
    /// The one study pet: its look, points and save
    /// (`<edition>/Pet/pet.json`). The Closet edits it and the coach, Study
    /// and Party show it, so no other module reads the save. It earns points
    /// from the shared focus clock and, until first saved, follows the
    /// active kit's starter pet.
    var studyPet: ClosetStore {
        shared.resolve {
            let store = ClosetStore(storage: storage, runMode: runMode, starter: .starter(kit: activeKit?.defaults),
                                    celebrations: celebrations)
            store.follow(focus: providers.$snapshot.map(\.focus).eraseToAnyPublisher())
            let today = PlannerDayKey(date: .now)
            store.follow(activity: activityLog.recorded,
                         history: activityLog.records(from: PlannerDayKey(date: .distantPast), through: today))
            store.follow(kits: kitApplied)
            return store
        }
    }
}
