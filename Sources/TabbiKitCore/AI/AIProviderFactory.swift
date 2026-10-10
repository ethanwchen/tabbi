import Foundation

/// Where the user's AI setup stands, for the setup and empty states of
/// every AI feature.
public enum AISetupState: Hashable, Sendable {
    /// No provider picked (or the picked one can't run in this build):
    /// nothing may be sent anywhere yet.
    case notChosen
    /// The picked API provider has no saved key.
    case needsKey(AIProviderID)
    /// Ready to send. A command line tool may still turn out to be missing,
    /// which the request reports as `AIProviderError.notInstalled`.
    case ready(AIProviderID)

    public var provider: AIProviderID? {
        switch self {
        case .notChosen: nil
        case .needsKey(let id), .ready(let id): id
        }
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// Builds the provider the user picked: an `AICommandLineProvider` for a
/// CLI, an `AIHTTPProvider` with the saved key for an API, and Ollama on
/// localhost. The provider fills in the user's model for requests that
/// leave it blank, so features only write prompts.
public struct AIProviderFactory: Sendable {
    public typealias Locate = @Sendable (AIProviderID) -> URL?

    private let keys: any AIKeyStore
    private let sandboxed: Bool
    private let locate: Locate
    private let transport: AIHTTPProvider.Transport
    private let runner: AICommandLineProvider.Runner

    /// - Parameters:
    ///   - sandboxed: true in the App Store build, which can't run CLIs.
    ///   - locate: finds a CLI; by default Claude Code goes through
    ///     `ClaudeExecutableResolver.shared` (which honors the path setting)
    ///     and the others through `AIExecutableLocator`.
    public init(
        keys: any AIKeyStore,
        sandboxed: Bool,
        locate: @escaping Locate = AIProviderFactory.defaultLocate,
        transport: @escaping AIHTTPProvider.Transport = AIHTTPProvider.urlSession(),
        runner: @escaping AICommandLineProvider.Runner = AICommandLineProvider.process
    ) {
        self.keys = keys
        self.sandboxed = sandboxed
        self.locate = locate
        self.transport = transport
        self.runner = runner
    }

    public static let defaultLocate: Locate = { id in
        switch id.transport {
        case .cli(let executable):
            id == .claudeCLI ? ClaudeExecutableResolver.shared.resolve() : AIExecutableLocator.locate(executable)
        case .api, .local:
            nil
        }
    }

    /// The providers to offer in this build, in picker order.
    public var availableProviders: [AIProviderID] { AIProviderID.available(sandboxed: sandboxed) }

    public func setupState(for settings: AISettings) -> AISetupState {
        guard let id = settings.activeProvider(sandboxed: sandboxed) else { return .notChosen }
        if id.requiresAPIKey, !keys.hasKey(for: id) { return .needsKey(id) }
        return .ready(id)
    }

    /// The provider for `settings`, or nil when none is picked. A provider
    /// still missing its key is returned and fails with `missingAPIKey`, so
    /// a feature has one error path.
    public func provider(for settings: AISettings) -> (any AIProvider)? {
        guard let id = settings.activeProvider(sandboxed: sandboxed) else { return nil }
        let base: any AIProvider
        if id.isCommandLineTool {
            let locate = locate
            base = AICommandLineProvider(id: id, locate: { locate(id) }, runner: runner)
        } else {
            base = AIHTTPProvider(id: id, apiKey: keys.key(for: id), transport: transport)
        }
        return ModelDefaultingProvider(base: base, model: settings.model(for: id))
    }
}

/// Sends the user's model with requests that don't name one.
private struct ModelDefaultingProvider: AIProvider {
    let base: any AIProvider
    let model: String

    var id: AIProviderID { base.id }

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        var request = request
        if request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { request.model = model }
        return base.stream(request)
    }
}
