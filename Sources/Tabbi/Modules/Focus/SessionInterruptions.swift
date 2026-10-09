import AppKit
import Combine

/// Calls `handler` when the Mac is about to sleep or Tabbi is quitting, so
/// a focus or study session under way ends there and is credited for the
/// time actually focused, instead of running on through the night or being
/// paid in full on the next launch.
///
/// The handler runs synchronously on the main actor before the Mac sleeps
/// or the app exits, so what it saves (the stopped timer, the activity
/// record, and the pet's points, which follow the shared clock through the
/// provider snapshot on the same call) is on disk by then.
@MainActor
final class SessionInterruptions {
    private let subscription: AnyCancellable

    /// - Parameters:
    ///   - workspace: where `NSWorkspace.willSleepNotification` is posted;
    ///     tests pass a center of their own.
    ///   - app: where `NSApplication.willTerminateNotification` is posted.
    init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
         app: NotificationCenter = .default,
         handler: @escaping @MainActor () -> Void) {
        // Both are posted on the main thread, so the handler runs before the
        // sleep or the exit goes ahead.
        subscription = workspace.publisher(for: NSWorkspace.willSleepNotification)
            .merge(with: app.publisher(for: NSApplication.willTerminateNotification))
            .sink { _ in MainActor.assumeIsolated { handler() } }
    }
}
