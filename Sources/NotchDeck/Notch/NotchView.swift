import SwiftUI
import NotchDeckCore

/// Root view: the black notch shape, morphing between closed and open, with
/// the tab bar and the selected module inside.
struct NotchView: View {
    @EnvironmentObject private var model: NotchViewModel
    @EnvironmentObject private var services: AppServices

    var body: some View {
        let shape = NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
        ZStack(alignment: .top) {
            shape
                .fill(Theme.Palette.background)
                .shadow(color: .black.opacity(model.isOpen ? 0.45 : 0), radius: 18, y: 8)

            if model.isOpen {
                OpenNotchContent()
                    .transition(AnyTransition.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if let preview = model.preview {
                NotchPreview(item: preview, notchWidth: model.geometry.notchSize.width)
                    .frame(height: model.geometry.notchSize.height)
            }
        }
        .frame(width: model.size.width, height: model.size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if !model.isOpen { model.openFromClosedClick() } }
        .contextMenu {
            ForEach(model.layout.enabled) { module in
                Button(module.title) { model.open(module) }
            }
            Divider()
            Button("Settings…") {
                model.close()
                services.openSettings()
            }
            Button("Quit NotchDeck") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.Motion.notch, value: model.phase)
        .animation(Theme.Motion.notch, value: model.previewKind)
        .preferredColorScheme(.dark)
    }
}

/// Header (tabs left of the notch, title right of it) above the module panel.
private struct OpenNotchContent: View {
    @EnvironmentObject private var model: NotchViewModel
    @EnvironmentObject private var services: AppServices

    var body: some View {
        let notch = model.geometry.notchSize
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBar()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notch.width)
                HStack(spacing: Theme.Spacing.s) {
                    Text(model.selected.title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    IconButton(symbol: "gearshape.fill", size: 22, help: "NotchDeck Settings") {
                        model.close()
                        services.openSettings()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Layout.openTopRadius + Theme.Layout.contentInset)
            .frame(height: max(notch.height, 32))

            ZStack {
                ModuleViews.panel(for: model.selected, services: services)
                    .id(model.selected)
                    .transition(.asymmetric(
                        insertion: .move(edge: model.movingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: model.movingForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.horizontal, Theme.Layout.contentInset + Theme.Layout.openTopRadius)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            .animation(Theme.Motion.content, value: model.selected)
        }
    }
}

private struct TabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(model.layout.enabled) { module in
                TabButton(module: module, isSelected: model.selected == module, namespace: selection) {
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
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: module.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.Palette.accent(for: module)
                                 : (hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText))
                .frame(width: 28, height: 24)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.Palette.accent(for: module).opacity(0.16))
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(module.title)
        .onHover { hovering = $0 }
    }
}
