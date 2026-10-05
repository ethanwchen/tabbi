import Combine
import SwiftUI
import TabbiKitCore

/// The compact tab bar left of the notch: one small icon per enabled module
/// with a sliding accent pill behind the selected one, and the number key
/// that jumps to it in the tooltip. A tab bounces when `celebrations` nods
/// for its module. Reads `NotchViewModel` from the environment.
public struct NotchTabBar: View {
    @EnvironmentObject private var model: NotchViewModel
    @Namespace private var selection
    /// Bounces per tab since this bar appeared; a tab's symbol bounces each time its count grows.
    @State private var bounces: [ModuleID: Int] = [:]
    private let celebrations: CelebrationCenter?

    public init(celebrations: CelebrationCenter? = nil) {
        self.celebrations = celebrations
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(model.layout.enabled) { module in
                TabButton(module: module, shortcut: model.layout.shortcut(for: module),
                          isSelected: model.selected == module, bounces: bounces[module, default: 0],
                          namespace: selection) {
                    model.selected = module
                }
            }
        }
        .animation(Theme.Motion.snappy, value: model.selected)
        .animation(Theme.Motion.snappy, value: model.layout)
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

private struct TabButton: View {
    let module: ModuleID
    /// Number key that jumps here, shown in the tooltip.
    let shortcut: Int?
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
