import SwiftUI
import NotchDeckCore

struct ClaudeUsagePanel: View {
    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        ModulePlaceholder(module: .claudeUsage, detail: "Claude usage is coming soon")
    }
}
