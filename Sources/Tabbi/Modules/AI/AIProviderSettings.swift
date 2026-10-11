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
/// Picking a provider that sends data off the Mac first asks, once, with
/// a disclosure naming the provider and what each feature sends.
struct AIProviderSection: View {
    @ObservedObject var ai: AIService
    @EnvironmentObject private var settings: SettingsStore
    /// The provider waiting for the user's permission while the alert shows.
    @State private var pendingConsent: AIProviderID?

    var body: some View {
        Section {
            Picker(String(localized: "Answers from", bundle: .tabbi), selection: choice) {
                Text("None", bundle: .tabbi).tag(AIProviderID?.none)
                ForEach(ai.availableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(Optional(provider))
                }
            }
            .help(String(localized: "The AI that answers Ask, Plan my day and Refine", bundle: .tabbi))
            if let provider = ai.setupState.provider {
                AIProviderStatusRow(ai: ai, provider: provider)
                    .id(provider)
            }
        } header: {
            Text("AI", bundle: .tabbi)
        } footer: {
            SectionFooter(footer)
        }
        .alert(pendingConsent?.consentTitle ?? "", isPresented: isAskingConsent, presenting: pendingConsent) { provider in
            Button(String(localized: "Allow", bundle: .tabbi)) { settings.settings.ai.choose(provider) }
            Button(String(localized: "Cancel", bundle: .tabbi), role: .cancel) {}
        } message: { provider in
            Text(provider.consentMessage(appName: Edition.current.name))
        }
    }

    /// The provider in use: a saved one this build can't run (Claude Code
    /// in the App Store build) or not yet allowed shows as None, as it acts.
    private var choice: Binding<AIProviderID?> {
        Binding(get: { ai.setupState.provider }, set: { provider in
            if let provider, settings.settings.ai.needsConsent(for: provider) {
                pendingConsent = provider
            } else {
                settings.settings.ai.choose(provider)
            }
        })
    }

    private var isAskingConsent: Binding<Bool> {
        Binding(get: { pendingConsent != nil }, set: { if !$0 { pendingConsent = nil } })
    }

    private var footer: String {
        guard let provider = ai.setupState.provider else {
            // A choice saved before Tabbi asked for permission sends nothing
            // until the user picks it again.
            if let saved = settings.settings.ai.provider, ai.availableProviders.contains(saved),
               settings.settings.ai.needsConsent(for: saved) {
                return String(localized: "Pick \(saved.displayName) again to allow it to receive your AI requests. \(Edition.current.name) sends nothing until you do.", bundle: .tabbi)
            }
            return String(localized: "Pick one to use Ask, Plan my day and Refine. \(Edition.current.name) sends nothing until you do.", bundle: .tabbi)
        }
        let hint = provider.requiresAPIKey ? String(localized: "Your key stays in your Keychain.", bundle: .tabbi)
            : provider.setupHint(model: settings.settings.ai.model(for: provider)) ?? ""
        let recipient = provider.vendorName.map { String(localized: "Sends what you ask to \($0).", bundle: .tabbi) } ?? ""
        return Sentences.join([provider.setupSummary, recipient, hint])
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
            LabeledContent(String(localized: "API key", bundle: .tabbi)) {
                HStack(spacing: 8) {
                    Label(String(localized: "Saved in your Keychain", bundle: .tabbi), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .labelStyle(StatusLabelStyle(tint: .green))
                    Button(String(localized: "Remove", bundle: .tabbi)) { save(nil) }
                        .help(String(localized: "Delete this key from your Keychain", bundle: .tabbi))
                }
            }
        } else {
            LabeledContent(String(localized: "API key", bundle: .tabbi)) {
                HStack(spacing: 8) {
                    SecureField(String(localized: "API key", bundle: .tabbi), text: $draft, prompt: Text("Paste your key", bundle: .tabbi))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 120, maxWidth: 180)
                        .onSubmit { save(draft) }
                        .help(String(localized: "Your \(provider.displayName) key. It is kept in your Keychain.", bundle: .tabbi))
                    Button(String(localized: "Save", bundle: .tabbi)) { save(draft) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(String(localized: "Save this key in your Keychain", bundle: .tabbi))
                    pageButton
                }
            }
            if saveFailed {
                Label(String(localized: "The Keychain didn't save the key. Try again.", bundle: .tabbi), systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: .orange))
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var toolRow: some View {
        LabeledContent(provider.isCommandLineTool ? String(localized: "Command", bundle: .tabbi) : String(localized: "App", bundle: .tabbi)) {
            HStack(spacing: 8) {
                if !provider.isCommandLineTool {
                    // Ollama: whether it runs shows only when it answers.
                    Text("Runs on this Mac", bundle: .tabbi)
                        .foregroundStyle(.secondary)
                    pageButton
                } else if let isInstalled {
                    if isInstalled {
                        Label(String(localized: "Installed", bundle: .tabbi), systemImage: "checkmark.circle.fill")
                            .labelStyle(StatusLabelStyle(tint: .green))
                            .foregroundStyle(.secondary)
                    } else {
                        Label(String(localized: "Not found on this Mac", bundle: .tabbi), systemImage: "exclamationmark.circle.fill")
                            .labelStyle(StatusLabelStyle(tint: .orange))
                            .foregroundStyle(.secondary)
                        pageButton
                    }
                } else {
                    ProgressView().controlSize(.small)
                    Text("Looking for it", bundle: .tabbi)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pageButton: some View {
        Button(provider.setupPageTitle) { NSWorkspace.shared.open(provider.setupPage) }
            .help(provider.setupPage.host().map { String(localized: "Open \($0) in your browser", bundle: .tabbi) }
                  ?? String(localized: "Open the official page in your browser", bundle: .tabbi))
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
            LabeledContent(String(localized: "Model", bundle: .tabbi)) {
                TextField(String(localized: "Model", bundle: .tabbi), text: $draft, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 240)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .help(String(localized: "The model \(provider.displayName) uses. Leave empty for the default.", bundle: .tabbi))
            }
        } header: {
            Text("AI model", bundle: .tabbi)
        } footer: {
            SectionFooter(String(localized: "Leave empty for the default, which is quick and inexpensive.", bundle: .tabbi))
        }
        .onAppear { draft = settings.settings.ai.models[provider] ?? "" }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private var placeholder: String {
        provider.defaultModel.isEmpty ? String(localized: "The tool's own default", bundle: .tabbi) : provider.defaultModel
    }

    private func commit() {
        settings.settings.ai.setModel(draft, for: provider)
        draft = settings.settings.ai.models[provider] ?? ""
    }
}
