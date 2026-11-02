import AppKit
import TabbiKitCore
import os

/// Runs the Do Not Disturb shortcuts in the sandboxed App Store build,
/// where `/usr/bin/shortcuts` can't start: it sends Apple Events to
/// Shortcuts Events (`ShortcutsEventsScript`), which runs a shortcut in the
/// background without opening the Shortcuts app.
///
/// macOS asks the user once before the first event (Automation). Nothing
/// here asks by surprise: `runner` and `names()` check the permission first
/// and give up quietly when it isn't granted, so the question only comes
/// from `permission(askIfNeeded: true)`, which the priming screens call
/// after their Continue button.
enum ShortcutsEvents {
    /// The runner focus mode and the Test buttons use in this build: the
    /// command line tool in the direct download, Shortcuts Events where the
    /// app is sandboxed.
    static func runner(for edition: Edition) -> any FocusShortcutRunning {
        edition.isSandboxed ? Runner() : FocusShortcutRunner()
    }

    /// Whether Tabbi may send Shortcuts Events Apple Events. It starts
    /// Shortcuts Events first, since macOS can only answer for an app that
    /// is running; it is a background app, so nothing shows on screen.
    static func permission(askIfNeeded: Bool) async -> AutomationPermission {
        let bundleID = ShortcutsEventsScript.bundleIdentifier
        var permission = await ConnectionProbes.automationPermission(for: bundleID, askIfNeeded: askIfNeeded)
        if permission == .appClosed, await launch() {
            permission = await ConnectionProbes.automationPermission(for: bundleID, askIfNeeded: askIfNeeded)
        }
        return permission
    }

    /// The names of the user's shortcuts, or nil when they can't be read
    /// (no permission yet, or Shortcuts Events didn't answer).
    static func names() async -> Set<String>? {
        guard await permission(askIfNeeded: false) == .granted else { return nil }
        let reply = await execute(ShortcutsEventsScript.listNames)
        guard reply.error == nil, let list = reply.descriptor else { return nil }
        // A list descriptor's items are 1-based.
        let count = list.numberOfItems
        guard count > 0 else { return list.stringValue.map { [$0] } ?? [] }
        return Set((1...count).compactMap { list.atIndex($0)?.stringValue })
    }

    /// Runs shortcuts through Shortcuts Events once the user allowed it.
    struct Runner: FocusShortcutRunning {
        func run(_ name: String) async -> FocusShortcutResult {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .notFound(name: name) }
            switch await ShortcutsEvents.permission(askIfNeeded: false) {
            case .granted: break
            case .appClosed: return .unavailable
            case .denied, .notAsked: return .notAllowed
            }
            let reply = await ShortcutsEvents.execute(ShortcutsEventsScript.run(name))
            if let error = reply.error {
                ShortcutsEvents.log.error("Shortcuts Events run failed (\(error.number)): \(error.message, privacy: .public)")
            }
            return ShortcutsEventsScript.result(errorNumber: reply.error?.number, message: reply.error?.message, name: name)
        }
    }

    // MARK: Plumbing

    private struct Reply: @unchecked Sendable {
        var descriptor: NSAppleEventDescriptor?
        var error: (number: Int, message: String)?
    }

    /// Runs `source` off the main thread, one script at a time.
    private static func execute(_ source: String) async -> Reply {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                guard let error else { return continuation.resume(returning: Reply(descriptor: output)) }
                let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                let message = error[NSAppleScript.errorMessage] as? String ?? ""
                continuation.resume(returning: Reply(descriptor: nil, error: (number, message)))
            }
        }
    }

    /// Starts Shortcuts Events without bringing anything forward.
    private static func launch() async -> Bool {
        guard let url = await MainActor.run(body: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: ShortcutsEventsScript.bundleIdentifier)
        }) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else { return false }
        // It answers Apple Events a moment after it starts.
        try? await Task.sleep(for: .milliseconds(300))
        return true
    }

    /// Serial and off the main thread: `NSAppleScript` isn't safe to run
    /// concurrently, and a shortcut can take seconds.
    private static let queue = DispatchQueue(label: "dev.tabbi.focus.shortcuts-events", qos: .userInitiated)

    private static let log = Logger(subsystem: "Tabbi", category: "Focus")
}
