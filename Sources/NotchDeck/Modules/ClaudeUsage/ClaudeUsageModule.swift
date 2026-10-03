import Combine
import SwiftUI
import NotchKitCore

/// Claude Usage: rate-limit windows and local token stats from the `claude` CLI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeUsage, title: "Claude Usage", symbol: "gauge.with.dots.needle.67percent", category: .ai,
        accent: .claude, permissions: [.claudeCLI]
    )
    /// Read by the closed-notch ticker until Claude Usage provides its
    /// highlight like every other module (review B3).
    let store = ClaudeUsageStore()
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        // A new `claude` path in Settings must take effect live, not on the
        // next launch.
        context.settings.$appliedClaudePathOverride
            .dropFirst()
            .sink { [store] _ in store.claudePathDidChange() }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeUsagePanel(store: store))
    }
}
