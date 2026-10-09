import Combine
import Foundation
import TabbiKitCore

/// The AI provider the user picked, shared by Ask and the AI features of
/// Today and the Schedule: it builds the provider from the saved choice and
/// the key in the Keychain, and says where setup stands so each feature
/// can show the same setup state. Nothing is sent before a provider is
/// picked, since `provider` is nil until then.
@MainActor
final class AIService: ObservableObject {
    /// Refreshed when the AI settings or a saved key change.
    @Published private(set) var setupState: AISetupState

    private let settings: SettingsStore
    private let keys: any AIKeyStore
    private let factory: AIProviderFactory
    private var cancellable: AnyCancellable?

    /// `factory` replaces the real one in tests (a mocked transport or
    /// process runner); it must use the same `keys`.
    init(settings: SettingsStore, keys: any AIKeyStore, sandboxed: Bool, factory: AIProviderFactory? = nil) {
        self.settings = settings
        self.keys = keys
        self.factory = factory ?? AIProviderFactory(keys: keys, sandboxed: sandboxed)
        setupState = self.factory.setupState(for: settings.settings.ai)
        cancellable = settings.$settings
            .map(\.ai)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] ai in self?.refresh(ai) }
    }

    /// The providers this build offers, in picker order.
    var availableProviders: [AIProviderID] { factory.availableProviders }

    /// The provider to send a request to, or nil when none is picked.
    var provider: (any AIProvider)? { factory.provider(for: settings.settings.ai) }

    /// Whether `id`'s command line tool can be found. The lookup can block
    /// on the login shell, so it runs off the main thread. Always true for
    /// the API providers, which need no install.
    nonisolated func isInstalled(_ id: AIProviderID) async -> Bool {
        guard id.isCommandLineTool else { return true }
        return await Task.detached(priority: .userInitiated) { AIProviderFactory.defaultLocate(id) != nil }.value
    }

    func hasKey(for id: AIProviderID) -> Bool { keys.hasKey(for: id) }

    /// Saves (or, when blank, deletes) the key for `id`.
    func setKey(_ key: String?, for id: AIProviderID) throws {
        try keys.setKey(key, for: id)
        refresh(settings.settings.ai)
    }

    private func refresh(_ ai: AISettings) {
        let state = factory.setupState(for: ai)
        if state != setupState { setupState = state }
    }
}

extension ModuleContext {
    /// The one AI service. Keys live in the Keychain under the edition's
    /// own service name; demo and snapshot runs keep them in memory.
    var ai: AIService {
        shared.resolve {
            let keys: any AIKeyStore = runMode.isEphemeral
                ? InMemoryAIKeyStore()
                : KeychainAIKeyStore(service: edition.bundleIdentifier + ".ai")
            #if APPSTORE
            let sandboxed = true
            #else
            let sandboxed = false
            #endif
            return AIService(settings: settings, keys: keys, sandboxed: sandboxed)
        }
    }
}
