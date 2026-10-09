import AppKit
import SwiftUI
import TabbiKitCore

extension AIService {
    /// The tabs with AI features (Ask, Plan my day and Day review, the
    /// Schedule's Refine); Connections shows the AI choice while one is on.
    static let featureModules: [ModuleID] = [.claudeAsk, .planner, .schedule]
}

/// Settings > Connections > AI: which provider answers, and the one thing
/// it still needs (a key, an install, a sign-in). "None" is a real choice
/// and the default, since nothing may be sent before the user picks.
struct AIProviderSection: View {
    @ObservedObject var ai: AIService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Section {
            Picker("Answers from", selection: choice) {
                Text("None").tag(AIProviderID?.none)
                ForEach(ai.availableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(Optional(provider))
                }
            }
            .help("The AI that answers Ask, Plan my day and Refine")
            if let provider = ai.setupState.provider {
                AIProviderStatusRow(ai: ai, provider: provider)
                    .id(provider)
            }
        } header: {
            Text("AI")
        } footer: {
            SectionFooter(footer)
        }
    }

    /// The provider in use: a saved one this build can't run (Claude Code
    /// in the App Store build) shows as None, as it acts.
    private var choice: Binding<AIProviderID?> {
        Binding(get: { ai.setupState.provider }, set: { settings.settings.ai.provider = $0 })
    }

    private var footer: String {
        guard let provider = ai.setupState.provider else {
            return "Pick one to use Ask, Plan my day and Refine. \(Edition.current.name) sends nothing until you do."
        }
        let hint = provider.requiresAPIKey ? "Your key stays in your Keychain."
            : provider.setupHint(model: settings.settings.ai.model(for: provider)) ?? ""
        return "\(provider.setupSummary) \(hint)"
    }
}

/// The row under the picker: the key field for a hosted API, or whether
/// a command line tool is on this Mac, with a link to what's missing.
private struct AIProviderStatusRow: View {
    @ObservedObject var ai: AIService
    let provider: AIProviderID
    @State private var draft = ""
    @State private var saveFailed = false
    /// Nil while the lookup runs; always true for providers with no tool.
    @State private var isInstalled: Bool?

    var body: some View {
        if provider.requiresAPIKey {
            keyRow
        } else {
            toolRow
                .task { isInstalled = await ai.isInstalled(provider) }
        }
    }

    @ViewBuilder
    private var keyRow: some View {
        if ai.hasKey(for: provider) {
            LabeledContent("API key") {
                HStack(spacing: 8) {
                    Label("Saved in your Keychain", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .labelStyle(StatusLabelStyle(tint: .green))
                    Button("Remove") { save(nil) }
                        .help("Delete this key from your Keychain")
                }
            }
        } else {
            LabeledContent("API key") {
                HStack(spacing: 8) {
                    SecureField("API key", text: $draft, prompt: Text("Paste your key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: 180)
                        .onSubmit { save(draft) }
                        .help("Your \(provider.displayName) key. It is kept in your Keychain.")
                    Button("Save") { save(draft) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Save this key in your Keychain")
                    pageButton
                }
            }
            if saveFailed {
                Label("The Keychain didn't save the key. Try again.", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: .orange))
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var toolRow: some View {
        LabeledContent(provider.isCommandLineTool ? "Command" : "App") {
            HStack(spacing: 8) {
                if !provider.isCommandLineTool {
                    // Ollama: whether it runs shows only when it answers.
                    Text("Runs on this Mac")
                        .foregroundStyle(.secondary)
                    pageButton
                } else if let isInstalled {
                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .labelStyle(StatusLabelStyle(tint: .green))
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Not found on this Mac", systemImage: "exclamationmark.circle.fill")
                            .labelStyle(StatusLabelStyle(tint: .orange))
                            .foregroundStyle(.secondary)
                        pageButton
                    }
                } else {
                    ProgressView().controlSize(.small)
                    Text("Looking for it")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pageButton: some View {
        Button(provider.setupPageTitle) { NSWorkspace.shared.open(provider.setupPage) }
            .help("Open \(provider.setupPage.host() ?? "the official page") in your browser")
    }

    private func save(_ key: String?) {
        do {
            try ai.setKey(key, for: provider)
            draft = ""
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}

/// A status label whose icon carries the color and whose words stay quiet.
private struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

/// Settings > Connections > More options: the model the chosen provider
/// uses, for the few who want another one. Blank means the default.
struct AIModelSection: View {
    let provider: AIProviderID
    @EnvironmentObject private var settings: SettingsStore
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Section {
            LabeledContent("Model") {
                TextField("Model", text: $draft, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 240)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .help("The model \(provider.displayName) uses. Leave empty for the default.")
            }
        } header: {
            Text("AI model")
        } footer: {
            SectionFooter("Leave empty for the default, which is quick and inexpensive.")
        }
        .onAppear { draft = settings.settings.ai.models[provider] ?? "" }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private var placeholder: String {
        provider.defaultModel.isEmpty ? "The tool's own default" : provider.defaultModel
    }

    private func commit() {
        settings.settings.ai.setModel(draft, for: provider)
        draft = settings.settings.ai.models[provider] ?? ""
    }
}
