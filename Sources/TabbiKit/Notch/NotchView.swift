import SwiftUI
import TabbiKitCore

/// Root view: the black notch shape, morphing between closed and open, with
/// the tab bar and the selected module inside. Reads `NotchViewModel` from
/// the environment; the app supplies its panels through `content`.
public struct NotchView: View {
    @EnvironmentObject private var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: NotchContent

    public init(content: NotchContent) {
        self.content = content
    }

    public var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        ZStack(alignment: .top) {
            // No shadow: the clip below would hide it anyway, and a blur on
            // a shape that morphs every frame costs GPU time for nothing.
            shape.fill(Theme.Palette.background)

            if model.isOpen {
                ThemeGlow()
                    .id(model.themeID)
                    .transition(.opacity)
                OpenNotchContent(content: content)
                    .id(model.themeID)
                    .transition(.notchContent(reduceMotion: reduceMotion))
            } else if let preview = model.preview {
                NotchPreview(item: preview, notchWidth: model.geometry.notchSize.width, content: content)
                    .id(model.themeID)
                    .frame(height: model.geometry.notchSize.height)
            }
        }
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            guard !model.isOpen else { return }
            // A preview with a one-click action (Anki's "Study <deck>") runs
            // it, and the panel opens on its module to show how it goes.
            if let preview = model.preview, let action = preview.action {
                content.runAction(action, from: preview.module)
            }
            model.openFromClosedClick()
        }
        .contextMenu {
            ForEach(model.layout.enabled) { module in
                Button(content.catalog.descriptor(for: module).title) { model.open(module) }
            }
            Divider()
            Button("Settings…") {
                model.close()
                content.openSettings()
            }
            if let checkForUpdates = content.checkForUpdates {
                Button("Check for Updates…", action: checkForUpdates)
            }
            Button("Quit \(content.appName)") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(phaseAnimation, value: model.phase)
        .animation(Motion.adapted(Motion.content, reduceMotion: reduceMotion), value: model.previewKind)
        .animation(Motion.adapted(Motion.content, reduceMotion: reduceMotion), value: model.showsTakeover)
        .preferredColorScheme(.dark)
        .environment(\.moduleCatalog, content.catalog)
        .environment(\.runModuleAction, content.runAction)
    }

    /// Opening stretches and settles, closing lands with no overshoot, and
    /// hovering answers quickly; Reduce Motion swaps all three for a short fade.
    private var phaseAnimation: Animation {
        let animation: Animation
        switch model.phase {
        case .open: animation = Motion.open
        case .hovering: animation = Motion.hover
        case .closed: animation = Motion.close
        }
        return Motion.adapted(animation, reduceMotion: reduceMotion)
    }
}

/// The theme's soft color rising from the bottom of the open panel. The top
/// stays black so the panel still meets the hardware notch seamlessly, and
/// the closed notch never shows it.
private struct ThemeGlow: View {
    var body: some View {
        if let glow = Theme.Palette.glow {
            LinearGradient(stops: [.init(color: glow, location: 0), .init(color: glow.opacity(0), location: 0.6)],
                           startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)
        }
    }
}

/// Header (tabs left of the notch; title, Settings and the header shortcuts
/// such as the pet's paw right of it) above the module panel,
/// or the app's takeover (first-run setup) in their place while it runs.
private struct OpenNotchContent: View {
    @EnvironmentObject private var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: NotchContent

    var body: some View {
        if model.showsTakeover, let takeover = content.takeover {
            // The takeover's header keeps to the same camera-safe zones as the tabs.
            let header = NotchHeaderLayout.openNotch(geometry: model.geometry, layout: model.layout, title: "")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    takeover.leading()
                        .frame(width: header.leadingZone.width, alignment: .leading)
                    Color.clear.frame(width: header.trailingZone.minX - header.leadingZone.maxX)
                    takeover.trailing()
                        .frame(width: header.trailingZone.width, alignment: .trailing)
                }
                .padding(.leading, header.leadingZone.minX)
                .frame(width: Theme.Layout.expandedSize.width,
                       height: NotchHeaderLayout.headerHeight(for: model.geometry), alignment: .leading)

                takeover.body()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Layout.contentInset + Theme.Layout.openTopRadius)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.l)
            }
            .transition(.opacity)
        } else {
            tabs()
                .transition(.opacity)
        }
    }

    /// The usual open notch: the tab bar, the tab's title and the panel.
    /// Every header control sits where `NotchHeaderLayout` puts it, clear of
    /// the camera; tabs that don't fit open from the "more" list.
    private func tabs() -> some View {
        let title = content.catalog.descriptor(for: model.selected).title
        let header = NotchHeaderLayout.openNotch(geometry: model.geometry, layout: model.layout, title: title)
        let headerHeight = NotchHeaderLayout.headerHeight(for: model.geometry)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                NotchTabBar(header: header, celebrations: content.celebrations)
                    .frame(width: header.leadingZone.width, alignment: .leading)
                Color.clear.frame(width: header.trailingZone.minX - header.leadingZone.maxX)
                HStack(spacing: NotchHeaderLayout.Metrics().trailingSpacing) {
                    if let titleFrame = header.titleFrame {
                        Text(title)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: titleFrame.width, alignment: .trailing)
                            .contentTransition(.opacity)
                            .help(title)
                    }
                    IconButton(symbol: "gearshape.fill", size: header.gearFrame.width,
                               help: "\(content.appName) Settings") {
                        model.close()
                        content.openSettings()
                    }
                    NotchHeaderShortcuts()
                }
                .frame(width: header.trailingZone.width, alignment: .trailing)
            }
            .padding(.leading, header.leadingZone.minX)
            .frame(width: Theme.Layout.expandedSize.width, height: headerHeight, alignment: .leading)

            ZStack {
                content.panel(model.selected)
                    .id(model.selected)
                    .transition(.tabSwitch(forward: model.movingForward, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, Theme.Layout.contentInset + Theme.Layout.openTopRadius)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            .motion(Motion.content, value: model.selected)
        }
        .overlay(alignment: .topLeading) {
            if model.showsMoreTabs, let more = header.moreFrame {
                ZStack(alignment: .topLeading) {
                    // A tap anywhere else closes the list without acting.
                    Color.black.opacity(0.001)
                        .onTapGesture { model.showsMoreTabs = false }
                    NotchMoreTabsMenu(header: header)
                        .offset(x: more.minX, y: more.maxY + Theme.Spacing.xs)
                }
                .transition(.opacity)
            }
        }
        .motion(Motion.content, value: model.showsMoreTabs)
    }
}
