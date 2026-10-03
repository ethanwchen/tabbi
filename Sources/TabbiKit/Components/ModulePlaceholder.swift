import SwiftUI
import TabbiKitCore

/// Temporary content for a module that hasn't been built yet.
public struct ModulePlaceholder: View {
    let module: ModuleID
    let detail: String
    @Environment(\.moduleCatalog) private var catalog

    public init(module: ModuleID, detail: String) {
        self.module = module
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: catalog.descriptor(for: module).symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(catalog.descriptor(for: module).accentColor)
            Text(detail)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
