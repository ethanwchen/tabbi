import XCTest
import AppKit
import TabbiKit
@testable import Tabbi

/// Tabbi has no visible menu bar, so its hidden main menu is the only way the
/// standard editing shortcuts reach text fields (a friend code pasted in
/// Party, a question typed into Ask Claude).
@MainActor
final class MainMenuTests: XCTestCase {
    private func item(in menu: NSMenu, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        let edit = menu.items.compactMap(\.submenu).first { $0.title == "Edit" }
        return edit?.items.first {
            $0.keyEquivalent == key
                && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers
        }
    }

    func testEditMenuHasTheStandardShortcuts() {
        let menu = MainMenu.make()
        let expected: [(String, NSEvent.ModifierFlags, String)] = [
            ("c", .command, "copy:"),
            ("v", .command, "paste:"),
            ("x", .command, "cut:"),
            ("a", .command, "selectAll:"),
            ("z", .command, "undo:"),
            ("z", [.command, .shift], "redo:"),
        ]
        for (key, modifiers, action) in expected {
            let found = item(in: menu, key: key, modifiers: modifiers)
            XCTAssertEqual(found?.action.map(NSStringFromSelector), action, "\(modifiers) \(key)")
            // Nil target: the first responder (the focused field) handles it.
            XCTAssertNil(found?.target)
        }
    }

    func testAppMenuComesFirstAndAddsNoShortcuts() {
        let menu = MainMenu.make()
        XCTAssertEqual(menu.items.last?.submenu?.title, "Edit")
        XCTAssertEqual(menu.items.first?.submenu?.items.count, 0)
    }

    func testThePanelPassesShortcutsToTheMainMenu() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        let menu = NSMenu()
        let edit = NSMenu(title: "Edit")
        let probe = Probe()
        let paste = NSMenuItem(title: "Paste", action: #selector(Probe.paste(_:)), keyEquivalent: "v")
        paste.target = probe
        edit.addItem(paste)
        let editItem = NSMenuItem()
        editItem.submenu = edit
        menu.addItem(editItem)
        app.mainMenu = menu

        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 40))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertTrue(probe.pasted)
    }

    /// The real menu reaches a focused field in the panel through the
    /// responder chain (Select All, so the test leaves the clipboard alone).
    func testSelectAllReachesAFieldInThePanel() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        app.mainMenu = MainMenu.make()

        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40))
        let field = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        field.string = "FRIEND-42"
        field.setSelectedRange(NSRange(location: 0, length: 0))
        panel.contentView = field
        XCTAssertTrue(panel.makeFirstResponder(field))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(field.selectedRange(), NSRange(location: 0, length: 9))
    }

    /// Shift tells Redo from Undo; AppKit reports the key as "Z" then.
    func testShiftCommandZRedoesInsteadOfUndoing() throws {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        let probe = Probe()
        let menu = MainMenu.make()
        for item in menu.items.compactMap(\.submenu).flatMap(\.items) where item.action != nil {
            item.target = probe
        }
        app.mainMenu = menu

        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 40))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "Z",
            charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(probe.performed, ["redo:"])
    }
}

private final class Probe: NSObject {
    var pasted = false
    var performed: [String] = []
    @objc func paste(_ sender: Any?) { pasted = true }
    @objc func undo(_ sender: Any?) { performed.append("undo:") }
    @objc func redo(_ sender: Any?) { performed.append("redo:") }
}
