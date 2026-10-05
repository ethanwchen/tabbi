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
        let name = app.name
        guard isInstalled else {
            return ConnectionStatus(light: .notInstalled, headline: "\(name) isn't on this Mac",
                                    detail: "Get \(name) to control your music from the notch.",
                                    action: app.downloadPage == nil ? nil : .download(app))
        }
        switch permission {
        case .granted:
            return ConnectionStatus(light: .connected, headline: "\(name) is connected",
                                    detail: "Play, pause and skip songs from the notch.")
        case .appClosed where grantedBefore:
            return ConnectionStatus(light: .connected, headline: "\(name) is connected",
                                    detail: "Play, pause and skip songs from the notch.")
        case .denied:
            return ConnectionStatus(light: .needsStep, headline: "Tabbi can't control \(name)",
                                    detail: "In System Settings, turn on \(name) under Tabbi.",
                                    action: .openSettings(.automationPrivacy))
        case .notAsked, .appClosed:
            return ConnectionStatus(light: .notSetUp, headline: "\(name) isn't connected",
                                    detail: "Connect it to play, pause and skip songs from the notch.",
                                    action: .askPermission(.automation(app)))
        }
    }
}
