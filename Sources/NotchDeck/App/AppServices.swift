import Combine
import SwiftUI

/// Long-lived state for every module, created once at launch and shared with
/// all views through the environment. Each module owns its own store class
/// inside `Modules/<Module>/`; add new stores here.
@MainActor
final class AppServices: ObservableObject {
    let spotify = SpotifyController()
    let system = SystemMonitor()
    let claudeUsage = ClaudeUsageStore()
    let planner = PlannerStore()
    let claudeAsk = ClaudeAskSession()

    /// True when some module wants a live activity beside the closed notch.
    @Published private(set) var hasCompactActivity = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        spotify.$showsCompactActivity
            .removeDuplicates()
            .assign(to: &$hasCompactActivity)
    }
}
