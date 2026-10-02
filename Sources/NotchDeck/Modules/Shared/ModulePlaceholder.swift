import SwiftUI
import NotchDeckCore

/// Temporary content for a module that hasn't been built yet.
struct ModulePlaceholder: View {
    let module: ModuleID
    let detail: String

    var body: some View {
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
