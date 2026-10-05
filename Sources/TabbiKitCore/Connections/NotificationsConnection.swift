import Foundation

/// Whether macOS lets Tabbi show notifications, mirrored from
/// `UNAuthorizationStatus` (provisional and ephemeral count as allowed).
public enum NotificationAccess: String, CaseIterable, Hashable, Sendable {
    case notDetermined
    case denied
    case allowed

    public var connectionStatus: ConnectionStatus {
        switch self {
        case .notDetermined:
            return ConnectionStatus(light: .notSetUp, headline: "Alerts are off",
                                    detail: "Turn them on to hear when a focus block or break ends.",
                                    action: .askPermission(.notifications))
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: "Alerts are blocked",
                                    detail: "Turn on Allow Notifications for Tabbi in System Settings.",
                                    action: .openSettings(.notifications))
        case .allowed:
            return ConnectionStatus(light: .connected, headline: "Alerts are on",
                                    detail: "Tabbi tells you when a focus block or break ends.")
        }
    }
}
