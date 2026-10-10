import Foundation
import ServiceManagement
import TabbiKitCore

/// Registers Tabbi as a login item, through `SMAppService.mainApp` in the app.
///
/// The system, not our defaults, is the source of truth: the user can remove
/// or approve the item in System Settings › General › Login Items at any
/// time, so `SettingsStore` reads `status` again whenever Tabbi comes back
/// to the front. Tests pass a stand-in for the system.
struct LaunchAtLogin {
    enum Failure: LocalizedError {
        case notBundled

        var errorDescription: String? {
            "Launch at login is only available when \(Edition.current.name) runs as an app (scripts/run.sh)."
        }
    }

    enum Status: Equatable {
        case off
        case on
        /// Registered, but blocked in System Settings › Login Items.
        case needsApproval
    }

    /// False for a `swift run` binary, which `SMAppService` cannot register.
    var isAvailable: Bool
    var status: () -> Status
    var register: () throws -> Void
    var unregister: () throws -> Void

    /// The app's own login item.
    static var system: LaunchAtLogin {
        LaunchAtLogin(
            // `SMAppService` can only register a real `.app` bundle.
            isAvailable: Bundle.main.bundleURL.pathExtension == "app",
            status: {
                switch SMAppService.mainApp.status {
                case .enabled: .on
                case .requiresApproval: .needsApproval
                default: .off
                }
            },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() }
        )
    }

    /// True when registered, including when macOS still waits for the user's approval.
    var isEnabled: Bool { isAvailable && status() != .off }

    /// True when the item is registered but blocked in System Settings › Login Items.
    var needsApproval: Bool { isAvailable && status() == .needsApproval }

    func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { throw Failure.notBundled }
        guard enabled != isEnabled else { return }
        if enabled {
            try register()
        } else {
            try unregister()
        }
    }
}
