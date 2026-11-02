import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › AI Usage, in the sandboxed App Store build only: which
    /// folders AI Usage may read and whose usage it shows.
    @MainActor static func aiUsage(store: ClaudeUsageStore, folders: AIUsageFolderAccess) -> SettingsPane {
        SettingsPane(id: "aiUsage", title: String(localized: "AI Usage", bundle: .tabbi),
                     symbol: ClaudeUsageModule.descriptor.symbol,
                     view: AnyView(AIUsageSettingsPane(store: store, folders: folders)))
    }
}

/// The folders the sandboxed AI Usage reads, each with Choose (or Change)
/// and Remove, and the tool the panel shows. Removing a folder forgets its
/// bookmark, so Tabbi can't read it again until it is chosen again.
struct AIUsageSettingsPane: View {
    @ObservedObject var store: ClaudeUsageStore
    @ObservedObject var folders: AIUsageFolderAccess

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Show usage for", bundle: .tabbi), selection: Binding(
                    get: { store.source }, set: { store.setSource($0) })) {
                    ForEach([AIUsageSource.claudeCode, .codex], id: \.self) { source in
                        Text(source.toolName).tag(source)
                    }
                }
                .help(String(localized: "Pick whose usage to show", bundle: .tabbi))
            }
            Section {
                folderRow(.claudeCode)
                folderRow(.codex)
            } header: {
                Text("Usage logs", bundle: .tabbi)
            } footer: {
                SectionFooter(String(localized: "Tabbi reads only token counts, model names and Codex's plan limits from these folders, and nothing leaves your Mac. Remove a folder to stop Tabbi from reading it.", bundle: .tabbi))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: 268)
    }

    private func folderRow(_ source: AIUsageSource) -> some View {
        let grant = folders.grants[source]
        return LabeledContent {
            HStack(spacing: 8) {
                Text(grant.map { AIUsageFolder.displayPath($0.picked) } ?? String(localized: "Not chosen", bundle: .tabbi))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if grant != nil {
                    Button(String(localized: "Remove", bundle: .tabbi)) { store.removeFolder(source) }
                        .help(String(localized: "Stop reading this folder", bundle: .tabbi))
                }
                Button(grant == nil ? String(localized: "Choose…", bundle: .tabbi) : String(localized: "Change…", bundle: .tabbi)) {
                    if store.source != source { store.setSource(source) }
                    store.pickFolder()
                }
                .help(String(localized: "Choose the \(AIUsageFolder.toolFolderName(for: source)) folder in your home folder", bundle: .tabbi))
            }
        } label: {
            Text(source.toolName)
        }
    }
}
