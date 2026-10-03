import Foundation
import ServiceManagement
import TabbiKitCore

/// Registers NotchDeck as a login item through `SMAppService.mainApp`.
///
/// The system, not our defaults, is the source of truth: the user can remove
/// the item in System Settings › General › Login Items at any time.
enum LaunchAtLogin {
    enum Failure: LocalizedError {
        case notBundled

        var errorDescription: String? {
            "Launch at login is only available when \(Edition.current.name) runs as an app (scripts/run.sh)."
        }
    }

    /// `SMAppService` can only register a real `.app` bundle, not a `swift run` binary.
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// True when registered, including when macOS still waits for the user's approval.
    static var isEnabled: Bool {
        guard isAvailable else { return false }
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// True when the item is registered but blocked in System Settings › Login Items.
    static var needsApproval: Bool {
        isAvailable && SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { throw Failure.notBundled }
        guard enabled != isEnabled else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
