import Foundation

/// Where Claude Code and Codex keep the usage logs AI Usage reads, and how
/// a folder the user picks maps to them.
///
/// The sandboxed App Store build can't look in `~/.claude` or `~/.codex` on
/// its own: the user picks the folder once in an open panel, and the app
/// keeps it as a security-scoped bookmark. People pick the tool's own
/// folder (`~/.claude`) as often as the logs inside it (`~/.claude/projects`),
/// so both are accepted.
public enum AIUsageFolder {
    /// The folder the open panel starts in and suggests: the tool's own
    /// hidden folder in the user's real home (not the app's container).
    public static func suggested(for source: AIUsageSource, home: URL = realHome) -> URL {
        home.appendingPathComponent(toolFolderName(for: source), isDirectory: true)
    }

    /// The tool folder's name, as the panel and Settings show it.
    public static func toolFolderName(for source: AIUsageSource) -> String {
        switch source {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        }
    }

    /// The logs folder inside the tool's folder.
    public static func logsFolderName(for source: AIUsageSource) -> String {
        switch source {
        case .claudeCode: "projects"
        case .codex: "sessions"
        }
    }

    /// The folder of logs a scan reads, given the folder the user picked:
    /// the logs folder itself, or the tool's folder that holds it. Nil when
    /// the pick holds neither, so the app can say it was the wrong folder.
    public static func logRoot(forPicked picked: URL, source: AIUsageSource,
                               isDirectory: (URL) -> Bool = AIUsageFolder.isDirectory) -> URL? {
        let logs = logsFolderName(for: source)
        let inside = picked.appendingPathComponent(logs, isDirectory: true)
        if isDirectory(inside) { return inside }
        if picked.lastPathComponent == logs, isDirectory(picked) { return picked }
        return nil
    }

    /// The pick as Settings shows it, with the home folder as `~`.
    public static func displayPath(_ url: URL, home: URL = realHome) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// The user's real home folder. Inside the App Sandbox,
    /// `homeDirectoryForCurrentUser` is the app's container, which never
    /// holds these logs, so the account's home comes from the user database.
    public static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
