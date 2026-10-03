import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// One tab of the notch: its metadata, its panel, and its lifecycle.
///
/// Each feature implements this in its own `Modules/<Module>/` folder and is
/// listed once in `ModuleList`, so adding a module never means editing a
/// switch in shared code. A module builds and owns its store from the
/// `ModuleContext` it is created with; modules live as long as the app, so
/// that state outlives the panel.
@MainActor
protocol NotchModule: AnyObject {
    /// Id, title, symbol, category, accent, and permissions. Kits refer to
    /// modules by `descriptor.id`. Static so the catalog (layouts, kits,
    /// the tab bar) is known before any module is created.
    nonisolated static var descriptor: ModuleDescriptor { get }

    /// Creates the module once at launch, whether or not it is enabled.
    /// Build stores here and follow what the context offers (the provider
    /// snapshot, kit changes); start background work in `start()`.
    init(context: ModuleContext)

    /// The panel shown while this tab is selected, laid out inside the fixed
    /// canvas (`Theme.Layout.expandedSize` minus header and insets).
    func makePanel() -> AnyView

    /// A pane for the Settings window's toolbar, shown while the module is
    /// enabled, or nil when it has nothing to configure beyond the Modules
    /// pane's on/off switch.
    func makeSettingsPane() -> SettingsPane?

    /// Called when the module becomes enabled in the layout (at launch, or
    /// when the user or a kit turns it on). Start background work the module
    /// needs while its panel is closed here; panel-only work belongs in the
    /// panel's `onAppear`.
    func start()

    /// Called when the module is turned off or the app quits. Undo `start()`.
    func stop()

    /// Tasks, events, progress, and focus state this module shares with
    /// Today and the ticker, re-published whenever they change; nil when it
    /// shares nothing. `ProviderHub` merges the enabled modules' values.
    /// It may emit on any thread (a network callback, say): the hub hops
    /// to the main actor itself.
    var provision: AnyPublisher<ModuleProvision, Never>? { get }
}

extension NotchModule {
    var descriptor: ModuleDescriptor { Self.descriptor }
    var id: ModuleID { descriptor.id }

    func makeSettingsPane() -> SettingsPane? { nil }
    func start() {}
    func stop() {}
    var provision: AnyPublisher<ModuleProvision, Never>? { nil }
}

/// The modules this build runs, in canonical order, keyed by id.
///
/// Drives the open notch's panels and keeps each module's `start()` /
/// `stop()` in step with the enabled tabs via `ModuleLifecycle`.
@MainActor
final class ModuleRegistry {
    /// Registered modules, in canonical order. A later duplicate id is left
    /// out, and stops debug builds, since it means two modules in the list
    /// claim the same id and one of them would silently disappear.
    let modules: [any NotchModule]
    /// The registered modules' descriptors, for layouts and kit validation.
    let catalog: ModuleCatalog
    private let index: [ModuleID: any NotchModule]
    private var lifecycle = ModuleLifecycle()

    init(_ modules: [any NotchModule]) {
        var index: [ModuleID: any NotchModule] = [:]
        var unique: [any NotchModule] = []
        for module in modules where index[module.id] == nil {
            index[module.id] = module
            unique.append(module)
        }
        self.modules = unique
        self.index = index
        catalog = ModuleCatalog(unique.map(\.descriptor))
        let duplicates = ModuleCatalog(modules.map(\.descriptor)).duplicateIDs
        if !duplicates.isEmpty {
            assertionFailure("Two modules share an id: \(duplicates.map(\.rawValue).joined(separator: ", "))")
        }
    }

    subscript(id: ModuleID) -> (any NotchModule)? { index[id] }

    /// The registered module of type `Module`, if this build has it.
    func module<Module: NotchModule>(_ type: Module.Type) -> Module? {
        index[Module.descriptor.id] as? Module
    }

    /// The panel for `id`, or a neutral placeholder when no module with that
    /// id is registered (say, a kit from a newer version lists it).
    func panel(for id: ModuleID) -> AnyView {
        index[id]?.makePanel()
            ?? AnyView(ModulePlaceholder(module: id, detail: "This module isn't available in this build"))
    }

    /// Ids of the modules currently started.
    var running: [ModuleID] { lifecycle.running }

    /// Starts newly enabled modules and stops disabled ones. Ids with no
    /// registered module are ignored.
    func update(enabled: [ModuleID]) {
        apply(lifecycle.update(enabled: enabled.filter { index[$0] != nil }))
    }

    /// Stops every running module, e.g. when the app quits.
    func stopAll() {
        apply(lifecycle.stopAll())
    }

    private func apply(_ changes: ModuleLifecycle.Changes) {
        for id in changes.stop { index[id]?.stop() }
        for id in changes.start { index[id]?.start() }
    }
}
