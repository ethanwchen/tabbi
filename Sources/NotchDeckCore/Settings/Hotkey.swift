/// A global keyboard shortcut, stored as a macOS virtual key code plus modifiers.
///
/// Kept free of Carbon/AppKit so it can be persisted and unit tested; the app
/// translates it to `RegisterEventHotKey` flags.
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// `kVK_*` virtual key code.
    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control-Option-Space.
    public static let `default` = Hotkey(keyCode: KeyCode.space, modifiers: [.control, .option])

    /// A global shortcut needs at least one of Control, Option or Command;
    /// Shift alone would swallow ordinary typing.
    public var isValid: Bool {
        !modifiers.intersection([.control, .option, .command]).isEmpty && KeyCode.name(for: keyCode) != nil
    }

    /// Human-readable form in Apple's modifier order, e.g. "⌃⌥Space".
    public var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + (KeyCode.name(for: keyCode) ?? "Key \(keyCode)")
    }

    /// ANSI virtual key codes (`kVK_*` from Carbon's Events.h) and their display names.
    public enum KeyCode {
        public static let space: UInt32 = 49

        private static let names: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
            15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
            42: "\\", 50: "`",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]

        /// Display name for a key code, or `nil` for keys NotchDeck doesn't support as hotkeys.
        public static func name(for keyCode: UInt32) -> String? { names[keyCode] }
    }
}
