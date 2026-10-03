import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Long-lived state for every module, created once at launch and shared with
/// all views through the environment. Each module owns its own store class
/// inside `Modules/<Module>/`; add new stores here.
@MainActor
final class AppServices: ObservableObject {
    /// Passed in (not created here) so the saved settings, e.g. the `claude`
    /// path override, are applied before any module store starts up.
    let settings: SettingsStore
    let spotify = SpotifyController()
    let system = SystemMonitor()
    let claudeUsage = ClaudeUsageStore()
    /// The Pomodoro timer, shown by both Today and Focus. It lives here so
    /// it keeps running while the notch is closed or either tab is off.
    let focus = FocusStore()
    let planner: PlannerStore
    /// The Study tab's timer, kept running while the notch is closed.
    let study: StudyStore
    let claudeAsk = ClaudeAskSession()
    /// The study pet's look and points, shared by the Closet tab and the pet
    /// in the notch.
    let closet = ClosetStore()
    /// The pet's study coach: nudges from the notch during focus phases.
    let coach: PetCoachController
    /// Friends and study parties; presence follows the shared focus timer.
    let party = PartyStore()
    /// The rotating live preview beside the closed notch.
    let ticker: TickerStore
    /// Every tab this build can show, created from `ModuleList`.
    let modules: ModuleRegistry
    /// What the enabled modules share (tasks, events, progress, focus).
    let providers: ProviderHub

    private var cancellables: Set<AnyCancellable> = []
    /// Created on first use so launching never builds a window nobody opens.
    private var settingsWindow: SettingsWindowController?

    init(settings: SettingsStore) {
        self.settings = settings
        let kit = settings.activeKit?.defaults
        planner = PlannerStore(focus: focus, planSettings: TodayPlanSettings(kit: kit))
        study = StudyStore(menu: StudyMethodMenu(kit: kit), goal: StudyDailyGoal(kit: kit))
        coach = PetCoachController(
            profile: { [closet] in closet.profile },
            lines: { [settings] in PetCoachMessages.lines(kitSettings: settings.activeKit?.defaults.settings(for: .closet)) },
            screen: { [settings] in NotchGeometry.screen(for: settings.settings.preferredDisplay) },
            pauseTimer: { [focus] in focus.pause() },
            resumeTimer: { [focus] in focus.start() }
        )
        modules = ModuleRegistry([
            NowPlayingModule(controller: spotify),
            SystemModule(monitor: system),
            ClaudeUsageModule(store: claudeUsage),
            TodayModule(store: planner),
            AskClaudeModule(session: claudeAsk),
            FocusModule(store: focus),
            StudyModule(store: study),
            AnkiModule(),
            PartyModule(store: party),
            ClosetModule(store: closet, coach: coach),
        ])
        assert(modules.catalog == settings.catalog,
               "AppServices must create exactly the modules in ModuleList, in order")
        providers = ProviderHub(registry: modules)
        planner.followSharedWork(from: providers.$snapshot, excluding: .planner)
        study.followCards(from: providers.$snapshot)
        coach.follow(focus: providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        closet.follow(focus: providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        coach.follow(awards: closet.awards.eraseToAnyPublisher())
        party.followFocus(from: providers.$snapshot.map(\.focus).eraseToAnyPublisher())
        ticker = TickerStore(settings: settings, spotify: spotify, providers: providers,
                             upNext: planner.upNext, claudeUsage: claudeUsage)
        // `$settings` emits before the new value is stored, so read the
        // layout from the emission.
        settings.$settings
            .map(\.modules.enabled)
            .removeDuplicates()
            .sink { [modules, providers] enabled in
                modules.update(enabled: enabled)
                providers.update(enabled: enabled)
            }
            .store(in: &cancellables)
        settings.$settings
            .map(\.kitID)
            .removeDuplicates()
            .sink { [planner, settings] id in
                MainActor.assumeIsolated {
                    planner.planSettings = TodayPlanSettings(kit: settings.kits.kit(id)?.defaults)
                }
            }
            .store(in: &cancellables)
        // Kit defaults that live outside `AppSettings`.
        settings.kitApplied
            .sink { [planner, study] application in
                MainActor.assumeIsolated {
                    // Also when re-applying the same kit, which may have been re-imported.
                    planner.planSettings = TodayPlanSettings(kit: application.kit.defaults)
                    let focus = FocusController.shared
                    focus.settings = focus.settings.applying(application.kit.defaults)
                    let kit = application.kit.defaults
                    study.use(StudyMethodMenu(kit: kit), goal: StudyDailyGoal(kit: kit), kitApplied: true)
                    if application.addsStarterTasks {
                        planner.addStarterTasks(application.kit.starterTasks(answers: application.answers))
                    }
                }
            }
            .store(in: &cancellables)
        // A new `claude` path in Settings must reach both Claude modules
        // live, not on the next launch.
        settings.$appliedClaudePathOverride
            .dropFirst()
            .sink { [claudeUsage, claudeAsk] _ in
                claudeUsage.claudePathDidChange()
                claudeAsk.claudePathDidChange()
            }
            .store(in: &cancellables)
    }

    /// Shows the Settings window (from the notch's gear button or context menu).
    func openSettings() {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings, modules: modules)
        settingsWindow = controller
        controller.present()
    }
}
