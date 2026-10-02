import SwiftUI
import NotchKitCore

/// Temporary content for a module that hasn't been built yet.
public struct ModulePlaceholder: View {
    let module: ModuleID
    let detail: String

    public init(module: ModuleID, detail: String) {
        self.module = module
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: module.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent(for: module))
            Text(detail)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
