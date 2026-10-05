import AppKit
import TabbiKitCore

/// Finds, starts and focuses the Anki app through `NSWorkspace`, matching
/// either of Anki's bundle ids (or, for a renamed copy, its name).
struct AnkiWorkspaceLauncher: AnkiAppLauncher {
    func isInstalled() async -> Bool {
        await MainActor.run { Self.applicationURL != nil || Self.runningAnki() != nil }
    }

    func runningSince() async -> Date? {
        await MainActor.run {
            guard let anki = Self.runningAnki() else { return nil }
            return anki.launchDate ?? .distantPast
        }
    }

    func launch() async -> Bool {
        guard let url = await MainActor.run(body: { Self.applicationURL }) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                continuation.resume(returning: app != nil && error == nil)
            }
        }
    }

    func activate() async {
        await MainActor.run { _ = Self.runningAnki()?.activate() }
    }

    // MARK: Finding Anki

    /// The running Anki, matched by either bundle id or by name.
    @MainActor
    static func runningAnki() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            AnkiConnectClient.isAnkiApp(bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
    }

    /// Where Anki is installed, by either bundle id.
    static var applicationURL: URL? {
        AnkiConnectClient.ankiBundleIdentifiers.lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }
}
