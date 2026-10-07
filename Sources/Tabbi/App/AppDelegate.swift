import AppKit
import TabbiKitCore
import TabbiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if InstallHygiene.isAnotherCopyRunning() {
            NSApp.terminate(nil)
            return
        }
        let edition = Edition.current
        if edition == .tabbi, RunMode.current == .live {
            // Before any store opens a file: adopts NotchDeck's data once.
            LegacyDataMigration.tabbi(storage: EditionStorage(edition: edition)).runIfNeeded()
        }
        let settings = SettingsStore(catalog: ModuleList.catalog, defaultKitID: edition.defaultKitID, kitStore: .standard(for: edition))
        guard InstallHygiene.settle(settings: settings) == .proceed else {
            NSApp.terminate(nil)
            return
        }
        AppUpdater.shared.start()
        MainMenu.install()
        let services = AppServices(settings: settings)
        self.services = services
        InstallHygiene.whenAnotherCopyLaunches { [weak services] in services?.openSettings() }
        notch = NotchController(content: ModuleViews.notchContent(services: services),
                                inputs: ModuleViews.notchInputs(services: services))
        // First run: the notch opens on setup and stays open until it ends.
        if !settings.settings.hasChosenKit {
            services.onboarding.start()
        }
    }

    /// With no Dock icon or menu bar item, opening the app again (from Finder,
    /// Spotlight, or `open`) is the natural way back into Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.modules.stopAll()
    }
}
