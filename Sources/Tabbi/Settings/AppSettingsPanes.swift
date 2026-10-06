import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Settings window's five sections, in toolbar order. A module's own
/// settings (Focus, Pet Coach, Party) open from its row in Tabs, so the
/// toolbar stays the same whichever tabs are on.
enum AppSettingsPane: String, CaseIterable {
    case general, tabs, look, connections, about

    var title: String {
        switch self {
        case .general: "General"
        case .tabs: "Tabs"
        case .look: "Look"
        case .connections: "Connections"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.grid.2x2"
        case .look: "paintpalette"
        case .connections: "link"
        case .about: "info.circle"
        }
    }

    @MainActor
    func view(moduleOptions: @escaping ModuleOptions) -> AnyView {
        switch self {
        case .general: AnyView(GeneralSettingsPane())
        case .tabs: AnyView(ModulesSettingsPane(moduleOptions: moduleOptions))
        case .look: AnyView(AppearanceSettingsPane())
        case .connections: AnyView(ConnectionsSettingsPane())
        case .about: AnyView(AboutSettingsPane())
        }
    }

    /// The window's panes, each reading the settings store from its environment.
    @MainActor
    static func panes(settings: SettingsStore, modules: ModuleRegistry, onboarding: OnboardingStore?) -> [SettingsPane] {
        let environment = PaneEnvironment(settings: settings, modules: modules, onboarding: onboarding)
        let moduleOptions = self.moduleOptions(settings: settings, modules: modules, onboarding: onboarding)
        return allCases.map { pane in
            // Connections checks the Mac when shown; let that finish in snapshots.
            environment.wrap(SettingsPane(id: pane.rawValue, title: pane.title, symbol: pane.symbol,
                                          view: pane.view(moduleOptions: moduleOptions),
                                          settleTime: pane == .connections ? .seconds(2) : .milliseconds(300)))
        }
    }

    /// Looks up a module's own settings, made fresh each time so they always
    /// follow the module's current state.
    @MainActor
    static func moduleOptions(settings: SettingsStore, modules: ModuleRegistry, onboarding: OnboardingStore?) -> ModuleOptions {
        let environment = PaneEnvironment(settings: settings, modules: modules, onboarding: onboarding)
        return { id in modules[id]?.makeSettingsPane().map(environment.wrap) }
    }
}

/// A module's own settings by id, or nil when it has none.
typealias ModuleOptions = @MainActor (ModuleID) -> SettingsPane?

/// What every Settings pane reads from its environment.
@MainActor
private struct PaneEnvironment {
    let settings: SettingsStore
    let modules: ModuleRegistry
    let onboarding: OnboardingStore?

    func wrap(_ pane: SettingsPane) -> SettingsPane {
        let modules = modules
        let onboarding = onboarding
        return SettingsPane(id: pane.id, title: pane.title, symbol: pane.symbol,
                            view: AnyView(pane.view.environmentObject(settings)
                                            .environment(\.moduleCatalog, settings.catalog)
                                            .environment(\.modulesUseKitDefaults, { modules.usesKitDefaults(of: $0) })
                                            .environment(\.runSetup, onboarding.map { store in { @MainActor @Sendable in store.start() } })),
                            settleTime: pane.settleTime)
    }
}

private struct ModulesUseKitDefaultsKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (KitManifest) -> AnyPublisher<Bool, Never> = { _ in
        Just(true).eraseToAnyPublisher()
    }
}

extension EnvironmentValues {
    /// Whether the modules' kit-derived state (`NotchModule.usesKitDefaults`)
    /// matches a kit, so the Kit section in Settings can tell if Reset to
    /// Kit Defaults has work to do without knowing any module.
    var modulesUseKitDefaults: @MainActor @Sendable (KitManifest) -> AnyPublisher<Bool, Never> {
        get { self[ModulesUseKitDefaultsKey.self] }
        set { self[ModulesUseKitDefaultsKey.self] = newValue }
    }

    /// Starts first-run setup again in the notch; nil where there is no
    /// notch to run it in (snapshots).
    var runSetup: (@MainActor @Sendable () -> Void)? {
        get { self[RunSetupKey.self] }
        set { self[RunSetupKey.self] = newValue }
    }
}

private struct RunSetupKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}

extension SettingsWindowController {
    /// The app's Settings window.
    /// - Parameter onboarding: offers Run Setup Again in Tabs.
    convenience init(settings: SettingsStore, modules: ModuleRegistry, onboarding: OnboardingStore? = nil) {
        self.init(
            panes: AppSettingsPane.panes(settings: settings, modules: modules, onboarding: onboarding),
            updates: Empty().eraseToAnyPublisher(),
            autosaveName: "TabbiSettings"
        )
    }
}
