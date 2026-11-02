import AppKit
import TabbiKitCore
import os

/// The folders AI Usage may read in the sandboxed App Store build.
///
/// The sandbox keeps the app out of `~/.claude` and `~/.codex`, so the
/// user picks the folder once in an open panel (which only reads, through
/// `files.user-selected.read-only`), and the pick is kept as a
/// security-scoped bookmark (`files.bookmarks.app-scope`), so it still
/// works after a relaunch. Nothing is read before the user picks, and
/// Remove forgets the bookmark at once. Demo and snapshot runs never show
/// a panel or touch the saved bookmarks.
@MainActor
final class AIUsageFolderAccess: ObservableObject {
    /// A folder the user picked and the logs folder a scan reads in it.
    struct Grant: Equatable {
        let picked: URL
        let logRoot: URL
    }

    /// How a pick went, for the panel's message.
    enum PickOutcome: Equatable {
        case chosen
        case cancelled
        /// The folder holds no logs of that tool.
        case wrongFolder
    }

    /// The readable folders, by source.
    @Published private(set) var grants: [AIUsageSource: Grant] = [:]

    private let defaults: UserDefaults
    private let isLive: Bool
    static let defaultsKey = "claudeUsage.folderBookmarks"

    init(runMode: RunMode, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLive = !runMode.isEphemeral
        guard isLive else { return }
        for (raw, data) in savedBookmarks {
            guard let source = AIUsageSource(rawValue: raw) else { continue }
            resolve(data, for: source)
        }
    }

    /// The logs folder to read for `source`, or nil until the user picked one.
    func logRoot(for source: AIUsageSource) -> URL? {
        grants[source]?.logRoot
    }

    /// Shows the open panel, starting in the tool's folder, and keeps the
    /// pick when it holds the tool's logs.
    func pick(_ source: AIUsageSource) -> PickOutcome {
        guard isLive else { return .cancelled }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        // The tool folders start with a dot, which Finder hides.
        panel.showsHiddenFiles = true
        let suggested = AIUsageFolder.suggested(for: source)
        panel.directoryURL = AIUsageFolder.isDirectory(suggested) ? suggested : AIUsageFolder.realHome
        panel.prompt = String(localized: "Choose", bundle: .tabbi)
        panel.message = Self.panelMessage(for: source)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        return keep(url, for: source)
    }

    /// Keeps `url` as the folder for `source` when it holds the tool's logs:
    /// a security-scoped bookmark for later launches, and access now.
    func keep(_ url: URL, for source: AIUsageSource) -> PickOutcome {
        guard isLive else { return .cancelled }
        guard let root = AIUsageFolder.logRoot(forPicked: url, source: source) else { return .wrongFolder }
        stopAccessing(source)
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil)
            var saved = savedBookmarks
            saved[source.rawValue] = data
            savedBookmarks = saved
        } catch {
            // Still readable for this launch, through the panel's own grant.
            Self.log.error("Couldn't keep the \(source.rawValue, privacy: .public) folder: \(error.localizedDescription, privacy: .public)")
        }
        _ = url.startAccessingSecurityScopedResource()
        grants[source] = Grant(picked: url, logRoot: root)
        return .chosen
    }

    /// Shows both tools' folders as picked, for the snapshot run; nothing
    /// is read or saved.
    func showForSnapshot(home: URL = AIUsageFolder.realHome) {
        guard !isLive else { return }
        for source in [AIUsageSource.claudeCode, .codex] {
            let picked = AIUsageFolder.suggested(for: source, home: home)
            grants[source] = Grant(picked: picked,
                                   logRoot: picked.appendingPathComponent(AIUsageFolder.logsFolderName(for: source)))
        }
    }

    /// Forgets the folder for `source`: its bookmark and the access.
    func remove(_ source: AIUsageSource) {
        stopAccessing(source)
        grants[source] = nil
        guard isLive else { return }
        var saved = savedBookmarks
        saved[source.rawValue] = nil
        savedBookmarks = saved
    }

    /// The panel's one line: which folder, and what Tabbi reads in it.
    static func panelMessage(for source: AIUsageSource) -> String {
        let folder = AIUsageFolder.toolFolderName(for: source)
        return switch source {
        case .claudeCode:
            String(localized: "Choose the \(folder) folder in your home folder. Tabbi reads only token counts and model names from Claude Code's logs.", bundle: .tabbi)
        case .codex:
            String(localized: "Choose the \(folder) folder in your home folder. Tabbi reads only token counts, model names and plan limits from Codex's logs.", bundle: .tabbi)
        }
    }

    // MARK: Bookmarks

    private var savedBookmarks: [String: Data] {
        get { defaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    private func resolve(_ data: Data, for source: AIUsageSource) {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            Self.log.error("The saved \(source.rawValue, privacy: .public) folder can't be opened any more")
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                      includingResourceValuesForKeys: nil, relativeTo: nil) {
            var saved = savedBookmarks
            saved[source.rawValue] = fresh
            savedBookmarks = saved
        }
        // A folder that moved or lost its logs reads as not picked, and the
        // panel offers to pick it again.
        guard let root = AIUsageFolder.logRoot(forPicked: url, source: source) else {
            url.stopAccessingSecurityScopedResource()
            return
        }
        grants[source] = Grant(picked: url, logRoot: root)
    }

    private func stopAccessing(_ source: AIUsageSource) {
        grants[source]?.picked.stopAccessingSecurityScopedResource()
    }

    private static let log = Logger(subsystem: "Tabbi", category: "AIUsage")
}
