import Foundation

/// Finds and runs the user's local `claude` CLI.
///
/// NotchDeck never talks to Anthropic directly and never reads credentials:
/// every Claude feature goes through the CLI the user is already signed in to.
/// GUI apps don't inherit the shell PATH, so the binary is located explicitly.
public enum ClaudeCLI {
    /// Environment variable that overrides discovery.
    public static let overrideVariable = "NOTCHDECK_CLAUDE_PATH"

    /// Finds the binary. A non-executable `pathOverride` (the user's setting)
    /// or environment override is skipped so discovery still works.
    public static func locate(
        pathOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        loginShellLookup: () -> String? = ClaudeCLI.lookupInLoginShell
    ) -> URL? {
        for override in [pathOverride, environment[overrideVariable]].compactMap({ $0 })
        where fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.local/share/fnm/aliases/default/bin/claude",
            "\(home)/.volta/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let hit = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }
        if let path = loginShellLookup(), fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Asks the user's login shell where `claude` is. Blocking; call off the main thread.
    public static func lookupInLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (output?.hasPrefix("/") == true) ? output : nil
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
        let lines = StreamingProcess.lines(
            executable: executable,
            arguments: arguments,
            currentDirectory: FileManager.default.temporaryDirectory
        )
        return AsyncThrowingStream { continuation in
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
