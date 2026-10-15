/// Keeps the open notch open while the user works in a menu it opened.
///
/// A menu, picker or context menu opened from the notch (Party's birth
/// month and year, a right-click on a friend) draws in a window of its own,
/// usually reaching below the notch's shape. Reaching for an item moves the
/// pointer out of the shape, which on its own closes the notch, and closing
/// it throws away what the panel's views held, such as the month just
/// picked. So from the moment a menu opens on the open notch, the pointer
/// leaving the shape no longer closes it: not while the menu is open, and
/// not after an item is picked with the pointer still outside, until the
/// pointer has come back over the notch. A click elsewhere, Esc or the
/// shortcut still close it as always.
public struct NotchPointerHold: Sendable, Equatable {
    /// Menus open right now that began on the open notch.
    public private(set) var openMenus = 0
    /// True from a menu opening until the pointer is back over the notch
    /// with no menu open.
    public private(set) var holdsOpen = false

    public init() {}

    /// A menu began tracking. Only one on the open notch holds it; one from
    /// the closed notch (its right-click menu) has nothing to keep open.
    public mutating func menuBegan(notchIsOpen: Bool) {
        guard notchIsOpen else { return }
        openMenus += 1
        holdsOpen = true
    }

    /// A menu stopped tracking, with or without a pick. The hold stays until
    /// the pointer comes back, since it is still where the item was.
    public mutating func menuEnded() {
        openMenus = max(0, openMenus - 1)
    }

    /// The pointer is over the notch's shape again: from now on, leaving it
    /// closes the notch as usual, unless a menu is still open.
    public mutating func pointerEntered() {
        guard openMenus == 0 else { return }
        holdsOpen = false
    }

    /// The notch closed (a click elsewhere, Esc, the shortcut), which ends
    /// any hold; a menu still closing after it has nothing to keep open.
    public mutating func notchClosed() {
        openMenus = 0
        holdsOpen = false
    }
}
