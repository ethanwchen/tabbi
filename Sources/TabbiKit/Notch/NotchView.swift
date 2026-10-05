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
                OpenNotchContent(content: content)
                    .transition(.notchContent(reduceMotion: reduceMotion))
            } else if let preview = model.preview {
                NotchPreview(item: preview, notchWidth: model.geometry.notchSize.width, content: content)
                    .frame(height: model.geometry.notchSize.height)
            }
        }
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if !model.isOpen { model.openFromClosedClick() } }
        .contextMenu {
            ForEach(model.layout.enabled) { module in
                Button(content.catalog.descriptor(for: module).title) { model.open(module) }
            }
            Divider()
            Button("Settings…") {
                model.close()
                content.openSettings()
            }
            Button("Quit \(content.appName)") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(phaseAnimation, value: model.phase)
        .animation(Motion.adapted(Motion.content, reduceMotion: reduceMotion), value: model.previewKind)
        .preferredColorScheme(.dark)
        .environment(\.moduleCatalog, content.catalog)
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

/// Header (tabs left of the notch, title right of it) above the module panel.
private struct OpenNotchContent: View {
    @EnvironmentObject private var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: NotchContent

    var body: some View {
        let notch = model.geometry.notchSize
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NotchTabBar()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notch.width)
                HStack(spacing: Theme.Spacing.s) {
                    Text(content.catalog.descriptor(for: model.selected).title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    IconButton(symbol: "gearshape.fill", size: 22, help: "\(content.appName) Settings") {
                        model.close()
                        content.openSettings()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Layout.openTopRadius + Theme.Layout.contentInset)
            .frame(height: max(notch.height, 32))

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
    }
}
