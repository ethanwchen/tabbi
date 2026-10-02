import AppKit
import NotchKitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let edition = Edition.current
        let settings = SettingsStore(defaultKitID: edition.defaultKitID, kitStore: .standard(for: edition))
        let services = AppServices(settings: settings)
        self.services = services
        notch = NotchController(services: services)
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
