import AppKit
import SwiftUI

/// A borderless, transparent panel pinned over the notch.
///
/// Non-activating so clicking it never steals focus from the app you're in,
/// but it can still become key so text fields (Ask Claude) accept typing.
public final class NotchPanel: NSPanel {
    public init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Above the menu bar so the notch can draw over it.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
    }

    /// Leaves the notch out of screenshots, recordings and shared screens,
    /// and out of Mission Control, as the user chose in Settings. Both are
    /// public window properties, so they work in the sandboxed edition.
    public func applyPrivacy(hideFromScreenCapture: Bool, hideInMissionControl: Bool) {
        sharingType = hideFromScreenCapture ? .none : .readOnly
        // A stationary window stays drawn over Mission Control like the
        // desktop; a transient one is hidden while it is open.
        collectionBehavior.remove([.stationary, .transient])
        collectionBehavior.insert(hideInMissionControl ? .transient : .stationary)
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    /// The panel can be key while another app stays active. AppKit then
    /// sends a main menu item's action to the key window it knows of, which
    /// need not be this panel, so Command-C, Command-V and the other Edit
    /// menu shortcuts are run here, down this panel's responder chain.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard let menu = NSApp.mainMenu, let item = Self.item(in: menu, matching: event),
              let action = item.action else { return false }
        if let target = item.target { return NSApp.sendAction(action, to: target, from: item) }
        return firstResponder?.tryToPerform(action, with: item) ?? false
    }

    /// The enabled menu item, at any depth, whose shortcut is the pressed key.
    static func item(in menu: NSMenu, matching event: NSEvent) -> NSMenuItem? {
        let shortcutFlags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let flags = event.modifierFlags.intersection(shortcutFlags)
        guard !flags.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { return nil }
        for item in menu.items {
            if let submenu = item.submenu {
                if let found = self.item(in: submenu, matching: event) { return found }
            } else if item.isEnabled, item.keyEquivalent.lowercased() == key,
                      item.keyEquivalentModifierMask.intersection(shortcutFlags) == flags {
                return item
            }
        }
        return nil
    }
}

/// Hosting view that accepts the first click, so a single click on the closed
/// notch opens it without first focusing the panel.
public final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
