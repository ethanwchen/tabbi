import SwiftUI
import TabbiKitCore

/// The compact tab bar left of the notch: one small icon per enabled module
/// with a sliding accent pill behind the selected one, and the number key
/// that jumps to it in the tooltip. Reads `NotchViewModel` from the environment.
public struct NotchTabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection

    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(model.layout.enabled) { module in
                TabButton(module: module, shortcut: model.layout.shortcut(for: module),
                          isSelected: model.selected == module, namespace: selection) {
                    model.selected = module
                }
            }
        }
        .animation(Theme.Motion.snappy, value: model.selected)
        .animation(Theme.Motion.snappy, value: model.layout)
    }
}

private struct TabButton: View {
    let module: ModuleID
    /// Number key that jumps here, shown in the tooltip.
    let shortcut: Int?
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        let descriptor = catalog.descriptor(for: module)
        Button(action: action) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? descriptor.accentColor
                                 : (hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText))
                .frame(width: 28, height: 24)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(descriptor.accentColor.opacity(0.16))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.tactile)
        .help(shortcut.map { "\(descriptor.title) (\($0))" } ?? descriptor.title)
        .onHover { hovering = $0 }
    }
}
