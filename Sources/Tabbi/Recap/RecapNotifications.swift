import Foundation
@preconcurrency import UserNotifications
import TabbiKitCore

/// The macOS notification that a weekly recap is ready, so a user who
/// rarely opens the notch on a Sunday still hears about their week. Only
/// exists in a live run inside a real app bundle: `UNUserNotificationCenter`
/// aborts in a bare `swift run` executable, and demo and snapshot runs post
/// nothing.
@MainActor
final class RecapNotifications: NSObject, UNUserNotificationCenterDelegate {
    private static let requestID = "recap.weekly.ready"
    private let center: UNUserNotificationCenter

    /// Nil outside a live run in an `.app` bundle.
    static func make(runMode: RunMode) -> RecapNotifications? {
        guard !runMode.isEphemeral,
              Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return RecapNotifications(center: .current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
    }

    /// Posts `notice` quietly, with no sound. A user who hasn't decided on
    /// Tabbi's notifications yet gets it on trial in Notification Center
    /// (provisional), so a weekly card never pops a permission prompt out
    /// of nowhere; a denied permission posts nothing.
    func post(_ notice: RecapNotice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        // One id, so a newer week's notice replaces an older one still listed.
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        let center = center
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .provisional]) { granted, _ in
                    if granted { center.add(request) }
                }
            default:
                break
            }
        }
    }

    /// Tabbi is always "frontmost" as an accessory app, so ask for the
    /// banner explicitly or macOS would swallow it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
