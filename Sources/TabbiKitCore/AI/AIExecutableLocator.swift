import Foundation

/// Finds a command line tool (claude, codex, gemini) on disk.
///
/// GUI apps don't inherit the shell PATH, so Tabbi looks where the usual
/// installers put these tools (the native installer, Homebrew, npm, Volta,
/// fnm, Bun) and then asks the user's login shell.
public enum AIExecutableLocator {
    /// The environment variable that points at `executable` and overrides
    /// discovery, such as `TABBI_CODEX_PATH`.
    public static func overrideVariable(for executable: String) -> String {
        "TABBI_\(executable.uppercased())_PATH"
    }

    /// Where installers put `executable`, most specific first.
    public static func candidatePaths(for executable: String, home: String) -> [String] {
        var paths = ["\(home)/.local/bin/\(executable)"]
        // Claude Code's older native installer.
        if executable == "claude" { paths.append("\(home)/.claude/local/claude") }
        paths += [
            "\(home)/.local/share/fnm/aliases/default/bin/\(executable)",
            "\(home)/.volta/bin/\(executable)",
            "/opt/homebrew/bin/\(executable)",
            "/usr/local/bin/\(executable)",
            "\(home)/.npm-global/bin/\(executable)",
            "\(home)/.bun/bin/\(executable)",
        ]
        return paths
    }

    /// Finds `executable`. A non-executable `pathOverride` (the user's
    /// setting) or environment override is skipped so discovery still works.
    public static func locate(
        _ executable: String,
        pathOverride: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        loginShellLookup: (String) -> String? = AIExecutableLocator.lookupInLoginShell
    ) -> URL? {
        for override in [pathOverride, environment[overrideVariable(for: executable)]].compactMap({ $0 })
        where fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        if let hit = candidatePaths(for: executable, home: home).first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }
        if let path = loginShellLookup(executable), fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Asks the user's login shell where `executable` is. Blocking; call
    /// off the main thread.
    public static func lookupInLoginShell(_ executable: String) -> String? {
        guard executable.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(executable)"]
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

    /// The environment to run a tool found at `executable` with. Codex and
    /// Gemini CLI are Node scripts (`#!/usr/bin/env node`), so PATH must
    /// reach `node`, which a GUI app's PATH usually doesn't: the tool's own
    /// folder and Homebrew's go first.
    public static func environment(
        running executable: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let existing = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let preferred = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        var seen = Set<String>()
        environment["PATH"] = (preferred + existing + ["/usr/bin", "/bin"])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }
}
