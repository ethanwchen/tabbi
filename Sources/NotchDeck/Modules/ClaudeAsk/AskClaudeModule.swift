import SwiftUI
import NotchKitCore

/// Ask Claude: a quick question to the local `claude` CLI, answered in the notch.
@MainActor
final class AskClaudeModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeAsk, title: "Ask Claude", symbol: "sparkles", category: .ai,
        accent: .claude, permissions: [.claudeCLI]
    )
    private let session: ClaudeAskSession

    init(session: ClaudeAskSession) {
        self.session = session
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeAskPanel(session: session))
    }
}
