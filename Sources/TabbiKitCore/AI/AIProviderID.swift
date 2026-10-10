import Foundation

/// One way Tabbi can reach a language model for Ask AI, Plan my day, Day
/// review and the Schedule's Refine.
///
/// Three are command line tools the user already signed in to (Claude Code,
/// Codex, Gemini CLI), three are hosted APIs called with the user's own key
/// from the Keychain, and Ollama runs models on this Mac. Nothing is sent
/// anywhere until the user picks one.
public enum AIProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case claudeCLI = "claude-cli"
    case codexCLI = "codex-cli"
    case geminiCLI = "gemini-cli"
    case anthropic
    case openAI = "openai"
    case gemini
    case ollama

    /// How Tabbi talks to the provider, which decides what setup it needs
    /// and whether the sandboxed App Store build can use it.
    public enum Transport: Hashable, Sendable {
        /// A local command line tool, found on disk and run as a process.
        case cli(executable: String)
        /// A hosted HTTPS API that takes the user's key.
        case api
        /// A server on this Mac (Ollama), reached over localhost.
        case local
    }

    public var transport: Transport {
        switch self {
        case .claudeCLI: .cli(executable: "claude")
        case .codexCLI: .cli(executable: "codex")
        case .geminiCLI: .cli(executable: "gemini")
        case .anthropic, .openAI, .gemini: .api
        case .ollama: .local
        }
    }

    /// The name shown in Settings and beside "Ask AI".
    public var displayName: String {
        switch self {
        case .claudeCLI: "Claude Code"
        case .codexCLI: "Codex CLI"
        case .geminiCLI: "Gemini CLI"
        case .anthropic: "Claude API"
        case .openAI: "OpenAI API"
        case .gemini: "Gemini API"
        case .ollama: "Ollama"
        }
    }

    /// The assistant's name in running text ("Ask Claude", "Refine with
    /// Gemini"), the same for the CLI and the API of one vendor.
    public var assistantName: String {
        switch self {
        case .claudeCLI, .anthropic: "Claude"
        case .codexCLI: "Codex"
        case .openAI: "OpenAI"
        case .geminiCLI, .gemini: "Gemini"
        case .ollama: "Ollama"
        }
    }

    /// A one-line note for the provider picker on cost and setup.
    public var setupSummary: String {
        switch self {
        case .claudeCLI: "Uses your Claude subscription through the claude command."
        case .codexCLI: "Uses your ChatGPT plan through the codex command."
        case .geminiCLI: "Free with a Google account through the gemini command."
        case .anthropic: "Pay as you go with an Anthropic API key."
        case .openAI: "Pay as you go with an OpenAI API key."
        case .gemini: "Free tier with a Google AI Studio key."
        case .ollama: "Free and offline: runs a model on this Mac."
        }
    }

    /// The official page with what setup needs: the API key page for a
    /// hosted API, the install page for a tool or Ollama. Opened in the
    /// browser, never fetched by Tabbi.
    public var setupPage: URL {
        let page = switch self {
        case .claudeCLI: "https://docs.anthropic.com/en/docs/claude-code/setup"
        case .codexCLI: "https://github.com/openai/codex"
        case .geminiCLI: "https://github.com/google-gemini/gemini-cli"
        case .anthropic: "https://console.anthropic.com/settings/keys"
        case .openAI: "https://platform.openai.com/api-keys"
        case .gemini: "https://aistudio.google.com/apikey"
        case .ollama: "https://ollama.com/download"
        }
        return URL(string: page)!
    }

    /// The button that opens `setupPage`.
    public var setupPageTitle: String { requiresAPIKey ? "Get a Key" : "Install" }

    /// What to do once installed, for the providers whose setup is more
    /// than an install or a key: the CLIs sign in on first run, and Ollama
    /// needs the model downloaded once. `model` is the one Tabbi will ask for.
    public func setupHint(model: String) -> String? {
        switch self {
        case .claudeCLI: "Run claude in Terminal once to sign in."
        case .codexCLI: "Run codex in Terminal once to sign in."
        case .geminiCLI: "Run gemini in Terminal once to sign in with Google."
        case .anthropic, .openAI, .gemini: nil
        case .ollama: "With Ollama open, run ollama pull \(model) in Terminal once."
        }
    }

    public var requiresAPIKey: Bool { transport == .api }

    public var isCommandLineTool: Bool {
        if case .cli = transport { return true }
        return false
    }

    /// Whether the sandboxed App Store build can use it: a sandboxed app
    /// cannot run the user's command line tools, but it can make network
    /// requests (the `network.client` entitlement), localhost included.
    public var worksInSandbox: Bool { !isCommandLineTool }

    /// The model a new user gets: fast and inexpensive, good enough for a
    /// quick question and a day plan. An empty value means the CLI's own
    /// default, which follows the user's plan.
    public var defaultModel: String {
        switch self {
        case .claudeCLI: "sonnet"
        case .codexCLI, .geminiCLI: ""
        case .anthropic: "claude-sonnet-5-5"
        case .openAI: "gpt-5-mini"
        // Google's alias for the newest Flash model, which the free tier covers.
        case .gemini: "gemini-flash-latest"
        case .ollama: "llama3.2"
        }
    }

    /// The host the app connects to for this provider, for the descriptors'
    /// network access list. Command line tools make their own connections.
    public var networkAccess: ModuleNetworkAccess? {
        switch self {
        case .claudeCLI, .codexCLI, .geminiCLI: nil
        case .anthropic: ModuleNetworkAccess(host: "api.anthropic.com", purpose: "answers from Claude with your API key")
        case .openAI: ModuleNetworkAccess(host: "api.openai.com", purpose: "answers from OpenAI with your API key")
        case .gemini: ModuleNetworkAccess(host: "generativelanguage.googleapis.com", purpose: "answers from Gemini with your API key")
        case .ollama: ModuleNetworkAccess(host: "localhost", purpose: "answers from a model Ollama runs on this Mac")
        }
    }

    /// Every host an AI feature may connect to, for module descriptors.
    public static var allNetworkAccess: [ModuleNetworkAccess] { allCases.compactMap(\.networkAccess) }

    /// The providers this build can offer, in picker order.
    public static func available(sandboxed: Bool) -> [AIProviderID] {
        allCases.filter { !sandboxed || $0.worksInSandbox }
    }
}
