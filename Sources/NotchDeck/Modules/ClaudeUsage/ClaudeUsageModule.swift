import SwiftUI
import NotchKitCore

/// Claude Usage: rate-limit windows and local token stats from the `claude` CLI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeUsage, title: "Claude Usage", symbol: "gauge.with.dots.needle.67percent", category: .ai,
        accent: .claude, permissions: [.claudeCLI]
    )
    private let store: ClaudeUsageStore

    init(store: ClaudeUsageStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeUsagePanel(store: store))
    }
}
