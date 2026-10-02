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
    /// The rotating live preview beside the closed notch.
    let ticker: TickerStore
    /// Every tab this build can show. Register new modules here.
    let modules: ModuleRegistry
    /// What the enabled modules share (tasks, events, progress, focus).
    let providers: ProviderHub

    private var cancellables: Set<AnyCancellable> = []
    /// Created on first use so launching never builds a window nobody opens.
    private var settingsWindow: SettingsWindowController?

    init(settings: SettingsStore) {
        self.settings = settings
        planner = PlannerStore(focus: focus)
        study = StudyStore(menu: StudyMethodMenu(kit: settings.activeKit?.defaults))
        modules = ModuleRegistry([
            NowPlayingModule(controller: spotify),
            SystemModule(monitor: system),
            ClaudeUsageModule(store: claudeUsage),
            TodayModule(store: planner),
            AskClaudeModule(session: claudeAsk),
            FocusModule(store: focus),
            StudyModule(store: study),
            AnkiModule(),
            PartyModule(),
            ClosetModule(),
        ])
        providers = ProviderHub(registry: modules)
        planner.followSharedWork(from: providers.$snapshot, excluding: .planner)
        study.followCards(from: providers.$snapshot)
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
        // Kit defaults that live outside `AppSettings`.
        settings.kitApplied
            .sink { [planner, study] application in
                MainActor.assumeIsolated {
                    let focus = FocusController.shared
                    focus.settings = focus.settings.applying(application.kit.defaults)
                    study.use(StudyMethodMenu(kit: application.kit.defaults), kitApplied: true)
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
