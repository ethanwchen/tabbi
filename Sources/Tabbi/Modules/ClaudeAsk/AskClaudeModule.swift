import Combine
import SwiftUI
import TabbiKitCore

/// Ask Claude: a quick question to the local `claude` CLI, answered in the notch.
@MainActor
final class AskClaudeModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .claudeAsk, title: "Ask Claude", symbol: "sparkles",
        summary: "Ask Claude a quick question from the notch.", category: .ai,
        accent: .claude, permissions: [.claudeCLI]
    )
    private let session: ClaudeAskSession
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        session = ClaudeAskSession(runMode: context.runMode)
        // A new `claude` path in Settings must take effect live, not on the
        // next launch.
        context.settings.$appliedClaudePathOverride
            .dropFirst()
            .sink { [session] _ in session.claudePathDidChange() }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeAskPanel(session: session))
    }
}
