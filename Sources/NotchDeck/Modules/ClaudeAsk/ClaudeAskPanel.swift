import SwiftUI
import NotchDeckCore

struct ClaudeAskPanel: View {
    @ObservedObject var session: ClaudeAskSession

    var body: some View {
        ModulePlaceholder(module: .claudeAsk, detail: "Ask Claude is coming soon")
    }
}
