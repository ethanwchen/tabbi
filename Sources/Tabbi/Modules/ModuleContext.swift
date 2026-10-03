import Combine
import Foundation
import os
import TabbiKitCore

/// Everything a module may use from the app, handed to `init(context:)`.
///
/// Modules build and own their stores from this, so adding a module never
/// means editing `AppServices`. It gives read access to settings and the
/// active kit, the merged provider snapshot, app-wide shared services, the
/// edition and a logger, and nothing that reaches into another module.
@MainActor
struct ModuleContext {
    /// The module this context was made for.
    let id: ModuleID
    /// The edition this process runs as.
    let edition: Edition
    /// App settings and the kit library. Read them (and follow
    /// `kitApplied`); only the Settings window changes them.
    let settings: SettingsStore
    /// What the enabled modules share, merged. Read it instead of another
    /// module's store.
    let providers: ProviderHub
    /// App-wide services that several modules use (say, the one focus
    /// timer Today and Focus both show), created on first use.
    let shared: SharedServices
    /// Logs under this module's id.
    let logger: Logger
    /// Live, demo data or snapshot rendering. Hand it to your store rather
    /// than reading the environment, so demo and snapshot runs behave the
    /// same in every module.
    let runMode: RunMode

    init(id: ModuleID, edition: Edition, settings: SettingsStore, providers: ProviderHub,
         shared: SharedServices, runMode: RunMode) {
        self.id = id
        self.edition = edition
        self.settings = settings
        self.providers = providers
        self.shared = shared
        self.runMode = runMode
        logger = Logger(subsystem: "Tabbi", category: id.rawValue)
    }

    /// Where this edition keeps its files. Put a module's files in a folder
    /// of it (`storage.folder("Planner")`), never in a hardcoded app folder,
    /// so each edition keeps its own data.
    var storage: EditionStorage { EditionStorage(edition: edition) }

    /// `NOTCHDECK_DEMO=1`: show realistic sample data and never touch the
    /// network, disk, Spotify, Music, Calendar or the `claude` CLI.
    var isDemo: Bool { runMode.isDemo }
    /// Rendering `--snapshot` PNGs: no sounds, nothing saved.
    var isSnapshot: Bool { runMode.isSnapshot }

    /// The kit the user has active now.
    var activeKit: KitManifest? { settings.activeKit }

    /// Sent each time the user applies a kit, including re-applying the
    /// active one, so a module can take on the kit's defaults for it.
    var kitApplied: AnyPublisher<SettingsStore.KitApplication, Never> { settings.kitApplied.eraseToAnyPublisher() }
}

/// App-wide services shared by several modules, keyed by type and created
/// the first time any module asks, so no shared file has to list them.
///
/// Declare one as a `ModuleContext` extension property in the folder of the
/// module that owns it, e.g. `var focusTimer: FocusStore { shared.resolve {
/// FocusStore(...) } }`, so every module asking gets the same instance.
@MainActor
final class SharedServices {
    private var services: [ObjectIdentifier: AnyObject] = [:]

    /// The one `Service` for this app, made by `make` on first use.
    func resolve<Service: AnyObject>(_ make: () -> Service) -> Service {
        let key = ObjectIdentifier(Service.self)
        if let existing = services[key] as? Service { return existing }
        let service = make()
        services[key] = service
        return service
    }
}
