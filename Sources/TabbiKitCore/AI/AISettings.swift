import Foundation

/// The user's AI choices: which provider answers Ask AI, Plan my day, Day
/// review and Refine, the model each provider uses, and which providers
/// the user allowed to receive their data.
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
    /// Providers the user allowed to receive their requests, after the
    /// disclosure that names the provider and what is sent (App Store
    /// Guideline 5.1.2(i)). A provider that sends data off the Mac stays
    /// inactive until it is in here, so a choice saved before Tabbi asked
    /// (the claude command older versions used) sends nothing until the
    /// user picks it again and allows it.
    public var consented: Set<AIProviderID>

    public init(provider: AIProviderID? = nil, models: [AIProviderID: String] = [:],
                consented: Set<AIProviderID> = []) {
        self.provider = provider
        self.models = models
        self.consented = consented
    }

    /// The provider that answers in this build, or nil when the user hasn't
    /// picked one this build can run and allowed it to receive their data.
    public func activeProvider(sandboxed: Bool) -> AIProviderID? {
        guard let provider, !sandboxed || provider.worksInSandbox, !needsConsent(for: provider) else { return nil }
        return provider
    }

    /// Whether picking `provider` must first ask the user's permission: it
    /// sends data off this Mac and the user hasn't allowed it yet.
    public func needsConsent(for provider: AIProviderID) -> Bool {
        provider.sendsDataOffMac && !consented.contains(provider)
    }

    /// Picks `provider` once the user has allowed it (or it needs no
    /// permission), recording the permission so it is asked only once.
    public mutating func choose(_ provider: AIProviderID?) {
        self.provider = provider
        if let provider, provider.sendsDataOffMac { consented.insert(provider) }
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
