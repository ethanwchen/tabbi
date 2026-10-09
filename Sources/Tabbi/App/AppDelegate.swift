import AppKit
import TabbiKitCore
import TabbiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The App Store installs, moves and updates the app itself, so its
        // build has no install hygiene and no updater (see Package.swift).
        #if !APPSTORE
        if InstallHygiene.isAnotherCopyRunning() {
            NSApp.terminate(nil)
            return
        }
        #endif
        let edition = Edition.current
        if edition == .tabbi, RunMode.current == .live {
            // Before any store opens a file: adopts NotchDeck's data once.
            LegacyDataMigration.tabbi(storage: EditionStorage(edition: edition)).runIfNeeded()
        }
        #if !APPSTORE
        // The App Store build relies on Apple's crash reports instead.
        if RunMode.current == .live {
            CrashHandler.install(in: EditionStorage(edition: edition), environment: Feedback.environment)
        }
        #endif
        let settings = SettingsStore(catalog: ModuleList.catalog(for: edition), defaultKitID: edition.defaultKitID, kitStore: .standard(for: edition))
        #if !APPSTORE
        guard InstallHygiene.settle(settings: settings) == .proceed else {
            NSApp.terminate(nil)
            return
        }
        AppUpdater.shared.start()
        #endif
        MainMenu.install()
        let services = AppServices(settings: settings)
        self.services = services
        #if !APPSTORE
        InstallHygiene.whenAnotherCopyLaunches { [weak services] in services?.openSettings() }
        #endif
        notch = NotchController(content: ModuleViews.notchContent(services: services),
                                inputs: ModuleViews.notchInputs(services: services))
        // First run: the notch opens on setup and stays open until it ends.
        if !settings.settings.hasChosenKit {
            services.onboarding.start()
        }
        services.accountSync.start()
    }

    /// With no Dock icon or menu bar item, opening the app again (from Finder,
    /// Spotlight, or `open`) is the natural way back into Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.accountSync.flushOnQuit()
        services?.modules.stopAll()
    }
}
