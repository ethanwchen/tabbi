import Combine
import SwiftUI
import TabbiKitCore

/// Usage: rate-limit windows and local token stats from the `claude` CLI,
/// or from the Codex CLI's logs while Codex is the chosen AI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeUsage, title: "AI Usage", symbol: "gauge.with.dots.needle.67percent",
        summary: "How much of your Claude or Codex plan you have used.", category: .ai,
        accent: .claude, permissions: [.claudeCLI], highlightTitle: "AI usage above 80%"
    )
    private let store: ClaudeUsageStore
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        let ai = context.ai
        store = ClaudeUsageStore(storage: context.storage, runMode: context.runMode,
                                 source: AIUsageSource.source(for: ai.setupState.provider))
        ai.$setupState
            .map { AIUsageSource.source(for: $0.provider) }
            .removeDuplicates()
            .dropFirst()
            .sink { [store] in store.setSource($0) }
            .store(in: &cancellables)
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
            .combineLatest(store.$source)
            .map { limits, source in
                ModuleProvision(highlights: ClaudeUsageHighlights.highlights(
                    for: limits?.snapshot, at: Date(), usage: source))
            }
            .eraseToAnyPublisher()
    }
}
