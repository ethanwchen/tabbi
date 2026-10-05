import AppKit
import Combine
import Sparkle
import TabbiKitCore

/// Keeps Tabbi up to date through Sparkle 2: a check at launch and once a
/// day while automatic checks are on, and "Check for Updates…" in Settings
/// and the notch's context menu.
///
/// Sparkle reads the feed and the EdDSA public key from Info.plist, which
/// `scripts/release.sh` fills in; `UpdatePolicy` keeps the updater off in
/// development builds, demo and snapshot runs, and copies running from a
/// disk image, so none of those touch the network. One per process, like
/// `NSApp`: the delegate starts it once install hygiene has settled.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    let policy: UpdatePolicy
    /// False while a check or an update is already under way.
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private let userDriver = BackgroundAppUserDriverDelegate()

    private init() {
        policy = UpdatePolicy(info: Bundle.main.infoDictionary ?? [:],
                              runMode: .current,
                              location: InstallLocation(bundleURL: Bundle.main.bundleURL,
                                                        home: FileManager.default.homeDirectoryForCurrentUser))
    }

    /// Starts the updater when this copy can update itself. Call once, after
    /// install hygiene, so a copy about to move itself never checks.
    func start() {
        guard policy.isActive, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                      userDriverDelegate: userDriver)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    /// Whether the menu shows "Check for Updates…": only when the updater runs.
    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        // Without a Dock icon Tabbi is rarely the active app; Sparkle's
        // progress and "up to date" windows only show in front if it is.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// The Settings toggle. Sparkle stores the choice in the app's defaults
    /// (`SUEnableAutomaticChecks`); release builds default it to on.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? policy.isPreview }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

/// Tabbi has no Dock icon, so a window Sparkle opens could sit behind the
/// app the user is in. Bringing Tabbi forward first makes the update
/// prompt (or the "You're up to date" answer) visible.
private final class BackgroundAppUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        MainActor.assumeIsolated { NSApp.activate() }
    }
}
