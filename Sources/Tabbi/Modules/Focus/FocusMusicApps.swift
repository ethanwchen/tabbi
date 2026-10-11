import AppKit
import TabbiKitCore
import os

/// What a script sent to a music app came back with.
enum FocusScriptResult: Equatable, Sendable {
    case output(String)
    /// Not sent: the app wasn't running and the script mustn't launch it.
    case skipped
    /// AppleScript reported an error with this number (-1743: no
    /// Automation access).
    case failed(code: Int)

    var output: String? {
        if case .output(let text) = self { return text }
        return nil
    }
}

/// How focus mode reaches Spotify and Music. The live value checks the
/// running apps and sends AppleScript; tests pass a fake, so no test ever
/// launches or scripts a real music app.
///
/// Both editions script the apps the same way: the direct download through
/// its Hardened Runtime Apple Events entitlement, the sandboxed App Store
/// build through the Apple Events exception that lists Spotify and Music
/// (the same access Now Playing uses).
struct FocusMusicApps: Sendable {
    var isInstalled: @Sendable (MediaSource) -> Bool
    var isRunning: @Sendable (MediaSource) -> Bool
    /// Runs `script` against `source`. Unless `launching`, it's skipped when
    /// the app isn't running, since any Apple Event would launch it.
    var run: @Sendable (_ script: String, _ source: MediaSource, _ launching: Bool) async -> FocusScriptResult

    static let live = FocusMusicApps(
        isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil },
        isRunning: { isRunning($0) },
        run: { script, source, launching in
            await withCheckedContinuation { continuation in
                scriptQueue.async {
                    guard launching || isRunning(source) else { return continuation.resume(returning: .skipped) }
                    var error: NSDictionary?
                    let output = NSAppleScript(source: script)?.executeAndReturnError(&error)
                    if let error {
                        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
                        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                        log.error("Focus script for \(source.displayName, privacy: .public) failed (\(code)): \(message, privacy: .public)")
                        return continuation.resume(returning: .failed(code: code))
                    }
                    continuation.resume(returning: .output(output?.stringValue ?? ""))
                }
            }
        }
    )

    private static let log = Logger(subsystem: "Tabbi", category: "Focus")

    private static func isRunning(_ source: MediaSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    /// Serial, and off the main thread: Apple Events can block for seconds.
    private static let scriptQueue = DispatchQueue(label: "dev.tabbi.focus.applescript", qos: .userInitiated)
}
