import Foundation

/// Starts, finds and focuses the Anki app. The Mac implementation uses
/// `NSWorkspace`; tests inject a fake so the open flow runs without Anki.
public protocol AnkiAppLauncher: Sendable {
    /// Whether an Anki app exists on this Mac.
    func isInstalled() async -> Bool
    /// When the running Anki started, or nil when Anki is closed. A launch
    /// date of unknown age (some processes don't report one) is `.distantPast`.
    func runningSince() async -> Date?
    /// Starts Anki and brings it to the front. False when it could not start.
    func launch() async -> Bool
    /// Brings the running Anki to the front.
    func activate() async
}

/// The clock the open flow waits on, injected so tests can step through
/// a 30 second wait instantly.
public struct AnkiOpenClock: Sendable {
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let live = AnkiOpenClock(now: { Date() }, sleep: { try await Task.sleep(for: .seconds($0)) })
}

/// What the open flow is doing, so the panel can say so.
public enum AnkiOpenPhase: Hashable, Sendable {
    /// Anki is running; asking it to open the deck.
    case opening
    /// Anki was closed (or only just started); waiting for it and
    /// AnkiConnect to come up.
    case launching
}

/// How a click on a deck ended. Every case except `.notInstalled` and
/// `.launchFailed` leaves Anki in front, so the user is never left with
/// nothing happening.
public enum AnkiOpenOutcome: Hashable, Sendable {
    /// Anki is in front, reviewing this deck.
    case opened(deck: String)
    /// No deck was asked for; Anki is in front.
    case openedApp
    /// Anki is in front but AnkiConnect never answered, so the deck could
    /// not be opened. The next step is installing the add-on.
    case addOnMissing
    /// AnkiConnect answered but has no deck by that name (renamed or deleted).
    case deckNotFound(String)
    /// AnkiConnect answered with some other problem, such as the profile
    /// picker still showing when the wait ran out.
    case failed(AnkiConnectError)
    /// There is no Anki on this Mac.
    case notInstalled
    /// Anki is installed but macOS would not start it.
    case launchFailed
}

/// One click on a deck: bring Anki forward (starting it if closed), wait
/// for AnkiConnect to answer, then open that deck's review.
///
/// A freshly started Anki needs several seconds to load its profile and
/// add-ons, and its port refuses connections until then, so a refused
/// connection only means "add-on missing" once the wait runs out. Kept in
/// TabbiKitCore with an injected launcher and clock so the whole state
/// machine is testable.
public struct AnkiDeckOpener: Sendable {
    public var client: AnkiConnectClient
    public var launcher: any AnkiAppLauncher
    public var clock: AnkiOpenClock
    /// How long to wait for a just-started Anki before giving up.
    public var launchTimeout: TimeInterval
    /// Pause between attempts while waiting.
    public var pollInterval: TimeInterval

    public static let defaultLaunchTimeout: TimeInterval = 30
    public static let defaultPollInterval: TimeInterval = 0.5

    public init(
        client: AnkiConnectClient,
        launcher: any AnkiAppLauncher,
        clock: AnkiOpenClock = .live,
        launchTimeout: TimeInterval = AnkiDeckOpener.defaultLaunchTimeout,
        pollInterval: TimeInterval = AnkiDeckOpener.defaultPollInterval
    ) {
        self.client = client
        self.launcher = launcher
        self.clock = clock
        self.launchTimeout = launchTimeout
        self.pollInterval = pollInterval
    }

    /// Opens `deck` (a full name such as "Step1::Cardio") for review, or
    /// just brings Anki forward when `deck` is nil or blank.
    /// - Parameter onPhase: told when the flow starts opening or launching.
    /// - Throws: only `CancellationError`.
    public func open(deck: String?, onPhase: @Sendable (AnkiOpenPhase) async -> Void = { _ in }) async throws -> AnkiOpenOutcome {
        let name = deck.flatMap(AnkiDeckName.normalized)
        var startedAt = await launcher.runningSince()
        let launchedHere = startedAt == nil
        if launchedHere {
            guard await launcher.isInstalled() else { return .notInstalled }
            await onPhase(.launching)
            guard await launcher.launch() else { return .launchFailed }
            startedAt = clock.now()
        }
        try Task.checkCancellation()
        guard let name else {
            await launcher.activate()
            return .openedApp
        }

        // A recently started Anki (by this click or just before it) gets
        // the full wait; an Anki that has been up a while answers at once
        // or not at all.
        let now = clock.now()
        let launchedRecently = startedAt.map { now.timeIntervalSince($0) < AnkiConnectionState.startupGrace } ?? false
        if !launchedHere { await onPhase(launchedRecently ? .launching : .opening) }
        let deadline = launchedRecently ? now.addingTimeInterval(launchTimeout) : now

        while true {
            try Task.checkCancellation()
            let error: AnkiConnectError
            do {
                let found = try await client.guiDeckReview(name: name)
                await launcher.activate()
                return found ? .opened(deck: name) : .deckNotFound(name)
            } catch let failure as AnkiConnectError {
                error = failure
            }
            guard Self.isStartingUp(error), clock.now() < deadline else {
                await launcher.activate()
                return Self.outcome(for: error)
            }
            try await clock.sleep(pollInterval)
        }
    }

    /// Errors a starting Anki gives before it is ready: the port refuses,
    /// the main thread is busy loading, or the profile isn't open yet.
    static func isStartingUp(_ error: AnkiConnectError) -> Bool {
        switch error {
        case .ankiNotRunning, .addOnMissing, .timeout, .collectionUnavailable: return true
        default: return false
        }
    }

    static func outcome(for error: AnkiConnectError) -> AnkiOpenOutcome {
        switch error {
        case .ankiNotRunning, .addOnMissing: return .addOnMissing
        default: return .failed(error)
        }
    }
}

/// Anki deck names: nested decks join their path with `::`
/// ("Step1::Cardio::Arrhythmias"), and AnkiConnect wants the full path.
public enum AnkiDeckName {
    public static let separator = "::"

    /// The path's parts, trimmed, with empty parts dropped, the way Anki
    /// itself cleans a typed deck name.
    public static func components(_ name: String) -> [String] {
        name.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The full name AnkiConnect expects, or nil for a blank name.
    public static func normalized(_ name: String) -> String? {
        let parts = components(name)
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }

    /// The deck's own name: "Arrhythmias" for "Step1::Cardio::Arrhythmias".
    public static func leaf(_ name: String) -> String {
        components(name).last ?? name
    }

    /// The parent path for display, "Step1 › Cardio", or nil for a top-level deck.
    public static func parentPath(_ name: String) -> String? {
        let parts = components(name)
        return parts.count > 1 ? parts.dropLast().joined(separator: " › ") : nil
    }
}
