import AppKit

/// The app's hidden main menu.
///
/// Tabbi is an accessory app, so macOS never shows a menu bar for it, but
/// AppKit still routes standard key equivalents (Command-C, Command-V and the
/// rest) through `NSApp.mainMenu`. Without one, text fields in the notch and
/// in Settings could not copy, paste or undo. Every item targets the first
/// responder, so whichever field has the caret handles it.
@MainActor
enum MainMenu {
    /// One standard text editing command.
    struct EditCommand {
        let title: String
        let action: Selector
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    /// The commands in the Edit menu, in menu order. A nil entry is a separator.
    static let editCommands: [EditCommand?] = [
        EditCommand(title: "Undo", action: Selector(("undo:")), key: "z", modifiers: .command),
        EditCommand(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]),
        nil,
        EditCommand(title: "Cut", action: #selector(NSText.cut(_:)), key: "x", modifiers: .command),
        EditCommand(title: "Copy", action: #selector(NSText.copy(_:)), key: "c", modifiers: .command),
        EditCommand(title: "Paste", action: #selector(NSText.paste(_:)), key: "v", modifiers: .command),
        EditCommand(title: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)),
                    key: "v", modifiers: [.command, .option, .shift]),
        EditCommand(title: "Delete", action: #selector(NSText.delete(_:)), key: "", modifiers: []),
        EditCommand(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a", modifiers: .command),
    ]

    /// Installs the menu as `NSApp.mainMenu`.
    static func install() {
        NSApp.mainMenu = make()
    }

    /// An app menu (required first, left empty so nothing else changes) and
    /// the Edit menu.
    static func make() -> NSMenu {
        let menu = NSMenu(title: "Main Menu")
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "Tabbi")
        menu.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        for command in editCommands {
            guard let command else {
                edit.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: command.title, action: command.action, keyEquivalent: command.key)
            item.keyEquivalentModifierMask = command.modifiers
            edit.addItem(item)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        return menu
    }
}
