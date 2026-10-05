import AppKit
import TabbiKitCore

/// First-launch install hygiene: makes sure one copy of Tabbi runs, from an
/// Applications folder, and starts at login, before onboarding takes over.
///
/// `AppDelegate` asks `isAnotherCopyRunning()` first thing and quits if so,
/// then calls `settle(settings:)` once settings exist and before it builds
/// any module, and registers `whenAnotherCopyLaunches` once it has. Onboarding
/// (the welcome window) starts only when `settle` returns `.proceed`, so the
/// user never answers kit questions in a copy that is about to quit. Demo and
/// snapshot runs leave the system alone.
@MainActor
enum InstallHygiene {
    /// What the app does after `settle(settings:)`.
    enum Outcome: Equatable {
        /// Carry on: build the app, then hand off to onboarding.
        case proceed
        /// The copy in Applications opens once this process is gone; quit.
        case quit
    }

    /// True when another copy already runs; it has been asked to show
    /// itself, so this one should quit without a word.
    static func isAnotherCopyRunning() -> Bool {
        !RunMode.current.isEphemeral && SingleInstance.handOffToRunningCopy()
    }

    /// How this copy shows itself when a second one launches and quits:
    /// the app passes what reopening it does (open Settings).
    static func whenAnotherCopyLaunches(_ show: @escaping @MainActor @Sendable () -> Void) {
        guard !RunMode.current.isEphemeral else { return }
        SingleInstance.onAnotherCopyLaunched(show)
    }

    /// Offers the move to Applications when the app runs from somewhere
    /// else, and turns launch at login on, the one time it defaults to on,
    /// for a new user running from Applications.
    static func settle(settings: SettingsStore, defaults: UserDefaults = .standard) -> Outcome {
        guard !RunMode.current.isEphemeral else { return .proceed }
        let location = InstallLocation(bundleURL: Bundle.main.bundleURL,
                                       home: FileManager.default.homeDirectoryForCurrentUser)
        let plan = InstallHygienePlan(location: location,
                                      record: InstallRecord.load(from: defaults),
                                      runMode: RunMode.current,
                                      isReturningUser: settings.settings.hasChosenKit)
        guard var record = plan.record ?? InstallRecord.load(from: defaults) else { return .proceed }
        defer { record.save(to: defaults) }
        if plan.offerMove, AppMover.offerMove(location: location, record: &record) {
            return .quit
        }
        if plan.enableLaunchAtLogin, !settings.settings.launchAtLogin {
            settings.setLaunchAtLogin(true)
        }
        return .proceed
    }
}
