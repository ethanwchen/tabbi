import SwiftUI
import TabbiKitCore

/// The compact tab bar left of the notch: one small icon per enabled module
/// with a sliding accent pill behind the selected one, and the number key
/// that jumps to it in the tooltip. Modules opened from the header instead
/// (`NotchHeaderShortcuts`) are left out. Reads `NotchViewModel` from the environment.
public struct NotchTabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection

    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(model.layout.tabs) { module in
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
                        Color.clear
                            .controlBackground(Capsule(), tint: descriptor.accentColor.opacity(0.16))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(descriptor.title) (\($0))" } ?? descriptor.title)
        .onHover { hovering = $0 }
    }
}

/// The buttons at the far right of the open notch header for modules that
/// open from there instead of a tab (the pet's paw), so the tab bar stays
/// short. Shows nothing when the layout has no such module on.
public struct NotchHeaderShortcuts: View {
    @EnvironmentObject private var model: NotchViewModel

    public init() {}

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(model.layout.headerShortcuts) { module in
                HeaderShortcutButton(module: module, key: model.layout.headerKey(for: module),
                                     isSelected: model.selected == module) {
                    model.selected = module
                }
            }
        }
        .animation(Theme.Motion.snappy, value: model.selected)
    }
}

/// One header shortcut, sized like a tab so it lines up with the tab row: a
/// control surface like the Settings button that takes the module's accent
/// while its page is open, and a small
/// wiggle on hover (skipped with Reduce Motion).
private struct HeaderShortcutButton: View {
    let module: ModuleID
    /// Letter key that opens it, shown in the tooltip.
    let key: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var wiggles = 0
    @Environment(\.moduleCatalog) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let descriptor = catalog.descriptor(for: module)
        let label = descriptor.headerShortcut?.label ?? descriptor.title
        Button(action: action) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected || hovering ? descriptor.accentColor : Theme.Palette.secondaryText)
                .keyframeAnimator(initialValue: 0.0, trigger: wiggles) { content, angle in
                    content.rotationEffect(.degrees(angle))
                } keyframes: { _ in
                    SpringKeyframe(-14, duration: 0.12)
                    SpringKeyframe(10, duration: 0.12)
                    SpringKeyframe(-4, duration: 0.1)
                    SpringKeyframe(0, duration: 0.16)
                }
                .frame(width: 28, height: 24)
                .controlBackground(Capsule(), hovering: hovering,
                                   tint: isSelected ? descriptor.accentColor.opacity(0.16) : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(key.map { "\(label) (\($0.uppercased()))" } ?? label)
        .accessibilityLabel(label)
        .onHover { inside in
            hovering = inside
            if inside && !reduceMotion { wiggles += 1 }
        }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
