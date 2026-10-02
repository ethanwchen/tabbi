import SwiftUI
import NotchKitCore

/// State of the notch: closed, hovered, or open on a module.
@MainActor
final class NotchViewModel: ObservableObject {
    enum Phase: Equatable {
        case closed
        case hovering
        case open
    }

    @Published private(set) var phase: Phase = .closed
    @Published var selected: ModuleID {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.selectedKey)
            // Direction drives the slide transition between modules.
            let order = layout.order
            movingForward = (order.firstIndex(of: selected) ?? 0) >= (order.firstIndex(of: oldValue) ?? 0)
        }
    }
    /// The user's tab order and enabled modules. When the selected module gets
    /// disabled, selection moves to the first enabled one.
    @Published var layout: ModuleLayout {
        didSet {
            let resolved = layout.resolvedSelection(selected)
            if resolved != selected { selected = resolved }
        }
    }
    @Published private(set) var movingForward = true
    @Published var geometry: NotchGeometry
    /// The live preview beside the closed notch, nil for a plain black notch
    /// (fed from `TickerStore`).
    @Published var preview: TickerItem?
    /// While true the notch stays open even when the pointer leaves
    /// (e.g. the user is typing a question).
    @Published var isPinned = false

    private static let selectedKey = "selectedModule"

    init(geometry: NotchGeometry, layout: ModuleLayout = .default) {
        self.geometry = geometry
        self.layout = layout
        let saved = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(ModuleID.init(rawValue:))
        self.selected = layout.resolvedSelection(saved ?? layout.enabled[0])
    }

    var isOpen: Bool { phase == .open }

    /// Changes only when the preview switches kind, so the notch animates its
    /// width on rotation but not on every countdown tick.
    var previewKind: TickerKind? { preview?.kind }

    /// The visible size of the notch shape for the current phase.
    var size: CGSize {
        let notch = geometry.notchSize
        let flare = topRadius * 2
        switch phase {
        case .open:
            return Theme.Layout.expandedSize
        case .hovering:
            let base = closedWidth(notch)
            return CGSize(width: base + Theme.Layout.hoverGrowth.width + flare,
                          height: notch.height + Theme.Layout.hoverGrowth.height)
        case .closed:
            return CGSize(width: closedWidth(notch) + flare, height: notch.height)
        }
    }

    var topRadius: CGFloat {
        isOpen ? Theme.Layout.openTopRadius : Theme.Layout.closedTopRadius
    }

    var bottomRadius: CGFloat {
        isOpen ? Theme.Layout.openBottomRadius : Theme.Layout.closedBottomRadius
    }

    private func closedWidth(_ notch: CGSize) -> CGFloat {
        notch.width + (preview.map { NotchPreviewLayout.wingWidth(for: $0) * 2 } ?? 0)
    }

    func open(_ module: ModuleID? = nil) {
        if let module { selected = layout.resolvedSelection(module) }
        phase = .open
    }

    func close() {
        isPinned = false
        phase = .closed
    }

    func setHovering(_ hovering: Bool) {
        guard phase != .open else { return }
        phase = hovering ? .hovering : .closed
    }

    /// Clicking the closed notch opens the module its preview belongs to,
    /// e.g. Today for a meeting countdown.
    func openFromClosedClick() {
        open(preview?.kind.module)
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func selectNext() { selected = layout.module(after: selected) }
    func selectPrevious() { selected = layout.module(before: selected) }

    /// Jumps to the tab under number key `number` (1-9). Returns false when
    /// there's no such tab, so the key isn't swallowed.
    func select(shortcut number: Int) -> Bool {
        guard let module = layout.module(forShortcut: number) else { return false }
        selected = module
        return true
    }
}
