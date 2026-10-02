import SwiftUI
import NotchKitCore

/// Ask Claude: a quick question to the local `claude` CLI, answered in the notch.
@MainActor
final class AskClaudeModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .claudeAsk)
    private let session: ClaudeAskSession

    init(session: ClaudeAskSession) {
        self.session = session
    }

    func makePanel() -> AnyView {
        AnyView(ClaudeAskPanel(session: session))
    }
}
