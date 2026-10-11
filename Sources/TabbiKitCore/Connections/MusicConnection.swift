import Foundation

/// What macOS says about Tabbi controlling a music app (Automation).
public enum AutomationPermission: String, CaseIterable, Hashable, Sendable {
    case granted
    case denied
    /// macOS hasn't asked yet.
    case notAsked
    /// macOS can only answer while the app is open, and it's closed.
    case appClosed
}

/// Where the connection to Spotify or Music stands.
public struct MusicConnectionState: Hashable, Sendable {
    public var app: ConnectionApp
    public var isInstalled: Bool
    public var permission: AutomationPermission
    /// Whether an earlier check, while the app was open, found access
    /// granted. Lets a closed app still read as connected.
    public var grantedBefore: Bool

    public init(app: ConnectionApp, isInstalled: Bool, permission: AutomationPermission, grantedBefore: Bool = false) {
        self.app = app
        self.isInstalled = isInstalled
        self.permission = permission
        self.grantedBefore = grantedBefore
    }

    public var connectionStatus: ConnectionStatus {
        let name = app.displayName
        guard isInstalled else {
            return ConnectionStatus(light: .notInstalled, headline: String(localized: "\(name) isn't on this Mac", bundle: .tabbi),
                                    detail: String(localized: "Get \(name) to control your music from the notch.", bundle: .tabbi),
                                    action: app.downloadPage == nil ? nil : .download(app))
        }
        switch permission {
        case .granted:
            return ConnectionStatus(light: .connected, headline: String(localized: "\(name) is connected", bundle: .tabbi),
                                    detail: String(localized: "Play, pause and skip songs from the notch.", bundle: .tabbi))
        case .appClosed where grantedBefore:
            return ConnectionStatus(light: .connected, headline: String(localized: "\(name) is connected", bundle: .tabbi),
                                    detail: String(localized: "Play, pause and skip songs from the notch.", bundle: .tabbi))
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Tabbi can't control \(name)", bundle: .tabbi),
                                    detail: String(localized: "In System Settings, turn on \(name) under Tabbi.", bundle: .tabbi),
                                    action: .openSettings(.automationPrivacy))
        case .notAsked, .appClosed:
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "\(name) isn't connected", bundle: .tabbi),
                                    detail: String(localized: "Click Connect, then Allow when your Mac asks if Tabbi can control \(name).", bundle: .tabbi),
                                    action: .askPermission(.automation(app)))
        }
    }
}
