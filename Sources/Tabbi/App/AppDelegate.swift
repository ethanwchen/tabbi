import AppKit
import TabbiKitCore
import TabbiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: AppServices?
    private var notch: NotchController?
    /// Links that arrived before the notch was up, opened once it is.
    private var pendingLinks: [URL] = []

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
        if Self.watchesForCrashes(in: RunMode.current) {
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
        let links = pendingLinks
        pendingLinks = []
        application(NSApp, open: links)
        #if !APPSTORE
        if Self.watchesForCrashes(in: RunMode.current) {
            // Asked once the notch is up, so the prompt never holds up launch.
            let report = CrashHandler.takePendingReport(in: EditionStorage(edition: edition))
            // Watched only from here on, so a hang never overwrites that report.
            HangWatchdog.shared.start()
            DispatchQueue.main.async { CrashReportFlow.live.run(with: report) }
        }
        #endif
    }

    /// Only the real app installs the crash handler, offers a pending report
    /// and watches for hangs: demo and snapshot runs must neither write a crash
    /// log into the user's data nor ask them to send one.
    nonisolated static func watchesForCrashes(in mode: RunMode) -> Bool {
        mode == .live
    }

    /// With no Dock icon or menu bar item, opening the app again (from Finder,
    /// Spotlight, or `open`) is the natural way back into Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.openSettings()
        return false
    }

    /// `tabbi://` links (Info.plist registers the scheme): Party invites from
    /// tabbinotch.com and the widget's open link.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let services, let notch else {
            pendingLinks += urls
            return
        }
        let router = AppLinkRouter(services: services, notch: notch.model)
        urls.forEach { router.open($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.accountSync.flushOnQuit()
        services?.modules.stopAll()
    }
}
