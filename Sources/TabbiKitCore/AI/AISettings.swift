import Foundation

/// The user's AI choices: which provider answers Ask AI, Plan my day, Day
/// review and Refine, and the model each provider uses.
///
/// There is no default provider. Until the user picks one, every AI
/// feature shows its setup state and nothing is sent anywhere.
public struct AISettings: Equatable, Sendable {
    /// The provider the user picked, or nil before they pick one. Kept as
    /// saved even when this build can't use it (Claude Code after moving to
    /// the App Store build), so going back restores it; `activeProvider`
    /// decides what runs.
    public var provider: AIProviderID?
    /// Models the user typed, per provider. A missing or blank entry means
    /// the provider's `defaultModel`.
    public var models: [AIProviderID: String]

    public init(provider: AIProviderID? = nil, models: [AIProviderID: String] = [:]) {
        self.provider = provider
        self.models = models
    }

    /// The provider that answers in this build, or nil when the user hasn't
    /// picked one this build can run.
    public func activeProvider(sandboxed: Bool) -> AIProviderID? {
        guard let provider, !sandboxed || provider.worksInSandbox else { return nil }
        return provider
    }

    /// The model to request from `provider`: the user's, or the default.
    public func model(for provider: AIProviderID) -> String {
        let typed = models[provider]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return typed.isEmpty ? provider.defaultModel : typed
    }

    /// Records `model` for `provider`; blank or the default clears the
    /// entry, so a later change of the default reaches this user too.
    public mutating func setModel(_ model: String, for provider: AIProviderID) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        models[provider] = trimmed.isEmpty || trimmed == provider.defaultModel ? nil : trimmed
    }
}
