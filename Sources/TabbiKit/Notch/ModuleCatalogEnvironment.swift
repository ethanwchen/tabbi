import SwiftUI
import TabbiKitCore

private struct ModuleCatalogKey: EnvironmentKey {
    static let defaultValue = ModuleCatalog([])
}

private struct ModuleActionKey: EnvironmentKey {
    static let defaultValue = ModuleActionRunner { _, _ in }
}

/// Runs a `ProvidedAction` that a module offered on something it shared,
/// by handing it back to that module. A struct around the closure so the
/// environment value can be called like a function.
public struct ModuleActionRunner: Sendable {
    private let run: @MainActor @Sendable (ModuleID, ProvidedAction) -> Void

    public init(_ run: @escaping @MainActor @Sendable (ModuleID, ProvidedAction) -> Void) {
        self.run = run
    }

    @MainActor
    public func callAsFunction(_ action: ProvidedAction, from module: ModuleID) {
        run(module, action)
    }
}

public extension EnvironmentValues {
    /// Runs a shared item's action in the module that offered it, such as
    /// Anki's "Study Pharm Sketchy" from Today's Anki row. Does nothing
    /// outside the notch.
    var runModuleAction: ModuleActionRunner {
        get { self[ModuleActionKey.self] }
        set { self[ModuleActionKey.self] = newValue }
    }

    /// The modules this build has, from the app's module registry. Shared
    /// views (tab bar, previews, placeholders, Settings) look up a module's
    /// title, symbol and accent here, so no view needs a hardcoded list.
    /// Unknown ids resolve to a neutral placeholder descriptor.
    var moduleCatalog: ModuleCatalog {
        get { self[ModuleCatalogKey.self] }
        set { self[ModuleCatalogKey.self] = newValue }
    }
}
