import Foundation

/// The outcome of checking which `claude` binary NotchDeck would run, shown
/// by the Settings window's Validate button.
public enum ClaudePathCheck: Equatable, Sendable {
    /// A working CLI. `isOverride` is false when it was found automatically.
    case found(path: String, version: String?, isOverride: Bool)
    /// Nothing exists at the user's path.
    case missing(path: String)
    /// The user's path is a directory or lacks execute permission.
    case notExecutable(path: String)
    /// The file runs, but `--version` did not answer like Claude Code.
    case notClaude(path: String)
    /// No override is set and auto-discovery found nothing.
    case notFound

    public var isSuccess: Bool {
        if case .found = self { return true }
        return false
    }

    /// Checks `override` (or auto-discovery when it is `nil`) and asks the
    /// binary for its version. Blocking; call off the main thread.
    ///
    /// An unusable override is reported as such rather than silently
    /// replaced by the auto-discovered binary, so the user can fix it.
    public static func run(
        override: String?,
        fileManager: FileManager = .default,
        locate: (String?) -> URL? = { ClaudeCLI.locate(pathOverride: $0) },
        version: (URL) -> String? = ClaudePathCheck.version(of:)
    ) -> ClaudePathCheck {
        let url: URL
        if let override {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: override, isDirectory: &isDirectory) else {
                return .missing(path: override)
            }
            guard !isDirectory.boolValue, fileManager.isExecutableFile(atPath: override) else {
                return .notExecutable(path: override)
            }
            url = URL(fileURLWithPath: override)
        } else {
            guard let located = locate(nil) else { return .notFound }
            url = located
        }
        guard let reported = version(url) else { return .notClaude(path: url.path) }
        return .found(path: url.path, version: reported, isOverride: override != nil)
    }

    /// Pulls the version number out of `claude --version` output such as
    /// "2.1.4 (Claude Code)". Returns `nil` for anything else, which is how a
    /// wrong binary (say, a shell script named `claude`) is told apart.
    public static func parseVersion(_ output: String) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.localizedCaseInsensitiveContains("claude") else { return nil }
        let token = trimmed.split(separator: " ").first.map(String.init) ?? ""
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return token
    }

    /// Runs `<executable> --version` with a short timeout and parses it.
    /// Blocking; call off the main thread.
    public static func version(of executable: URL) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseVersion(output)
    }
}
