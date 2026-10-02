import Combine
import SwiftUI

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
    let planner = PlannerStore()
    let claudeAsk = ClaudeAskSession()
    /// The rotating live preview beside the closed notch.
    let ticker: TickerStore

    private var cancellables: Set<AnyCancellable> = []
    /// Created on first use so launching never builds a window nobody opens.
    private var settingsWindow: SettingsWindowController?

    init(settings: SettingsStore) {
        self.settings = settings
        ticker = TickerStore(settings: settings, spotify: spotify, planner: planner, claudeUsage: claudeUsage)
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
        let controller = settingsWindow ?? SettingsWindowController(settings: settings)
        settingsWindow = controller
        controller.present()
    }
}
