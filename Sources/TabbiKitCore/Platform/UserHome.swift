import Foundation

extension FileManager {
    /// The current user's home folder: `homeDirectoryForCurrentUser` on the
    /// Mac (the app's container inside the App Sandbox). iOS has no such API,
    /// so there it is the app's own home, which never holds the Mac tools'
    /// folders (`~/.claude`, `~/.codex`) that the callers look for.
    var userHome: URL {
        #if os(macOS)
        homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }
}
