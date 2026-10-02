import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices(settings: SettingsStore())
        self.services = services
        notch = NotchController(services: services)
    }
}
