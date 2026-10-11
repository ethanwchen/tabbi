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
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "Alerts are off", bundle: .tabbi),
                                    detail: String(localized: "Click Connect, then Allow when your Mac asks. It only asks once.", bundle: .tabbi),
                                    action: .askPermission(.notifications))
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Alerts are blocked", bundle: .tabbi),
                                    detail: String(localized: "Turn on Allow Notifications for Tabbi in System Settings.", bundle: .tabbi),
                                    action: .openSettings(.notifications))
        case .allowed:
            return ConnectionStatus(light: .connected, headline: String(localized: "Alerts are on", bundle: .tabbi),
                                    detail: String(localized: "Tabbi tells you when a focus block or break ends.", bundle: .tabbi))
        }
    }
}
