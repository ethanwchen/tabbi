import AppKit
import TabbiKitCore

/// Tells the user, once, when another copy of Tabbi is installed in an
/// Applications folder.
///
/// The direct download and the App Store edition share a bundle id, so both
/// copies carry a widget extension with the same id. macOS registers only
/// one of them, and every time it switches between the two (one is opened,
/// updated or replaced) `chronod` drops the widget's cached description
/// ("Requested to add extension, but purging instead"), which can leave a
/// widget on the desktop blank until the Mac restarts. The App Store also
/// names its copy "Tabbi 2" when the direct download already sits in
/// /Applications, so this is easy to end up with without noticing
/// (docs/widget.md, Troubleshooting).
@MainActor
enum DuplicateCopyCheck {
    /// The copies already shown to the user, so each set is mentioned once.
    static let acknowledgedKey = "widget.duplicateCopiesAcknowledged"

    /// Looks for other copies a moment after launch, so the question never
    /// holds up the notch or another first-launch prompt.
    static func scheduleIfNeeded(defaults: UserDefaults = .standard) {
        guard !RunMode.current.isEphemeral, let bundleID = Bundle.main.bundleIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let fileManager = FileManager.default
            let others = otherCopies(of: Bundle.main.bundleURL,
                                     among: NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID),
                                     home: fileManager.homeDirectoryForCurrentUser) {
                fileManager.fileExists(atPath: $0.path)
            }
            let paths = others.map(\.path).sorted()
            let acknowledged = Set(defaults.stringArray(forKey: acknowledgedKey) ?? [])
            guard !paths.isEmpty, !Set(paths).isSubset(of: acknowledged) else { return }
            defaults.set(Array(acknowledged.union(paths)).sorted(), forKey: acknowledgedKey)
            show(others)
        }
    }

    /// The other installed copies among `urls` (every app LaunchServices
    /// knows with this bundle id): those in /Applications or
    /// ~/Applications, where the widget's extension is picked from, other
    /// than `bundleURL` itself. Build folders, disk images and the Trash
    /// don't count.
    nonisolated static func otherCopies(of bundleURL: URL, among urls: [URL], home: URL,
                                        exists: (URL) -> Bool) -> [URL] {
        let own = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let folders = ["/Applications/", home.appendingPathComponent("Applications").standardizedFileURL.path + "/"]
        var seen: Set<String> = [own]
        return urls.filter { url in
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard folders.contains(where: path.hasPrefix), !path.contains("/.Trash/"),
                  seen.insert(path).inserted else { return false }
            return exists(url)
        }
    }

    private static func show(_ others: [URL]) {
        let name = Edition.current.name
        let alert = NSAlert()
        alert.messageText = String(localized: "Two copies of \(name) are installed", bundle: .tabbi)
        let folder = others[0].deletingLastPathComponent().path
        alert.informativeText = String(localized: "Another copy is in \(folder). The copies share one widget, which can go blank when macOS switches between them. Keep the copy you use and move the other to the Trash.", bundle: .tabbi)
        alert.addButton(withTitle: String(localized: "Show Other Copy", bundle: .tabbi))
        alert.addButton(withTitle: String(localized: "OK", bundle: .tabbi))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(others)
        }
    }
}
