import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Ask Claude: when answers open in the large view, and where
    /// chats are kept.
    @MainActor static func claudeAsk(_ session: ClaudeAskSession) -> SettingsPane {
        SettingsPane(id: "claudeAsk", title: "Ask Claude", symbol: "sparkles",
                     view: AnyView(ClaudeAskSettingsPane(session: session)))
    }
}

/// Settings › Ask Claude. Edits go straight to `ClaudeAskSession`, which
/// saves them.
struct ClaudeAskSettingsPane: View {
    @ObservedObject var session: ClaudeAskSession

    var body: some View {
        Form {
            Section {
                Picker("Open answers in the large view", selection: $session.preferences.largeView) {
                    ForEach(ClaudeAskLargeView.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help("Whether a question grows the notch into the larger chat view")
            } header: {
                Text("Answers")
            } footer: {
                Footer(footer)
            }

            Section {
                LabeledContent("Saved chats") {
                    Text(session.savedChats.count, format: .number)
                        .monospacedDigit()
                }
            } header: {
                Text("History")
            } footer: {
                Footer("Chats stay on this Mac, in \(Edition.current.name)'s own folder. Delete them from History in the Ask Claude tab.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: 280)
    }

    private var footer: String {
        switch session.preferences.largeView {
        case .askEachTime: "Answers stay in the notch. Press Command-Return to send and expand, or click Expand on a chat."
        case .always: "Every question opens a larger chat view under the notch. Press Esc to go back."
        case .never: "Chats always stay in the notch."
        }
    }
}

/// Explanatory text under a grouped section, aligned with the section's rows.
private struct Footer: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
