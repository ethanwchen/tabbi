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
/// A tab bounces when `celebrations` nods for its module, and wears a
/// small count while `badges` has one for it (Party's friend requests);
/// the "more" button wears a dot while a hidden tab has one. Reads
/// `NotchViewModel` from the environment.
public struct NotchTabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection
    /// Bounces per tab since this bar appeared; a tab's symbol bounces each time its count grows.
    @State private var bounces: [ModuleID: Int] = [:]
    @State private var counts: [ModuleID: Int] = [:]
    private let header: NotchHeaderLayout
    private let celebrations: CelebrationCenter?
    private let badges: AnyPublisher<[ModuleID: Int], Never>?

    public init(header: NotchHeaderLayout, celebrations: CelebrationCenter? = nil,
                badges: AnyPublisher<[ModuleID: Int], Never>? = nil) {
        self.header = header
        self.celebrations = celebrations
        self.badges = badges
    }

    public var body: some View {
        let tabs = model.layout.tabs
        let visible = tabs.prefix(header.visibleTabCount)
        HStack(spacing: header.tabSpacing) {
            ForEach(visible, id: \.self) { module in
                TabButton(module: module, shortcut: model.layout.shortcut(for: module), width: header.tabWidth,
                          isSelected: model.selected == module, bounces: bounces[module, default: 0],
                          badge: counts[module, default: 0], namespace: selection) {
                    model.selected = module
                }
            }
            if header.hasOverflow {
                MoreTabsButton(selected: header.overflowSelection(in: tabs, selected: model.selected),
                               isOpen: model.showsMoreTabs,
                               hasBadge: header.overflowTabs(tabs).contains { counts[$0, default: 0] > 0 },
                               namespace: selection) {
                    model.showsMoreTabs.toggle()
                }
            }
        }
        .onReceive(badges ?? Empty().eraseToAnyPublisher()) { counts = $0 }
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
    /// A hidden tab has a badge.
    var hasBadge = false
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
                .overlay(alignment: .topTrailing) {
                    if hasBadge {
                        Circle()
                            .fill(Theme.Palette.primaryText)
                            .frame(width: 5, height: 5)
                            .offset(x: -2, y: 3)
                    }
                }
        }
        .buttonStyle(.tactile)
        .help(Text("More tabs", bundle: .tabbi))
        .accessibilityLabel(Text("More tabs", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: isOpen)
    }
}

/// The tabs that didn't fit in the header, listed under the "more" button
/// with their number keys. Picking one opens it, which closes the list.
public struct NotchMoreTabsMenu: View {
    @EnvironmentObject private var model: NotchViewModel
    @State private var counts: [ModuleID: Int] = [:]
    private let header: NotchHeaderLayout
    private let badges: AnyPublisher<[ModuleID: Int], Never>?

    public init(header: NotchHeaderLayout, badges: AnyPublisher<[ModuleID: Int], Never>? = nil) {
        self.header = header
        self.badges = badges
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(header.overflowTabs(model.layout.tabs), id: \.self) { module in
                MoreTabRow(module: module, shortcut: model.layout.shortcut(for: module),
                           isSelected: model.selected == module, badge: counts[module, default: 0]) {
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
        .onReceive(badges ?? Empty().eraseToAnyPublisher()) { counts = $0 }
    }
}

private struct MoreTabRow: View {
    let module: ModuleID
    let shortcut: Int?
    let isSelected: Bool
    var badge = 0
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
                if badge > 0 { TabBadge(count: badge, tint: descriptor.accentColor) }
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
    /// The count the tab wears (`ModuleProvision.badge`); 0 shows none.
    let badge: Int
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
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        TabBadge(count: badge, tint: descriptor.accentColor)
                            .offset(x: 1, y: -3)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.tactile)
        .motion(Theme.Motion.snappy, value: badge)
        .help(shortcut.map { "\(descriptor.title) (\($0))" } ?? descriptor.title)
        // The tab shows only its symbol, so name it (and its count) for VoiceOver.
        .accessibilityLabel(descriptor.title)
        .accessibilityValue(badge > 0 ? Text("Waiting: \(badge)", bundle: .tabbi) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
}

/// A tab's count: a small capsule in the module's accent, "9+" past nine.
private struct TabBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.Palette.onAccent)
            .padding(.horizontal, 3)
            .frame(minWidth: 12, minHeight: 12)
            .background(Capsule().fill(tint))
            .overlay(Capsule().strokeBorder(Theme.Palette.background, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
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
