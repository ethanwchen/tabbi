import CoreGraphics

/// When the notch panel steps aside: the two most common complaints about
/// notch apps are a panel drawn over fullscreen video and games, and a
/// virtual notch on an external monitor nobody asked for. These rules decide
/// both from plain values so they can be tested without a screen.
public enum NotchVisibility {
    /// A window as `CGWindowListCopyWindowInfo` reports it. Only bounds and
    /// layer are read, which needs no Screen Recording permission.
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        /// The window level; ordinary app windows are on layer 0.
        public var layer: Int
        public var alpha: Double
        /// In global display coordinates (origin at the top left of the main display).
        public var bounds: CGRect

        public init(ownerPID: Int32, layer: Int, alpha: Double = 1, bounds: CGRect) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.alpha = alpha
            self.bounds = bounds
        }
    }

    /// True when an app other than `ownPID` shows a visible, ordinary window
    /// covering all of `displayBounds` (same coordinate space as the window
    /// bounds): a native fullscreen space, a fullscreen game or video. A zoomed
    /// window leaves the menu bar uncovered and the desktop sits below layer 0,
    /// so neither counts.
    public static func isFullscreenAppActive(windows: [Window], displayBounds: CGRect, ownPID: Int32) -> Bool {
        guard !displayBounds.isEmpty else { return false }
        return windows.contains { window in
            window.ownerPID != ownPID && window.layer == 0 && window.alpha > 0
                && window.bounds.contains(displayBounds)
        }
    }

    /// The screen the notch should appear on, or nil when it should not appear
    /// at all: with `showOnExternalDisplays` off only built-in screens qualify,
    /// so a closed lid or a desk setup without the MacBook hides the notch.
    public static func screen(for preference: DisplayPreference, showOnExternalDisplays: Bool,
                              in screens: [DisplayPreference.Screen]) -> DisplayPreference.Screen? {
        preference.resolve(in: showOnExternalDisplays ? screens : screens.filter(\.isBuiltIn))
    }

    /// Whether the panel is shown. `revealed` is the user asking for it with
    /// the global shortcut, which brings it back over a fullscreen app.
    public static func isShown(hideInFullscreen: Bool, fullscreenAppActive: Bool, revealed: Bool) -> Bool {
        revealed || !(hideInFullscreen && fullscreenAppActive)
    }
}
