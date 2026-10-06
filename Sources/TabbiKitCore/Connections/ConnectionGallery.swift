import Foundation

extension ConnectionKind {
    /// Every state this row can show, from nothing to connected, so each
    /// one can be rendered and reviewed. The order follows the path a new
    /// user walks: missing first, connected last.
    public var everyState: [ConnectionDiagnosis] {
        switch self {
        case .calendar:
            let accesses: [CalendarConnectionState] = [
                CalendarConnectionState(access: .notDetermined),
                CalendarConnectionState(access: .denied),
                CalendarConnectionState(access: .restricted),
                CalendarConnectionState(access: .writeOnly),
                CalendarConnectionState(access: .fullAccess),
                CalendarConnectionState(access: .fullAccess, accounts: ["iCloud"]),
                CalendarConnectionState(access: .fullAccess, accounts: ["iCloud", "Google"]),
            ]
            return accesses.map(\.diagnosis)
        case .anki:
            let states: [AnkiConnectionState] = [
                .checking, .notInstalled, .notRunning, .starting, .addOnMissing,
                .needsPermission(.permissionDenied), .needsPermission(.apiKeyRequired), .addOnOutdated,
                .problem(.collectionUnavailable), .problem(.timeout), .problem(.transport("")), .ready,
            ]
            return states.map(\.diagnosis)
        case .spotify, .music:
            let app: ConnectionApp = self == .spotify ? .spotify : .music
            // Music comes with every Mac, so only Spotify can be missing.
            let missing = app == .spotify ? [MusicConnectionState(app: app, isInstalled: false, permission: .notAsked)] : []
            let states: [MusicConnectionState] = missing + [
                MusicConnectionState(app: app, isInstalled: true, permission: .notAsked),
                MusicConnectionState(app: app, isInstalled: true, permission: .appClosed),
                MusicConnectionState(app: app, isInstalled: true, permission: .denied),
                MusicConnectionState(app: app, isInstalled: true, permission: .appClosed, grantedBefore: true),
                MusicConnectionState(app: app, isInstalled: true, permission: .granted),
            ]
            return states.map(\.diagnosis)
        case .notifications:
            return NotificationAccess.allCases.map(\.diagnosis)
        case .doNotDisturb:
            let on = FocusSettings.suggestedOnShortcut, off = FocusSettings.suggestedOffShortcut
            let lists: [Set<String>?] = [[], [on], [off], [on, off]]
            let unknown = [FocusShortcutsState(onName: on, offName: off, installed: nil),
                           FocusShortcutsState(onName: on, offName: off, installed: nil, couldNotList: true)]
            let turnedOff = FocusShortcutsState(onName: on, offName: off, installed: [on, off], isTurnedOn: false)
            return ([turnedOff] + unknown + lists.map { FocusShortcutsState(onName: on, offName: off, installed: $0) })
                .map(\.diagnosis)
        case .claude:
            let states: [ClaudeConnectionState] = [.checking, .notInstalled, .signedOut, .ready]
            return states.map(\.diagnosis)
        case .party:
            let states: [PartyConnectionState] = [.notSetUp, .connecting, .offline, .connected(friendCode: "PUFF-42")]
            return states.map(\.diagnosis)
        }
    }
}
