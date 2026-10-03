import Combine
import SwiftUI
import TabbiKitCore

/// Claude Usage: rate-limit windows and local token stats from the `claude` CLI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeUsage, title: "Claude Usage", symbol: "gauge.with.dots.needle.67percent", category: .ai,
        accent: .claude, permissions: [.claudeCLI], highlightTitle: "Claude usage above 80%"
    )
    private let store: ClaudeUsageStore
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        store = ClaudeUsageStore(storage: context.storage, runMode: context.runMode)
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

    /// A rate-limit window above 80% for the closed-notch ticker.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$limits
            .map { ModuleProvision(highlights: ClaudeUsageHighlights.highlights(for: $0?.snapshot, at: Date())) }
            .eraseToAnyPublisher()
    }
}
