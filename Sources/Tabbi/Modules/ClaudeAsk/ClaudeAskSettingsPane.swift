import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Ask AI: when answers open in the large view, and where
    /// chats are kept.
    @MainActor static func claudeAsk(_ session: ClaudeAskSession) -> SettingsPane {
        SettingsPane(id: "claudeAsk", title: String(localized: "Ask AI", bundle: .tabbi), symbol: "sparkles",
                     view: AnyView(ClaudeAskSettingsPane(session: session)))
    }
}

/// Settings › Ask AI. Edits go straight to `ClaudeAskSession`, which
/// saves them.
struct ClaudeAskSettingsPane: View {
    @ObservedObject var session: ClaudeAskSession

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Open answers in the large view", bundle: .tabbi), selection: $session.preferences.largeView) {
                    ForEach(ClaudeAskLargeView.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help(String(localized: "Whether a question grows the notch into the larger chat view", bundle: .tabbi))
            } header: {
                Text("Answers", bundle: .tabbi)
            } footer: {
                SectionFooter(footer)
            }

            Section {
                LabeledContent(String(localized: "Saved chats", bundle: .tabbi)) {
                    Text(session.savedChats.count, format: .number)
                        .monospacedDigit()
                }
            } header: {
                Text("History", bundle: .tabbi)
            } footer: {
                SectionFooter(String(localized: "Chats stay on this Mac, in \(Edition.current.name)'s own folder. Delete them from History in the Ask AI tab.", bundle: .tabbi))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: 280)
    }

    private var footer: String {
        switch session.preferences.largeView {
        case .askEachTime: String(localized: "Answers stay in the notch. Press Command-Return to send and expand, or click Expand on a chat.", bundle: .tabbi)
        case .always: String(localized: "Every question opens a larger chat view under the notch. Press Esc to go back.", bundle: .tabbi)
        case .never: String(localized: "Chats always stay in the notch.", bundle: .tabbi)
        }
    }
}
