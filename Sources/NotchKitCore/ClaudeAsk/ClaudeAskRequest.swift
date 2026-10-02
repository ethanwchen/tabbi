import Foundation

/// How Ask Claude invokes the CLI, kept pure so the flags are unit tested.
public enum ClaudeAskRequest {
    /// Fast model alias; Ask Claude is a quick Q&A box, not a coding agent.
    public static let model = "sonnet"

    /// Arguments inserted before `-- <prompt>` in `claude -p --output-format stream-json`.
    ///
    /// `--tools ""` removes every built-in tool and `--strict-mcp-config`
    /// (with no `--mcp-config`) ignores the user's MCP servers, so the CLI
    /// can only answer in text. Passing `sessionID` continues that chat.
    public static func extraArguments(resuming sessionID: String? = nil) -> [String] {
        var arguments = [
            "--include-partial-messages",
            "--model", model,
            "--tools", "",
            "--strict-mcp-config",
        ]
        if let sessionID, !sessionID.isEmpty {
            arguments += ["--resume", sessionID]
        }
        return arguments
    }
}

extension ClaudeAskFailure {
    /// Maps an error thrown by the CLI stream to a failure safe to show.
    public init(error: Error) {
        if let failure = error as? ProcessFailure {
            let detail = ClaudeAskConversation.summarize(failure.stderr)
                ?? "Claude exited unexpectedly (status \(failure.status))."
            self = .process(detail: detail)
        } else {
            self = .process(detail: ClaudeAskConversation.summarize(error.localizedDescription)
                ?? "Couldn't start Claude.")
        }
    }
}

extension ClaudeAskConversation {
    /// A finished sample exchange for `NOTCHDECK_DEMO=1` snapshots and
    /// screenshots, built through the same reducer as live data.
    public static var demo: ClaudeAskConversation {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Name for a function that retries with backoff?")
        conversation.apply(.sessionStarted(sessionID: "demo-session"))
        conversation.apply(.result(ClaudeResult(
            text: """
            - **`retryWithBackoff(_:)`** - clear and conventional
            - **`withRetries(maxAttempts:)`** - reads well at the call site

            I'd pick `retryWithBackoff` unless you already use the `with…` style.
            """,
            sessionID: "demo-session",
            isError: false
        )))
        return conversation
    }
}
