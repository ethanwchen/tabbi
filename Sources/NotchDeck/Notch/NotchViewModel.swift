import SwiftUI
import NotchDeckCore

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
            let all = ModuleID.allCases
            movingForward = all.firstIndex(of: selected)! >= all.firstIndex(of: oldValue)!
        }
    }
    @Published private(set) var movingForward = true
    @Published var geometry: NotchGeometry
    /// Whether a module currently shows a compact live activity beside the
    /// closed notch (set by AppServices).
    @Published var hasCompactActivity = false
    /// While true the notch stays open even when the pointer leaves
    /// (e.g. the user is typing a question).
    @Published var isPinned = false

    private static let selectedKey = "selectedModule"

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        let saved = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(ModuleID.init(rawValue:))
        self.selected = saved ?? .spotify
    }

    var isOpen: Bool { phase == .open }

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
        notch.width + (hasCompactActivity ? Theme.Layout.compactWingWidth * 2 : 0)
    }

    func open(_ module: ModuleID? = nil) {
        if let module { selected = module }
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

    func toggle() {
        isOpen ? close() : open()
    }

    func selectNext() { selected = selected.next }
    func selectPrevious() { selected = selected.previous }
}
