import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Settings window's own panes. Enabled modules' panes sit between
/// `leading` and `trailing`.
enum AppSettingsPane: String, CaseIterable {
    case general, appearance, modules, connections, preview, shortcuts, claude, about

    static let leading: [AppSettingsPane] = [.general, .appearance, .modules, .connections, .preview, .shortcuts]
    static let trailing: [AppSettingsPane] = [.claude, .about]

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .modules: "Modules"
        case .connections: "Connections"
        case .preview: "Preview"
        case .shortcuts: "Shortcuts"
        case .claude: "Claude"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .modules: "square.grid.2x2"
        case .connections: "link"
        case .preview: "rectangle.topthird.inset.filled"
        case .shortcuts: "keyboard"
        case .claude: "terminal"
        case .about: "info.circle"
        }
    }

    @MainActor
    var view: AnyView {
        switch self {
        case .general: AnyView(GeneralSettingsPane())
        case .appearance: AnyView(AppearanceSettingsPane())
        case .modules: AnyView(ModulesSettingsPane())
        case .connections: AnyView(ConnectionsSettingsPane())
        case .preview: AnyView(PreviewSettingsPane())
        case .shortcuts: AnyView(ShortcutsSettingsPane())
        case .claude: AnyView(ClaudeSettingsPane())
        case .about: AnyView(AboutSettingsPane())
        }
    }

    /// The toolbar's panes for a layout: the window's own, with the enabled
    /// modules' panes (in canonical module order) in between, each reading
    /// the settings store from its environment. Modules that share a pane
    /// (Today and Focus) return the same id; it shows once, in the first
    /// one's place.
    @MainActor
    static func panes(settings: SettingsStore, modules: ModuleRegistry, onboarding: OnboardingStore?,
                      enabled: [ModuleID]) -> [SettingsPane] {
        let enabled = Set(enabled)
        var seen: Set<String> = []
        let modulePanes = modules.modules
            .filter { enabled.contains($0.id) }
            .compactMap { $0.makeSettingsPane() }
            .filter { seen.insert($0.id).inserted }
        func own(_ panes: [AppSettingsPane]) -> [SettingsPane] {
            panes.map { pane in
                // The Claude and Connections panes check the Mac when shown;
                // let that finish in snapshots.
                SettingsPane(id: pane.rawValue, title: pane.title, symbol: pane.symbol, view: pane.view,
                             settleTime: [.claude, .connections].contains(pane) ? .seconds(2) : .milliseconds(300))
            }
        }
        return (own(leading) + modulePanes + own(trailing)).map { pane in
            SettingsPane(id: pane.id, title: pane.title, symbol: pane.symbol,
                         view: AnyView(pane.view.environmentObject(settings)
                                         .environment(\.moduleCatalog, settings.catalog)
                                         .environment(\.modulesUseKitDefaults, { modules.usesKitDefaults(of: $0) })
                                         .environment(\.runSetup, onboarding.map { store in { @MainActor @Sendable in store.start() } })),
                         settleTime: pane.settleTime)
        }
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
    /// The app's Settings window, following the enabled modules.
    /// - Parameter onboarding: offers Run Setup Again in the Kit section.
    convenience init(settings: SettingsStore, modules: ModuleRegistry, onboarding: OnboardingStore? = nil) {
        // `$settings` emits before the new value is stored, so read the
        // layout from the emission.
        let updates = settings.$settings
            .map(\.modules.enabled)
            .removeDuplicates()
            .dropFirst()
            .map { AppSettingsPane.panes(settings: settings, modules: modules, onboarding: onboarding, enabled: $0) }
            .eraseToAnyPublisher()
        self.init(
            panes: AppSettingsPane.panes(settings: settings, modules: modules, onboarding: onboarding,
                                         enabled: settings.settings.modules.enabled),
            updates: updates,
            autosaveName: "TabbiSettings"
        )
    }
}
