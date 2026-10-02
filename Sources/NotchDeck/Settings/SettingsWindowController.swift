import AppKit
import SwiftUI

/// The Settings window: a native toolbar-tabbed preferences window. This is
/// the one place in NotchDeck where system chrome and the light/dark system
/// appearance are correct, so it deliberately does not use the notch theme.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The panes, in toolbar order.
    enum Pane: String, CaseIterable {
        case general, modules, shortcuts, about

        var title: String {
            switch self {
            case .general: "General"
            case .modules: "Modules"
            case .shortcuts: "Shortcuts"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .modules: "square.grid.2x2"
            case .shortcuts: "keyboard"
            case .about: "info.circle"
            }
        }
    }

    private let tabs = NSTabViewController()

    init(settings: SettingsStore) {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in Pane.allCases {
            let host = NSHostingController(rootView: Self.view(for: pane).environmentObject(settings))
            // The window follows each pane's natural size as the user switches tabs.
            host.sizingOptions = .preferredContentSize
            // The tab view controller shows the selected child's title in the title bar.
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NotchDeckSettings")
        super.init(window: window)
        select(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func select(_ pane: Pane) {
        tabs.selectedTabViewItemIndex = Pane.allCases.firstIndex(of: pane) ?? 0
        window?.title = pane.title
    }

    /// Brings the window forward. NotchDeck is an accessory app, so it must
    /// activate itself or the window would open behind the frontmost app.
    func present() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Renders the window, title bar and toolbar included, to PNG data for
    /// `SnapshotRenderer`. Works off screen without Screen Recording permission.
    func snapshot(of pane: Pane) async -> Data? {
        tabs.transitionOptions = []
        select(pane)
        guard let window else { return nil }
        // The selected toolbar item is a glass layer composited by the window
        // server, which `cacheDisplay` draws as an opaque white box; the title
        // still names the pane.
        window.toolbar?.selectedItemIdentifier = nil
        // Let SwiftUI lay out the new pane and the window adopt its size.
        try? await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        // The theme frame (the content view's superview) draws the chrome.
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @ViewBuilder
    private static func view(for pane: Pane) -> some View {
        switch pane {
        case .general: GeneralSettingsPane()
        case .modules: ModulesSettingsPane()
        case .shortcuts: ShortcutsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}
