import Foundation

/// Where the Anki tab stands with AnkiConnect, one case per screen the
/// panel can show. Built from the latest refresh by `resolve(...)`, so the
/// rules (Anki still starting, which errors are setup steps) are testable.
public enum AnkiConnectionState: Hashable, Sendable {
    /// Before the first refresh finishes.
    case checking
    /// No Anki app on this Mac.
    case notInstalled
    /// Anki is installed but closed.
    case notRunning
    /// Anki was just opened and AnkiConnect isn't listening yet. Anki needs a
    /// few seconds to load add-ons, so this is not yet "add-on missing".
    case starting
    /// Anki runs but nothing answers on the port: the add-on isn't installed,
    /// is disabled, or Anki wasn't restarted after installing it.
    case addOnMissing
    /// AnkiConnect answered but won't let us in: permission was denied or an
    /// API key is required. The error says which.
    case needsPermission(AnkiConnectError)
    /// The add-on is too old for API version 6.
    case addOnOutdated
    /// Connected; the summary is current.
    case ready
    /// Anything else, such as a modal dialog blocking Anki or the profile
    /// picker. Transient, so the panel keeps the last summary if it has one.
    case problem(AnkiConnectError)

    /// How long after Anki launches a refused connection still means
    /// "starting" rather than "add-on missing".
    public static let startupGrace: TimeInterval = 15

    /// The state for a refresh outcome.
    /// - Parameters:
    ///   - error: the refresh's error, or nil when it succeeded.
    ///   - isInstalled: whether an Anki app exists on disk.
    ///   - launchedAt: when the running Anki process started, if known.
    ///   - now: the current instant.
    public static func resolve(error: AnkiConnectError?, isInstalled: Bool, launchedAt: Date?, now: Date) -> AnkiConnectionState {
        guard let error else { return .ready }
        switch error {
        case .ankiNotRunning:
            // The HTTP probe is the source of truth: an install we couldn't
            // find (a portable copy, say) still runs, so only a refused
            // connection with nothing on disk reads as "not installed".
            return isInstalled ? .notRunning : .notInstalled
        case .addOnMissing:
            if let launchedAt, now.timeIntervalSince(launchedAt) < startupGrace { return .starting }
            return .addOnMissing
        case .permissionDenied, .apiKeyRequired:
            return .needsPermission(error)
        case .addOnOutdated, .unsupportedAction:
            return .addOnOutdated
        case .timeout, .collectionUnavailable, .syncNotConfigured, .anki, .invalidResponse, .transport:
            return .problem(error)
        }
    }

    /// True for the states that need the user to do something before any
    /// numbers can show (open Anki, install the add-on, allow access).
    public var isSetupStep: Bool {
        switch self {
        case .notInstalled, .notRunning, .starting, .addOnMissing, .needsPermission, .addOnOutdated: return true
        case .checking, .ready, .problem: return false
        }
    }

    /// Whether a summary from an earlier refresh is still worth showing.
    /// A transient problem keeps it (dimmed as stale); a setup step means
    /// Anki is gone, so old numbers would mislead.
    public var keepsLastSummary: Bool {
        switch self {
        case .ready, .problem, .checking: return true
        default: return false
        }
    }

    /// How often to refresh while the panel is visible. Setup steps poll
    /// quickly so the panel flips to the deck view moments after the user
    /// opens Anki or restarts it with the add-on; otherwise the due counts
    /// only change as the user reviews, so a few minutes is plenty.
    public var refreshInterval: TimeInterval {
        switch self {
        case .starting: return 2
        case .notRunning, .addOnMissing, .needsPermission, .addOnOutdated, .checking: return 5
        case .problem: return 30
        case .notInstalled: return 60
        case .ready: return 180
        }
    }
}

extension AnkiSummary {
    /// The Anki day this summary describes (the last history entry).
    public var day: AnkiDay? { history.last?.day }

    /// Whether this summary still describes today. Due counts reset at
    /// Anki's rollover, so yesterday's numbers must not be shared as today's.
    public func isCurrent(now: Date, rolloverHour: Int = 4, calendar: Calendar = .current) -> Bool {
        day == AnkiDay(date: now, rolloverHour: rolloverHour, calendar: calendar)
    }

    /// The instant the next Anki day starts after `now`, when due counts
    /// reset and a summary from today stops being current.
    public static func nextRollover(after now: Date, rolloverHour: Int = 4, calendar: Calendar = .current) -> Date {
        let tomorrow = AnkiDay(date: now, rolloverHour: rolloverHour, calendar: calendar).adding(days: 1)
        let start = DateComponents(year: tomorrow.year, month: tomorrow.month, day: tomorrow.day, hour: rolloverHour)
        return calendar.date(from: start) ?? now.addingTimeInterval(86_400)
    }

    /// Top-level decks with cards due, most due first, ties by name. Anki
    /// rolls children into parents, so listing only roots never double counts.
    public var topDecks: [AnkiDeckStats] {
        Self.rootDecks(decks)
            .filter { $0.dueTotal > 0 }
            .sorted { $0.dueTotal != $1.dueTotal ? $0.dueTotal > $1.dueTotal : $0.name < $1.name }
    }

    /// Share of today's work done: reviewed out of reviewed plus still due.
    /// 1 when nothing was due at all.
    public var completionFraction: Double {
        let target = reviewedToday + dueTotal
        return target > 0 ? Double(reviewedToday) / Double(target) : 1
    }
}

extension AnkiConnectionState {
    /// Parses a state name for `NOTCHDECK_ANKI_STATE`, which pins the Anki
    /// tab to one screen so every setup state can be snapshotted without
    /// uninstalling Anki or its add-on. Nil for an unknown name.
    public init?(previewName: String) {
        switch previewName.lowercased() {
        case "checking": self = .checking
        case "notinstalled": self = .notInstalled
        case "notrunning": self = .notRunning
        case "starting": self = .starting
        case "addonmissing": self = .addOnMissing
        case "permission", "permissiondenied": self = .needsPermission(.permissionDenied)
        case "apikey", "apikeyrequired": self = .needsPermission(.apiKeyRequired)
        case "addonoutdated": self = .addOnOutdated
        case "problem": self = .problem(.timeout)
        case "ready": self = .ready
        default: return nil
        }
    }
}
