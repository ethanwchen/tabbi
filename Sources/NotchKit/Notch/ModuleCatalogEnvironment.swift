import SwiftUI
import NotchKitCore

private struct ModuleCatalogKey: EnvironmentKey {
    static let defaultValue = ModuleCatalog([])
}

public extension EnvironmentValues {
    /// The modules this build has, from the app's module registry. Shared
    /// views (tab bar, previews, placeholders, Settings) look up a module's
    /// title, symbol and accent here, so no view needs a hardcoded list.
    /// Unknown ids resolve to a neutral placeholder descriptor.
    var moduleCatalog: ModuleCatalog {
        get { self[ModuleCatalogKey.self] }
        set { self[ModuleCatalogKey.self] = newValue }
    }
}
