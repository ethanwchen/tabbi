import Foundation
@preconcurrency import UserNotifications
import TabbiKitCore

/// The macOS banner for a shared session that finished while the notch was
/// closed or hidden, so the "Great job, team!" moment still reaches the
/// user. Only exists in a live run inside a real app bundle:
/// `UNUserNotificationCenter` aborts in a bare `swift run` executable, and
/// demo and snapshot runs post nothing.
@MainActor
final class PartyNotifications: NSObject, UNUserNotificationCenterDelegate {
    private static let requestPrefix = "party.session.completed"
    private let center: UNUserNotificationCenter

    /// Nil outside a live run in an `.app` bundle.
    static func make(runMode: RunMode) -> PartyNotifications? {
        guard !runMode.isEphemeral,
              Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return PartyNotifications(center: .current())
    }

    private init(center: UNUserNotificationCenter) {
        self.center = center
        super.init()
        center.delegate = self
    }

    /// Posts the celebration as a banner right away. Asks for permission
    /// first if the user hasn't decided yet; a denied permission posts nothing.
    func post(_ celebration: PartyTeamCelebration) {
        let content = UNMutableNotificationContent()
        content.title = celebration.title
        content.body = celebration.detail
        let id = "\(Self.requestPrefix).\(Int64(celebration.date.timeIntervalSinceReferenceDate * 1000))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        let center = center
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
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
