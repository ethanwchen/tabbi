import AppKit

/// Where the hardware notch is (or where a virtual one should go).
struct NotchGeometry: Equatable {
    /// Size of the hardware notch, or of the virtual pill on notchless screens.
    var notchSize: CGSize
    var hasHardwareNotch: Bool
    /// The screen's full frame in global coordinates.
    var screenFrame: CGRect
    /// Horizontal center of the notch in global coordinates.
    var centerX: CGFloat

    /// The screen NotchDeck lives on: the built-in notched display if present.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func measure(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasHardwareNotch: true,
                screenFrame: frame,
                centerX: frame.minX + left.width + width / 2
            )
        }
        // Notchless display: a virtual pill tucked into the menu bar.
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(
            notchSize: CGSize(width: 190, height: menuBarHeight),
            hasHardwareNotch: false,
            screenFrame: frame,
            centerX: frame.midX
        )
    }
}
