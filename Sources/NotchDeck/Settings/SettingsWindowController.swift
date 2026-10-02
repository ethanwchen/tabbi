import AppKit
import Combine
import SwiftUI
import NotchKitCore

/// The Settings window: a native toolbar-tabbed preferences window. This is
/// the one place in NotchDeck where system chrome and the light/dark system
/// appearance are correct, so it deliberately does not use the notch theme.
///
/// Its own panes frame the panes enabled modules contribute
/// (`NotchModule.makeSettingsPane()`), which come and go with the layout, so
/// Settings only shows what the user's tabs can use.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// The window's own panes. Module panes sit between `leading` and `trailing`.
    enum Pane: String, CaseIterable {
        case general, modules, preview, shortcuts, claude, about

        static let leading: [Pane] = [.general, .modules, .preview, .shortcuts]
        static let trailing: [Pane] = [.claude, .about]

        var title: String {
            switch self {
            case .general: "General"
            case .modules: "Modules"
            case .preview: "Preview"
            case .shortcuts: "Shortcuts"
            case .claude: "Claude"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .modules: "square.grid.2x2"
            case .preview: "rectangle.topthird.inset.filled"
            case .shortcuts: "keyboard"
            case .claude: "terminal"
            case .about: "info.circle"
            }
        }
    }

    /// One toolbar item: a window pane or a module's pane.
    private struct Entry {
        let id: String
        let title: String
        let symbol: String
        let makeView: () -> AnyView
    }

    private let tabs = NSTabViewController()
    private var cancellable: AnyCancellable?

    init(settings: SettingsStore, modules: ModuleRegistry) {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        Self.sync(tabs, to: Self.entries(modules: modules, enabled: settings.settings.modules.enabled), settings: settings)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NotchDeckSettings")
        super.init(window: window)
        select(Pane.general.rawValue)

        // `$settings` emits before the new value is stored, so read the
        // layout from the emission.
        cancellable = settings.$settings
            .map(\.modules.enabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [tabs] enabled in
                Self.sync(tabs, to: Self.entries(modules: modules, enabled: enabled), settings: settings)
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Ids of the panes in toolbar order, module panes included.
    var paneIDs: [String] { tabs.tabViewItems.compactMap { $0.identifier as? String } }

    /// Shows the pane with `id`, or the first pane if there is none.
    func select(_ id: String) {
        tabs.selectedTabViewItemIndex = paneIDs.firstIndex(of: id) ?? 0
        window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
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
    func snapshot(of id: String) async -> Data? {
        tabs.transitionOptions = []
        select(id)
        guard let window else { return nil }
        // The selected toolbar item is a glass layer composited by the window
        // server, which `cacheDisplay` draws as an opaque white box; the title
        // still names the pane.
        window.toolbar?.selectedItemIdentifier = nil
        // Let SwiftUI lay out the new pane and the window adopt its size;
        // the Claude pane also waits for its CLI check to finish.
        try? await Task.sleep(for: id == Pane.claude.rawValue ? .seconds(2) : .milliseconds(300))
        window.layoutIfNeeded()
        // The theme frame (the content view's superview) draws the chrome.
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// The toolbar's panes for a layout: the window's own, with the enabled
    /// modules' panes (in canonical module order) in between.
    private static func entries(modules: ModuleRegistry, enabled: [ModuleID]) -> [Entry] {
        let enabled = Set(enabled)
        let modulePanes = modules.modules
            .filter { enabled.contains($0.id) }
            .compactMap { $0.makeSettingsPane() }
            .map { pane in Entry(id: pane.id, title: pane.title, symbol: pane.symbol) { pane.view } }
        func own(_ panes: [Pane]) -> [Entry] {
            panes.map { pane in Entry(id: pane.rawValue, title: pane.title, symbol: pane.symbol) { view(for: pane) } }
        }
        return own(Pane.leading) + modulePanes + own(Pane.trailing)
    }

    /// Removes panes that are no longer wanted and inserts new ones in
    /// place, so panes that stay keep their state and the selection.
    private static func sync(_ tabs: NSTabViewController, to entries: [Entry], settings: SettingsStore) {
        let ids = Set(entries.map(\.id))
        for item in tabs.tabViewItems where !ids.contains(item.identifier as? String ?? "") {
            tabs.removeTabViewItem(item)
        }
        for (index, entry) in entries.enumerated() {
            let items = tabs.tabViewItems
            if index < items.count, items[index].identifier as? String == entry.id { continue }
            let host = NSHostingController(rootView: entry.makeView().environmentObject(settings))
            // The window follows each pane's natural size as the user switches tabs.
            host.sizingOptions = .preferredContentSize
            // The tab view controller shows the selected child's title in the title bar.
            host.title = entry.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = entry.id
            item.label = entry.title
            item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: entry.title)
            tabs.insertTabViewItem(item, at: index)
        }
    }

    private static func view(for pane: Pane) -> AnyView {
        switch pane {
        case .general: AnyView(GeneralSettingsPane())
        case .modules: AnyView(ModulesSettingsPane())
        case .preview: AnyView(PreviewSettingsPane())
        case .shortcuts: AnyView(ShortcutsSettingsPane())
        case .claude: AnyView(ClaudeSettingsPane())
        case .about: AnyView(AboutSettingsPane())
        }
    }
}
