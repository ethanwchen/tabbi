import Foundation

extension ClaudeAskConversation {
    /// What every provider is told about the panel, so answers fit it:
    /// short, in Markdown, and with no tools to reach for.
    public static let instructions = """
    You answer quick questions in Tabbi, a small panel in the Mac's notch. \
    Be brief and direct, use Markdown sparingly, and keep code samples short.
    """
}

extension ClaudeAskFailure {
    /// Maps an error thrown by `provider`'s stream to a failure safe to show.
    public init(error: Error, provider: AIProviderID) {
        switch error {
        case AIProviderError.notInstalled:
            self = .notInstalled(provider)
        case AIProviderError.missingAPIKey:
            self = .needsKey(provider)
        case let error as AIProviderError:
            self = .process(detail: ClaudeAskConversation.summarize(error.message(for: provider))
                ?? "\(provider.assistantName) couldn't answer.")
        case let failure as ProcessFailure:
            self = .process(detail: ClaudeAskConversation.summarize(failure.stderr)
                ?? "\(provider.assistantName) exited unexpectedly (status \(failure.status)).")
        default:
            self = .process(detail: ClaudeAskConversation.summarize(error.localizedDescription)
                ?? "Couldn't start \(provider.assistantName).")
        }
    }
}

/// The words for a failure, the same in the setup screen and the failed
/// answer, so every provider's setup reads alike.
extension ClaudeAskFailure {
    /// The failed answer's headline. `assistant` names who was asked.
    public func title(assistant: String) -> String {
        switch self {
        case .noProvider: "No AI chosen yet"
        case .notInstalled(let id): "\(id.assistantName) isn't set up yet"
        case .needsKey(let id): "\(id.displayName) needs a key"
        case .process: "\(assistant) couldn't answer"
        }
    }

    /// The line under the headline.
    public var detail: String {
        switch self {
        case .noProvider: "Pick one in Connections. Some are free."
        case .notInstalled: "Connections shows you how to add it."
        case .needsKey: "Add your key in Connections."
        case .process(let detail): detail
        }
    }

    /// The setup screen's headline, shown before the first question.
    public var setupTitle: String {
        switch self {
        case .noProvider: "Choose an AI to ask questions"
        case .notInstalled(let id): "Set up \(id.assistantName) to ask questions"
        case .needsKey(let id): "Add your \(id.displayName) key"
        case .process: "Ask anything"
        }
    }

    /// The setup screen's sentence.
    public var setupMessage: String {
        switch self {
        case .noProvider:
            "Answers come from the AI you pick: Claude, ChatGPT, Gemini or a free model on this Mac."
        case .notInstalled(let id):
            "\(id.displayName) isn't on this Mac yet. Connections shows you how to add it."
        case .needsKey(let id):
            "Paste a key in Connections to ask \(id.assistantName) questions. It stays in your Keychain."
        case .process(let detail):
            detail
        }
    }

    /// The button that opens Connections.
    public var setupAction: String {
        switch self {
        case .noProvider: "Choose AI"
        case .notInstalled(let id): "Set up \(id.assistantName)"
        case .needsKey: "Add key"
        case .process: "Open Connections"
        }
    }
}

extension ClaudeAskConversation {
    /// Two finished sample exchanges for `TABBI_DEMO=1` snapshots and
    /// screenshots, built through the same reducer as live data.
    public static var demo: ClaudeAskConversation {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "How should an app retry a flaky network call?")
        conversation.apply(.sessionStarted(sessionID: "demo-session"))
        conversation.apply(.result(ClaudeResult(
            text: """
            Retry a few times, waiting longer after each try:

            - Start around **0.5 s** and double the wait each time
            - Add a little random jitter so clients don't retry in sync
            - Stop after 3 to 5 tries and only retry errors that can pass
            """,
            sessionID: "demo-session",
            isError: false
        )))
        conversation.begin(prompt: "Name for a function that retries with backoff?")
        conversation.apply(.result(ClaudeResult(
            text: """
            I'd go with **`retryWithBackoff`**. It says what it does at the call site:

            ```swift
            let profile = try await retryWithBackoff(attempts: 3) {
                try await api.fetchProfile()
            }
            ```

            `withRetries(maxAttempts:)` also reads well if you already use the `with…` style.
            """,
            sessionID: "demo-session",
            isError: false
        )))
        return conversation
    }
}
