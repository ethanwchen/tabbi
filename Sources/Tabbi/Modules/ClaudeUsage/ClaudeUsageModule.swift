import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Usage: rate-limit windows and local token stats from the `claude` CLI,
/// or from the Codex CLI's logs while Codex is the chosen AI.
@MainActor
final class ClaudeUsageModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeUsage, title: String(localized: "AI Usage", bundle: .tabbi), symbol: "gauge.with.dots.needle.67percent",
        summary: String(localized: "How much of your Claude or Codex plan you have used.", bundle: .tabbi), category: .ai,
        accent: .claude, permissions: permissions, highlightTitle: String(localized: "AI usage above 80%", bundle: .tabbi)
    )
    /// The direct download runs the claude CLI for live limits; the App
    /// Store build only reads the folders the user picks.
    #if APPSTORE
    private nonisolated static let permissions: Set<ModulePermission> = []
    #else
    private nonisolated static let permissions: Set<ModulePermission> = [.claudeCLI]
    #endif
    let store: ClaudeUsageStore
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        let ai = context.ai
        // Sandboxed, nothing runs the CLI and the user picks what to show,
        // since no command line AI can be the chosen one there.
        if context.edition.isSandboxed {
            store = ClaudeUsageStore(storage: context.storage, runMode: context.runMode,
                                     folders: AIUsageFolderAccess(runMode: context.runMode))
            return
        }
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

    /// Sandboxed, the folders AI Usage may read and which tool it shows.
    func makeSettingsPane() -> SettingsPane? {
        guard let folders = store.folders else { return nil }
        return .aiUsage(store: store, folders: folders)
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
