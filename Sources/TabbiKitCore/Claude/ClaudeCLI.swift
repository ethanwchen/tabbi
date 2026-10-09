import Foundation

/// Finds and runs the user's local `claude` CLI.
///
/// Tabbi never talks to Anthropic directly and never reads credentials:
/// every Claude feature goes through the CLI the user is already signed in to.
/// GUI apps don't inherit the shell PATH, so the binary is located explicitly.
public enum ClaudeCLI {
    /// Environment variable that overrides discovery.
    public static let overrideVariable = "TABBI_CLAUDE_PATH"

    /// The user's "claude path" setting, applied by the app whenever it changes.
    /// It is the default `pathOverride` so every caller of `locate()` honors the
    /// setting without threading it through each module.
    public static var userPathOverride: String? {
        get { userPathLock.withLock { storedUserPath } }
        set { userPathLock.withLock { storedUserPath = newValue } }
    }
    private static let userPathLock = NSLock()
    nonisolated(unsafe) private static var storedUserPath: String?

    /// Finds the binary. A non-executable `pathOverride` (the user's setting)
    /// or environment override is skipped so discovery still works.
    public static func locate(
        pathOverride: String? = ClaudeCLI.userPathOverride,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        loginShellLookup: () -> String? = ClaudeCLI.lookupInLoginShell
    ) -> URL? {
        AIExecutableLocator.locate(
            "claude",
            pathOverride: pathOverride,
            environment: environment,
            fileManager: fileManager,
            loginShellLookup: { _ in loginShellLookup() }
        )
    }

    /// Asks the user's login shell where `claude` is. Blocking; call off the main thread.
    public static func lookupInLoginShell() -> String? {
        AIExecutableLocator.lookupInLoginShell("claude")
    }

    /// Runs `claude -p` with stream-json output and yields parsed events.
    ///
    /// Runs in a neutral temporary directory so no project CLAUDE.md or
    /// settings are picked up. The prompt goes last, after `--`, so text that
    /// starts with `-` or matches a subcommand is never parsed as CLI input.
    /// Cancel the consuming task to stop the process.
    public static func stream(
        executable: URL,
        prompt: String,
        extraArguments: [String] = []
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let arguments = ["-p", "--output-format", "stream-json", "--verbose"] + extraArguments + ["--", prompt]
        return events(from: StreamingProcess.lines(
            executable: executable,
            arguments: arguments,
            currentDirectory: FileManager.default.temporaryDirectory
        ))
    }

    /// Runs `claude -p` with one stream-json `inputLine` on stdin (a user
    /// message, which can carry images) and yields parsed events, like
    /// `stream(executable:prompt:extraArguments:)`. The CLI answers and exits
    /// once stdin closes.
    public static func stream(
        executable: URL,
        inputLine: Data,
        extraArguments: [String] = []
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
            + extraArguments
        return events(from: StreamingProcess.lines(
            executable: executable,
            arguments: arguments,
            currentDirectory: FileManager.default.temporaryDirectory,
            input: inputLine
        ))
    }

    private static func events(
        from lines: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        continuation.yield(ClaudeStreamEvent.parse(line: line))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
