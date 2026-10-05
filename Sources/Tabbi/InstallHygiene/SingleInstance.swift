import AppKit

/// Keeps one copy of Tabbi running: two would draw two notches and fight
/// over the hotkey and the data files.
///
/// A second copy asks the first to show itself through a distributed
/// notification named after the bundle id, rather than an Apple Event,
/// which would need the user's Automation permission.
@MainActor
enum SingleInstance {
    private static var observer: NSObjectProtocol?

    private static func notificationName(_ bundleID: String) -> Notification.Name {
        Notification.Name(bundleID + ".anotherCopyLaunched")
    }

    /// When another process with this bundle id runs, asks it to show
    /// itself and returns true, so this one can quit quietly.
    static func handOffToRunningCopy() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ownPID && !$0.isTerminated }) else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName(bundleID), object: nil, userInfo: nil, deliverImmediately: true)
        other.activate()
        return true
    }

    /// Calls `show` whenever a second copy launches and hands off to this one.
    static func onAnotherCopyLaunched(_ show: @escaping @MainActor @Sendable () -> Void) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName(bundleID), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { show() }
        }
    }
}
