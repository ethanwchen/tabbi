import AppKit
import Combine
import SwiftUI
import TabbiKitCore

/// The compact tab bar left of the notch: one small icon per enabled module
/// with a sliding accent pill behind the selected one, and the number key
/// that jumps to it in the tooltip. Modules opened from the header instead
/// (`NotchHeaderShortcuts`) are left out. Sizes and how many tabs show come
/// from `header`, so no tab ever reaches under the camera; the rest sit
/// behind a "more" button that toggles `NotchViewModel.showsMoreTabs`
/// (`NotchMoreTabsMenu`).
/// A tab bounces when `celebrations` nods for its module. Reads
/// `NotchViewModel` from the environment.
public struct NotchTabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection
    /// Bounces per tab since this bar appeared; a tab's symbol bounces each time its count grows.
    @State private var bounces: [ModuleID: Int] = [:]
    private let header: NotchHeaderLayout
    private let celebrations: CelebrationCenter?

    public init(header: NotchHeaderLayout, celebrations: CelebrationCenter? = nil) {
        self.header = header
        self.celebrations = celebrations
    }

    public var body: some View {
        let tabs = model.layout.tabs
        let visible = tabs.prefix(header.visibleTabCount)
        HStack(spacing: header.tabSpacing) {
            ForEach(visible, id: \.self) { module in
                TabButton(module: module, shortcut: model.layout.shortcut(for: module), width: header.tabWidth,
                          isSelected: model.selected == module, bounces: bounces[module, default: 0],
                          namespace: selection) {
                    model.selected = module
                }
            }
            if header.hasOverflow {
                let hidden = Array(tabs.dropFirst(header.visibleTabCount))
                MoreTabsButton(selected: hidden.contains(model.selected) ? model.selected : nil,
                               isOpen: model.showsMoreTabs, namespace: selection) {
                    model.showsMoreTabs.toggle()
                }
            }
        }
        .motion(Theme.Motion.snappy, value: model.selected)
        .motion(Theme.Motion.snappy, value: model.layout)
        .onReceive(nods) { nod in
            guard let nod else { return }
            bounces[nod.tab(enabled: model.layout.enabled, selected: model.selected), default: 0] += 1
        }
    }

    /// Nods made while this bar is on screen; the current one at appear is skipped.
    private var nods: AnyPublisher<CelebrationNod?, Never> {
        celebrations?.$nod.dropFirst().eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }
}

/// The last button of a tab bar that overflows. It wears the selection pill,
/// in the open tab's accent, while that tab is one of the hidden ones.
private struct MoreTabsButton: View {
    /// The hidden tab that is open, if any.
    let selected: ModuleID?
    let isOpen: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        let accent = selected.map { catalog.descriptor(for: $0).accentColor }
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .foregroundStyle(accent ?? (hovering || isOpen ? Theme.Palette.primaryText : Theme.Palette.tertiaryText))
                .frame(width: NotchHeaderLayout.Metrics().moreWidth, height: 24)
                .background {
                    if let accent {
                        Color.clear
                            .controlBackground(Capsule(), tint: accent.opacity(0.16))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.tactile)
        .help("More tabs")
        .accessibilityLabel("More tabs")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: isOpen)
    }
}

/// The tabs that didn't fit in the header, listed under the "more" button
/// with their number keys. Picking one opens it, which closes the list.
public struct NotchMoreTabsMenu: View {
    @EnvironmentObject private var model: NotchViewModel
    private let header: NotchHeaderLayout

    public init(header: NotchHeaderLayout) {
        self.header = header
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(model.layout.tabs.dropFirst(header.visibleTabCount), id: \.self) { module in
                MoreTabRow(module: module, shortcut: model.layout.shortcut(for: module),
                           isSelected: model.selected == module) {
                    model.selected = module
                    model.showsMoreTabs = false
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frame(width: 168)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.Palette.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.Palette.surface)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(Theme.Palette.stroke, lineWidth: 0.5)
        )
    }
}

private struct MoreTabRow: View {
    let module: ModuleID
    let shortcut: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.moduleCatalog) private var catalog

    var body: some View {
        let descriptor = catalog.descriptor(for: module)
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: descriptor.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected || hovering ? descriptor.accentColor : Theme.Palette.secondaryText)
                    .frame(width: 16)
                Text(descriptor.title)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(isSelected || hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Spacing.xs)
                if let shortcut {
                    Text("\(shortcut)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(isSelected ? descriptor.accentColor.opacity(0.16)
                          : (hovering ? Theme.Palette.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(descriptor.title) (\($0))" } ?? descriptor.title)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

private struct TabButton: View {
    let module: ModuleID
    /// Number key that jumps here, shown in the tooltip.
    let shortcut: Int?
    let width: CGFloat
    let isSelected: Bool
    /// Grows by one for each celebration nod aimed at this tab.
    let bounces: Int
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.moduleCatalog) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let descriptor = catalog.descriptor(for: module)
        Button(action: action) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : bounces)
                .symbolEffect(.pulse, options: .nonRepeating, value: reduceMotion ? bounces : 0)
                .foregroundStyle(isSelected ? descriptor.accentColor
                                 : (hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText))
                .frame(width: width, height: 24)
                .background {
                    if isSelected {
                        Color.clear
                            .controlBackground(Capsule(), tint: descriptor.accentColor.opacity(0.16))
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
        .motion(Theme.Motion.snappy, value: model.selected)
    }
}

/// One header shortcut, sized like a tab so it lines up with the tab row: a
/// control surface like the Settings button that takes the module's accent
/// while its page is open, the same press feedback as the tabs and the gear,
/// and a small wiggle on hover (skipped with Reduce Motion).
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
                .frame(width: NotchHeaderLayout.Metrics().shortcutWidth,
                       height: NotchHeaderLayout.Metrics().controlHeight)
                .controlBackground(Capsule(), hovering: hovering,
                                   tint: isSelected ? descriptor.accentColor.opacity(0.16) : nil)
                .contentShape(Capsule())
        }
        .buttonStyle(.tactile)
        .help(key.map { "\(label) (\($0.uppercased()))" } ?? label)
        .accessibilityLabel(label)
        .onHover { inside in
            hovering = inside
            if inside && !reduceMotion { wiggles += 1 }
        }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

public extension NotchHeaderLayout {
    /// The header of the open notch on `geometry` showing `layout`, with
    /// `title` measured in the active theme's title type, across an open
    /// notch `canvasWidth` wide. A display without a notch reserves no cutout.
    @MainActor
    static func openNotch(geometry: NotchGeometry, layout: ModuleLayout, title: String,
                          canvasWidth: CGFloat = Theme.Layout.expandedSize.width) -> NotchHeaderLayout {
        NotchHeaderLayout(canvasWidth: canvasWidth,
                          notchSize: geometry.hasHardwareNotch ? geometry.notchSize : nil,
                          headerHeight: headerHeight(for: geometry),
                          tabCount: layout.tabs.count, shortcutCount: layout.headerShortcuts.count,
                          titleWidth: titleWidth(title))
    }

    /// Height of the open notch's header row: the notch's own height, and
    /// at least a comfortable row on short menu bars.
    @MainActor
    static func headerHeight(for geometry: NotchGeometry) -> CGFloat {
        max(geometry.notchSize.height, 32)
    }

    /// `Theme.Typography.title` as AppKit measures it.
    @MainActor
    private static func titleWidth(_ title: String) -> CGFloat {
        let base = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let descriptor = Theme.current.typeface == .rounded
            ? base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor : base.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: 13) ?? base
        return (title as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }
}
