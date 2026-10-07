import CoreGraphics

/// How much of Tabbi stays on screen while the notch is closed. Some people
/// want the notch out of the way until they reach for it, and some only ever
/// open it with the global shortcut; `NotchVisibility.isShown` applies it.
public enum NotchMode: String, CaseIterable, Sendable {
    /// The closed notch, its wings and preview are always drawn.
    case alwaysVisible = "always"
    /// Nothing is drawn until the pointer reaches the top-center hot zone
    /// (`NotchVisibility.hoverZone`), and it goes away once the pointer leaves.
    case showOnHover = "hover"
    /// Nothing is drawn and hovering does nothing; only the global shortcut
    /// opens the notch.
    case hidden

    public static let `default`: NotchMode = .alwaysVisible

    /// The name Settings and the notch's right-click menu show.
    public var title: String {
        switch self {
        case .alwaysVisible: "Always Visible"
        case .showOnHover: "Show on Hover"
        case .hidden: "Hidden"
        }
    }
}

extension NotchVisibility {
    /// Whether the panel is shown.
    /// - Parameters:
    ///   - mode: the user's `NotchMode`.
    ///   - revealed: the user asked for the notch with the global shortcut,
    ///     which brings it back over a fullscreen app and in every mode.
    ///   - pointerNear: the pointer is in the hover zone, or on the notch
    ///     while it is drawn.
    ///   - isOpen: the notch is open (or pinned open), so it stays drawn in
    ///     any mode until it closes, even after the pointer leaves.
    public static func isShown(mode: NotchMode, hideInFullscreen: Bool, fullscreenAppActive: Bool,
                               revealed: Bool, pointerNear: Bool, isOpen: Bool) -> Bool {
        if revealed { return true }
        if hideInFullscreen && fullscreenAppActive { return false }
        switch mode {
        case .alwaysVisible: return true
        case .showOnHover: return pointerNear || isOpen
        case .hidden: return isOpen
        }
    }

    /// Room around the closed notch that still counts as reaching for it, so
    /// the pointer need not land exactly on a small hardware notch.
    public static let hoverZoneMargin = CGSize(width: 24, height: 8)

    /// The top-center area that brings a `.showOnHover` notch out, in
    /// AppKit screen coordinates (origin at the bottom left): the closed
    /// notch's rect (which touches the top of its screen), wider by
    /// `hoverZoneMargin` on each side and taller below.
    public static func hoverZone(closedNotch: CGRect) -> CGRect {
        guard !closedNotch.isEmpty else { return .null }
        let margin = hoverZoneMargin
        return CGRect(x: closedNotch.minX - margin.width, y: closedNotch.minY - margin.height,
                      width: closedNotch.width + margin.width * 2, height: closedNotch.height + margin.height)
    }

    /// Whether the pointer at `point` keeps a `.showOnHover` notch out: in
    /// the hover zone, or (once the notch is drawn) anywhere on its shape,
    /// so moving onto the wings or a preview does not make it vanish.
    public static func isPointerNear(_ point: CGPoint, hoverZone: CGRect, drawnShape: CGRect?) -> Bool {
        if hoverZone.contains(point) { return true }
        guard let drawnShape else { return false }
        return drawnShape.insetBy(dx: -4, dy: -4).contains(point)
    }
}
