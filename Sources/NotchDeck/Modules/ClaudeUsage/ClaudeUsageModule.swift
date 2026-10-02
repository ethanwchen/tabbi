import SwiftUI
import NotchKitCore

/// Claude Usage: rate-limit windows and local token stats from the `claude` CLI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .claudeUsage)
    private let store: ClaudeUsageStore

    init(store: ClaudeUsageStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeUsagePanel(store: store))
    }
}
