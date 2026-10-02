import AppKit
import NotchKitCore

/// Where the hardware notch is (or where a virtual one should go).
struct NotchGeometry: Equatable {
    /// Size of the hardware notch, or of the virtual pill on notchless screens.
    var notchSize: CGSize
    var hasHardwareNotch: Bool
    /// The screen's full frame in global coordinates.
    var screenFrame: CGRect
    /// Horizontal center of the notch in global coordinates.
    var centerX: CGFloat

    /// The screen NotchDeck lives on, per the user's display preference, falling
    /// back to another connected screen when the preferred one is gone.
    static func screen(for preference: DisplayPreference) -> NSScreen? {
        let screens = NSScreen.screens
        let descriptors = screens.map { screen in
            let id = screen.displayID
            return DisplayPreference.Screen(id: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                                            isMain: id == CGMainDisplayID())
        }
        guard let chosen = preference.resolve(in: descriptors) else { return nil }
        return screens.first { $0.displayID == chosen.id }
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

extension NSScreen {
    /// The screen's `CGDirectDisplayID`, stable while the display stays connected.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
