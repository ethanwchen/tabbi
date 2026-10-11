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
        case .claudeCLI: String(localized: "Uses your Claude subscription through the claude command.", bundle: .tabbi)
        case .codexCLI: String(localized: "Uses your ChatGPT plan through the codex command.", bundle: .tabbi)
        case .geminiCLI: String(localized: "Free with a Google account through the gemini command.", bundle: .tabbi)
        case .anthropic: String(localized: "Pay as you go with an Anthropic API key.", bundle: .tabbi)
        case .openAI: String(localized: "Pay as you go with an OpenAI API key.", bundle: .tabbi)
        case .gemini: String(localized: "Free tier with a Google AI Studio key.", bundle: .tabbi)
        case .ollama: String(localized: "Free and offline: runs a model on this Mac.", bundle: .tabbi)
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
    public var setupPageTitle: String { requiresAPIKey ? String(localized: "Get a Key", bundle: .tabbi) : String(localized: "Install", bundle: .tabbi) }

    /// The next step, for the providers whose setup is more than a key: a
    /// command line tool needs installing, then signing in once, and Ollama
    /// needs the model downloaded once. `model` is the one Tabbi will ask
    /// for, and `tool` where the provider's command line tool stands.
    ///
    /// It never tells the user to type a tool's bare name: a tool that is
    /// not installed can't run, and one that is may still be missing from
    /// a fresh Terminal window's PATH (Claude's installer puts it in
    /// `~/.local/bin`), so a found tool is named by its full path. Claude
    /// Code points to the Claude row in Connections instead, whose
    /// walkthrough installs and signs in with one pasted line.
    public func setupHint(model: String, tool: AIToolLookup) -> String? {
        switch (self, tool) {
        case (.anthropic, _), (.openAI, _), (.gemini, _): return nil
        case (.ollama, _): return String(localized: "With Ollama open, run ollama pull \(model) in Terminal once.", bundle: .tabbi)
        case (.claudeCLI, .missing):
            let button = ConnectionAction.showGuide(.claudeInstall).title
            return String(localized: "To install it, click \(button) on the Claude row below.", bundle: .tabbi)
        case (.claudeCLI, .found):
            return String(localized: "The Claude row below shows how to sign in, if you still need to.", bundle: .tabbi)
        case (_, .missing):
            return String(localized: "Click \(setupPageTitle) for the official steps, then come back here.", bundle: .tabbi)
        case (.codexCLI, .found(let executable)):
            let command = ShellCommandLine.running(executable, arguments: ["login"])
            return String(localized: "To sign in, run \(command) in Terminal once.", bundle: .tabbi)
        case (.geminiCLI, .found(let executable)):
            let command = ShellCommandLine.running(executable)
            return String(localized: "To sign in with Google, run \(command) in Terminal once.", bundle: .tabbi)
        case (_, .looking): return nil
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

/// Where a provider's command line tool stands on this Mac, which decides
/// the setup hint Settings shows under the AI choice.
public enum AIToolLookup: Hashable, Sendable {
    /// Still looking; the login shell can take a moment.
    case looking
    /// Not found anywhere Tabbi looks.
    case missing
    /// Found at this file, which a hint names in full.
    case found(URL)
}
