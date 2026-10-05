import AppKit
import EventKit
import UserNotifications
import TabbiKitCore

/// Looks at the Mac to find where each connection stands. Every check is
/// read-only: nothing here asks macOS for a permission or launches an app.
/// The rules that turn what it finds into words live in TabbiKitCore.
struct ConnectionProbes: Sendable {
    /// Where one connection stands right now, with the checks behind it.
    func diagnosis(of kind: ConnectionKind) async -> ConnectionDiagnosis {
        switch kind {
        case .anki: await Self.anki().diagnosis
        case .calendar: Self.calendar().diagnosis
        case .claude: await Self.claude().diagnosis
        case .spotify: await Self.music(.spotify).diagnosis
        case .music: await Self.music(.music).diagnosis
        case .notifications: await Self.notifications().diagnosis
        case .doNotDisturb: await Self.focusShortcuts().diagnosis
        // The Party tab reports its own state (`ConnectionsStore.follow(party:)`).
        case .party: PartyConnectionState.connecting.diagnosis
        }
    }

    // MARK: Apps

    /// The first installed copy of an app, by its bundle ids in order.
    @MainActor
    static func installedURL(of app: ConnectionApp) -> URL? {
        app.bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    @MainActor
    static func isRunning(_ app: ConnectionApp) -> Bool {
        app.bundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    // MARK: Anki

    /// The same handshake the Anki tab makes, mapped through the same rules.
    private static func anki() async -> AnkiConnectionState {
        let client = AnkiConnectClient(isAnkiRunning: { await MainActor.run { runningAnki() != nil } })
        let error: AnkiConnectError?
        do {
            _ = try await client.connect()
            error = nil
        } catch let failure as AnkiConnectError {
            error = failure
        } catch {
            return .problem(.transport(error.localizedDescription))
        }
        return await MainActor.run {
            AnkiConnectionState.resolve(error: error, isInstalled: installedURL(of: .anki) != nil,
                                        launchedAt: runningAnki()?.launchDate, now: Date())
        }
    }

    @MainActor
    private static func runningAnki() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            AnkiConnectClient.isAnkiApp(bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
    }

    // MARK: Calendar

    static func calendarAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .denied
        }
    }

    private static func calendar() -> CalendarConnectionState {
        let access = calendarAccess()
        guard access == .fullAccess else { return CalendarConnectionState(access: access) }
        var accounts: [String] = []
        for calendar in EKEventStore().calendars(for: .event) where !accounts.contains(calendar.source.title) {
            accounts.append(calendar.source.title)
        }
        return CalendarConnectionState(access: access, accounts: accounts)
    }

    // MARK: Claude

    /// Finds `claude`, then asks it (with a tiny, private probe) whether
    /// someone is signed in.
    private static func claude() async -> ClaudeConnectionState {
        await Task.detached(priority: .userInitiated) {
            guard let executable = ClaudeCLI.locate() else { return ClaudeConnectionState.notInstalled }
            let output = run(executable, ClaudeConnectionState.probeArguments) ?? ""
            return .resolve(isInstalled: true, signIn: ClaudeSignIn.parse(authStatusOutput: output))
        }.value
    }

    // MARK: Spotify and Music

    private static func music(_ app: ConnectionApp) async -> MusicConnectionState {
        let isInstalled = await MainActor.run { installedURL(of: app) != nil }
        guard isInstalled, let bundleID = app.bundleIDs.first else {
            return MusicConnectionState(app: app, isInstalled: isInstalled, permission: .notAsked)
        }
        let permission = await automationPermission(for: bundleID, askIfNeeded: false)
        let key = "connections.automationGranted.\(bundleID)"
        if permission == .granted { UserDefaults.standard.set(true, forKey: key) }
        if permission == .denied || permission == .notAsked { UserDefaults.standard.removeObject(forKey: key) }
        return MusicConnectionState(app: app, isInstalled: true, permission: permission,
                                    grantedBefore: UserDefaults.standard.bool(forKey: key))
    }

    /// Whether Tabbi may send Apple Events to an app. With `askIfNeeded`
    /// macOS shows its prompt when it hasn't asked yet. The call can block
    /// for as long as the prompt is up, so it runs off the main thread.
    static func automationPermission(for bundleID: String, askIfNeeded: Bool) async -> AutomationPermission {
        await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let descriptor = target.aeDesc else { return AutomationPermission.notAsked }
            let status = AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, askIfNeeded)
            switch status {
            case noErr: return .granted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(procNotFound): return .appClosed
            default: return .notAsked
            }
        }.value
    }

    // MARK: Alerts

    /// Notification permission. `UNUserNotificationCenter` aborts outside a
    /// real app bundle (a bare `swift run`), so there it reads as not asked.
    private static func notifications() async -> NotificationAccess {
        guard isAppBundle else { return .notDetermined }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    static var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    // MARK: Do Not Disturb

    /// Lists the user's shortcuts and looks for the two that Focus runs.
    private static func focusShortcuts() async -> FocusShortcutsState {
        let (onName, offName) = focusShortcutNames()
        let output = await Task.detached(priority: .userInitiated) {
            run(FocusShortcutRunner.systemExecutable, ["list"])
        }.value
        return FocusShortcutsState(onName: onName, offName: offName,
                                   installed: FocusShortcutsState.parseList(output ?? ""))
    }

    /// The names Focus runs: the user's own, or the suggested ones.
    static func focusShortcutNames() -> (on: String, off: String) {
        let saved = FocusSettingsRepository().load()
        return (saved.onShortcut.isEmpty ? FocusSettings.suggestedOnShortcut : saved.onShortcut,
                saved.offShortcut.isEmpty ? FocusSettings.suggestedOffShortcut : saved.offShortcut)
    }

    // MARK: Running a probe

    /// Runs a short command and returns what it printed, whatever its exit
    /// status (`claude auth status` exits non-zero when signed out). Nil if
    /// it can't start or runs past `timeout`. Blocking; call off the main
    /// thread.
    private static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 10) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { [process] in if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Reading to the end drains the pipe as it fills, so a long list
        // never stalls the process; it returns once the process exits.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
