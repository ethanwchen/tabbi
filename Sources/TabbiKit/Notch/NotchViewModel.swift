import SwiftUI
import TabbiKitCore

/// State of the notch: closed, hovered, or open on a module, plus tab
/// selection and navigation. Shared so any notch app built on TabbiKit gets
/// the same open/close, 1-9 / arrow-key and header letter-key behavior.
@MainActor
public final class NotchViewModel: ObservableObject {
    public enum Phase: Equatable {
        case closed
        case hovering
        case open
    }

    @Published public private(set) var phase: Phase = .closed
    @Published public var selected: ModuleID {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.selectedKey)
            showsMoreTabs = false
            if selected != oldValue {
                openedFromKeyboard = false
                requestedOpenSize = nil
            }
            // Direction drives the slide transition between modules, in the
            // header's visual order: the tabs, then the shortcuts at the far right.
            let order = layout.tabs + layout.headerShortcuts
            movingForward = (order.firstIndex(of: selected) ?? 0) >= (order.firstIndex(of: oldValue) ?? 0)
        }
    }
    /// The user's tab order and enabled modules. When the selected module gets
    /// disabled, selection moves to the first enabled one.
    @Published public var layout: ModuleLayout {
        didSet {
            let resolved = layout.resolvedSelection(selected)
            if resolved != selected { selected = resolved }
            showsMoreTabs = false
        }
    }
    @Published public private(set) var movingForward = true
    /// Whether the list of tabs that didn't fit in the header is showing.
    /// Picking a tab, changing the tabs or closing the notch hides it.
    @Published public var showsMoreTabs = false
    @Published public var geometry: NotchGeometry
    /// The live preview beside the closed notch, nil for a plain black notch
    /// (fed from `TickerStore`).
    @Published public var preview: TickerItem?
    /// While true the notch stays open even when the pointer leaves
    /// (e.g. the user is typing a question).
    @Published public var isPinned = false
    /// The active theme's id. `NotchView` re-keys the open panel by it, so a
    /// theme switch redraws every view with the new `Theme` tokens.
    @Published public var themeID: ThemeID = Theme.current.id
    /// The user's notch mode and global shortcut (mirrored from settings),
    /// so the right-click menu checks the current mode and names the
    /// shortcut that brings a hidden notch back.
    @Published public var notchMode: NotchMode = .default
    @Published public var hotkey: Hotkey = .default
    /// True while the app's takeover (first-run onboarding) fills the open
    /// notch in place of the tabs; tab keys and swipes do nothing meanwhile.
    @Published public var showsTakeover = false {
        didSet {
            guard showsTakeover != oldValue else { return }
            isPinned = showsTakeover
            requestedOpenSize = nil
            if showsTakeover { phase = .open }
        }
    }

    /// True when the global shortcut opened the notch, so the open tab can
    /// put the caret in its main field (Today's "Add a task") and the user can
    /// type right away. Opening by pointer leaves focus alone, since a focused
    /// field pins the notch open after the pointer leaves. Switching tabs
    /// clears it, so only the tab the shortcut opened on takes the caret, and
    /// that tab takes it once through `consumeKeyboardOpen()`.
    @Published public private(set) var openedFromKeyboard = false

    /// A larger open canvas the selected tab asked for (Ask Claude's large
    /// chat view), or nil for the usual `Theme.Layout.expandedSize`. It
    /// lasts until the tab gives it back, Esc, another tab or closing.
    @Published public private(set) var requestedOpenSize: CGSize?

    private static let selectedKey = "selectedModule"

    /// Room kept free beside and below a larger open canvas, so it never
    /// fills the screen.
    private static let screenMargin = CGSize(width: 48, height: 96)

    public init(geometry: NotchGeometry, layout: ModuleLayout) {
        self.geometry = geometry
        self.layout = layout
        let saved = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(ModuleID.init(rawValue:))
        self.selected = layout.resolvedSelection(saved ?? layout.enabled[0])
    }

    public var isOpen: Bool { phase == .open }

    /// True while the open notch shows the larger canvas a tab asked for.
    public var isEnlarged: Bool { requestedOpenSize != nil }

    /// The open notch's size: the usual canvas, or the larger one the
    /// selected tab asked for, fitted to the screen and never smaller than
    /// the usual one. It stays centered under the notch, so the header
    /// keeps clear of the camera at either size.
    public var openSize: CGSize {
        let base = Theme.Layout.expandedSize
        guard let requested = requestedOpenSize else { return base }
        let screen = geometry.screenFrame.size
        let fit = CGSize(width: screen.width - Self.screenMargin.width * 2,
                         height: screen.height - Self.screenMargin.height)
        return CGSize(width: max(base.width, min(requested.width, fit.width)),
                      height: max(base.height, min(requested.height, fit.height)))
    }

    /// Asks for a larger open canvas, or gives it back with nil. Only the
    /// open notch grows; a request while it's closed is ignored.
    public func requestOpenSize(_ size: CGSize?) {
        guard size == nil || (isOpen && !showsTakeover) else { return }
        requestedOpenSize = size
    }

    /// Changes only when the preview switches kind, so the notch animates its
    /// width on rotation but not on every countdown tick.
    public var previewKind: TickerKind? { preview?.kind }

    /// The visible size of the notch shape for the current phase.
    public var size: CGSize {
        let notch = geometry.notchSize
        let flare = topRadius * 2
        switch phase {
        case .open:
            return openSize
        case .hovering:
            let base = closedWidth(notch)
            return CGSize(width: base + Theme.Layout.hoverGrowth.width + flare,
                          height: notch.height + Theme.Layout.hoverGrowth.height)
        case .closed:
            return CGSize(width: closedWidth(notch) + flare, height: notch.height)
        }
    }

    public var topRadius: CGFloat {
        isOpen ? Theme.Layout.openTopRadius : Theme.Layout.closedTopRadius
    }

    public var bottomRadius: CGFloat {
        isOpen ? Theme.Layout.openBottomRadius : Theme.Layout.closedBottomRadius
    }

    private func closedWidth(_ notch: CGSize) -> CGFloat {
        notch.width + (preview.map { NotchPreviewLayout.wingWidth(for: $0) * 2 } ?? 0)
    }

    public func open(_ module: ModuleID? = nil, fromKeyboard: Bool = false) {
        if let module { selected = layout.resolvedSelection(module) }
        openedFromKeyboard = fromKeyboard
        // A takeover waits for the user, not the pointer.
        if showsTakeover { isPinned = true }
        phase = .open
    }

    /// True once after the global shortcut opened the notch, then false, so
    /// a tab's view that appears again later (back from Settings, the large
    /// chat view or a takeover) doesn't grab the caret a second time.
    public func consumeKeyboardOpen() -> Bool {
        guard openedFromKeyboard else { return false }
        openedFromKeyboard = false
        return true
    }

    public func close() {
        isPinned = false
        openedFromKeyboard = false
        requestedOpenSize = nil
        showsMoreTabs = false
        phase = .closed
    }

    public func setHovering(_ hovering: Bool) {
        guard phase != .open else { return }
        phase = hovering ? .hovering : .closed
    }

    /// Clicking the closed notch opens the module its preview belongs to,
    /// e.g. Today for a meeting countdown.
    public func openFromClosedClick() {
        open(preview?.module)
    }

    public func toggle(fromKeyboard: Bool = false) {
        isOpen ? close() : open(fromKeyboard: fromKeyboard)
    }

    public func selectNext() {
        guard !showsTakeover else { return }
        selected = layout.module(after: selected)
    }

    public func selectPrevious() {
        guard !showsTakeover else { return }
        selected = layout.module(before: selected)
    }

    /// Jumps to the tab under number key `number` (1-9). Returns false when
    /// there's no such tab, so the key isn't swallowed.
    public func select(shortcut number: Int) -> Bool {
        guard !showsTakeover, let module = layout.module(forShortcut: number) else { return false }
        selected = module
        return true
    }

    /// Opens the header module under letter `key` (P for the pet). Returns
    /// false when no enabled module has that key, so the key isn't swallowed.
    public func select(headerKey key: String) -> Bool {
        guard !showsTakeover, let module = layout.module(forHeaderKey: key) else { return false }
        selected = module
        return true
    }
}
