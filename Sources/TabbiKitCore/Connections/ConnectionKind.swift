import Foundation

/// One row in Connections: an app or permission that some tabs need.
///
/// Each kind names the modules it serves, so Connections lists only what
/// the current tabs use, in this order (the most common first).
public enum ConnectionKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case calendar
    case anki
    case spotify
    case music
    case notifications
    case doNotDisturb
    case claude
    case party

    public var id: String { rawValue }

    /// The row's name.
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .anki: "Anki"
        case .spotify: "Spotify"
        case .music: "Apple Music"
        case .notifications: "Alerts"
        case .doNotDisturb: "Do Not Disturb"
        case .claude: "Claude"
        case .party: "Party"
        }
    }

    /// An SF Symbol for the row.
    public var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .anki: "rectangle.stack.fill"
        case .spotify: "music.note"
        case .music: "music.note.list"
        case .notifications: "bell.badge.fill"
        case .doNotDisturb: "moon.fill"
        case .claude: "sparkles"
        case .party: "person.3.fill"
        }
    }

    /// What connecting it unlocks, in one plain line short enough to
    /// fit beside the widest button without wrapping.
    public var unlocks: String {
        switch self {
        case .calendar: "See today's events in the notch."
        case .anki: "See due cards and start reviews."
        case .spotify: "Play, pause and skip on Spotify."
        case .music: "Play, pause and skip in Apple Music."
        case .notifications: "Get an alert when a timer ends."
        case .doNotDisturb: "Quiet other alerts while you focus."
        case .claude: "Powers Plan my day and Ask Claude."
        case .party: "Study with friends, see their timers."
        }
    }

    /// The modules that use this connection.
    public var modules: [ModuleID] {
        switch self {
        case .calendar: [.planner]
        case .anki: [.anki]
        case .spotify, .music: [.spotify]
        case .notifications: [.planner, .focus, .study]
        case .doNotDisturb: [.planner, .focus, .study]
        case .claude: [.planner, .claudeAsk, .claudeUsage]
        case .party: [.party]
        }
    }

    /// Whether the connection runs a helper program (the `claude` CLI or
    /// Shortcuts), which a sandboxed build can't (`Edition.runsLocalTools`).
    public var needsLocalTools: Bool { self == .claude || self == .doNotDisturb }

    /// The connections the enabled modules use, in row order, leaving out
    /// those that need helper programs when `localTools` is false.
    public static func relevant(to enabled: some Sequence<ModuleID>, localTools: Bool = true) -> [ConnectionKind] {
        let enabled = Set(enabled)
        return allCases.filter { !enabled.isDisjoint(with: $0.modules) && (localTools || !$0.needsLocalTools) }
    }

    /// A believable spread of states for demo mode and snapshots: most
    /// rows connected, a couple with one step left.
    public var demoStatus: ConnectionStatus { demoDiagnosis.status }

    /// The troubleshooter's checks for `demoStatus`.
    public var demoDiagnosis: ConnectionDiagnosis {
        switch self {
        case .calendar: CalendarConnectionState(access: .fullAccess, accounts: ["iCloud", "Google"]).diagnosis
        case .anki: AnkiConnectionState.ready.diagnosis
        case .spotify: MusicConnectionState(app: .spotify, isInstalled: true, permission: .granted).diagnosis
        case .music: MusicConnectionState(app: .music, isInstalled: true, permission: .notAsked).diagnosis
        case .notifications: NotificationAccess.allowed.diagnosis
        case .doNotDisturb:
            FocusShortcutsState(onName: "Tabbi Focus On", offName: "Tabbi Focus Off",
                                installed: ["Tabbi Focus On"]).diagnosis
        case .claude: ClaudeConnectionState.ready.diagnosis
        case .party: PartyConnectionState.connected(friendCode: "PUFF-42").diagnosis
        }
    }
}
