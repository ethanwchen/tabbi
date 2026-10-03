import AppKit
import TabbiKitCore
import TabbiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let edition = Edition.current
        let settings = SettingsStore(catalog: ModuleList.catalog, defaultKitID: edition.defaultKitID, kitStore: .standard(for: edition))
        let services = AppServices(settings: settings)
        self.services = services
        notch = NotchController(content: ModuleViews.notchContent(services: services),
                                inputs: ModuleViews.notchInputs(services: services))
        if !settings.settings.hasChosenKit {
            let welcome = WelcomeWindowController(settings: settings)
            self.welcome = welcome
            welcome.present()
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
