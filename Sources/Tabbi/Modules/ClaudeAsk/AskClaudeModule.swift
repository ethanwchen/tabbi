import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Ask AI: a quick question to the AI the user picked in Connections
/// (Claude first among them), answered in the notch.
@MainActor
final class AskClaudeModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeAsk, title: "Ask AI", symbol: "sparkles",
        summary: "Ask Claude, Gemini or another AI a quick question.", category: .ai,
        accent: .claude, permissions: [.claudeCLI],
        network: AIProviderID.allNetworkAccess
    )
    /// Internal so snapshot runs can show the history list.
    let session: ClaudeAskSession
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        session = ClaudeAskSession(runMode: context.runMode, storage: context.storage, ai: context.ai)
        // A new provider, key or `claude` path in Settings must take effect
        // live, not on the next launch.
        context.ai.$setupState.dropFirst()
            .sink { [session] state in session.prepare(state) }
            .store(in: &cancellables)
        context.settings.$appliedClaudePathOverride.dropFirst()
            .sink { [session] _ in session.prepare() }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeAskPanel(session: session))
    }

    func makeSettingsPane() -> SettingsPane? {
        .claudeAsk(session)
    }
}
