import AppKit
import Combine
import SwiftUI

/// One toolbar pane of the Settings window: the app's own panes and those
/// enabled modules contribute (`NotchModule.makeSettingsPane()`) alike.
public struct SettingsPane {
    /// Unique among all panes; also names the snapshot (`settings-<id>.png`).
    public let id: String
    public let title: String
    /// SF Symbol for the toolbar item.
    public let symbol: String
    public let view: AnyView
    /// How long `SettingsWindowController.snapshot(of:)` lets the pane settle,
    /// longer for panes that load something (e.g. a CLI check) when shown.
    public let settleTime: Duration

    public init(id: String, title: String, symbol: String, view: AnyView, settleTime: Duration = .milliseconds(300)) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.view = view
        self.settleTime = settleTime
    }
}

/// The Settings window: a native toolbar-tabbed preferences window. This is
/// the one place where system chrome and the light/dark system appearance are
/// correct, so it deliberately does not use the notch theme.
///
/// The app decides which panes exist; when `updates` emits a new list (e.g.
/// a module was turned on), panes that stay keep their state and the
/// selection, so Settings only ever shows what the user's tabs can use.
@MainActor
public final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()
    private var panes: [String: SettingsPane] = [:]
    private var cancellable: AnyCancellable?

    /// - Parameters:
    ///   - panes: the panes in toolbar order; the first is selected.
    ///   - updates: later pane lists, applied in place.
    ///   - autosaveName: where AppKit remembers the window's position.
    public init(panes: [SettingsPane], updates: AnyPublisher<[SettingsPane], Never>, autosaveName: String) {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        self.panes = Self.sync(tabs, to: panes)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosaveName)
        super.init(window: window)
        if let first = panes.first { select(first.id) }

        cancellable = updates.sink { [weak self] panes in
            guard let self else { return }
            self.panes = Self.sync(tabs, to: panes)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Ids of the panes in toolbar order.
    public var paneIDs: [String] { tabs.tabViewItems.compactMap { $0.identifier as? String } }

    /// Shows the pane with `id`, or the first pane if there is none.
    public func select(_ id: String) {
        guard !tabs.tabViewItems.isEmpty else { return }
        tabs.selectedTabViewItemIndex = paneIDs.firstIndex(of: id) ?? 0
        window?.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
    }

    /// Brings the window forward. The notch app is an accessory app, so it
    /// must activate itself or the window would open behind the frontmost app.
    public func present() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Renders the window, title bar and toolbar included, to PNG data for
    /// snapshots. Works off screen without Screen Recording permission.
    public func snapshot(of id: String) async -> Data? {
        tabs.transitionOptions = []
        select(id)
        guard let window else { return nil }
        // The selected toolbar item is a glass layer composited by the window
        // server, which `cacheDisplay` draws as an opaque white box; the title
        // still names the pane.
        window.toolbar?.selectedItemIdentifier = nil
        // Let SwiftUI lay out the new pane and the window adopt its size.
        try? await Task.sleep(for: panes[id]?.settleTime ?? .milliseconds(300))
        window.layoutIfNeeded()
        // The theme frame (the content view's superview) draws the chrome.
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Removes panes that are no longer wanted and inserts new ones in
    /// place, so panes that stay keep their state and the selection.
    /// Returns the panes keyed by id.
    private static func sync(_ tabs: NSTabViewController, to wanted: [SettingsPane]) -> [String: SettingsPane] {
        let panes = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in tabs.tabViewItems where panes[item.identifier as? String ?? ""] == nil {
            tabs.removeTabViewItem(item)
        }
        for (index, pane) in wanted.enumerated() {
            let items = tabs.tabViewItems
            if index < items.count, items[index].identifier as? String == pane.id { continue }
            let host = NSHostingController(rootView: pane.view)
            // The window follows each pane's natural size as the user switches tabs.
            host.sizingOptions = .preferredContentSize
            // The tab view controller shows the selected child's title in the title bar.
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = pane.id
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.insertTabViewItem(item, at: index)
        }
        return panes
    }
}
