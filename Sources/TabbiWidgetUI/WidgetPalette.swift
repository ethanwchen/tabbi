import AppKit
import SwiftUI

/// The widget's colors: the warm browns, cream and gold of the Tabbi site,
/// as a cream card in light desktop mode and a cocoa one in dark mode. The
/// widget sits on the wallpaper, not on the notch, so it does not use the
/// app's notch-black `Theme`.
enum WidgetPalette {
    static let background = dynamic(light: 0xFBF7F0, dark: 0x2A231D)
    /// The pet's tile and the stat chips.
    static let surface = dynamic(light: 0xF3EADC, dark: 0x362D25)
    static let primaryText = dynamic(light: 0x2A231D, dark: 0xFBF7F0)
    static let secondaryText = dynamic(light: 0x6E6357, dark: 0xA39888)
    /// Gold for the streak and the running clock: deeper on cream, so it
    /// keeps its contrast.
    static let accent = dynamic(light: 0xA9781C, dark: 0xF4D57E)
    /// The break clock, so a break never reads as focus time.
    static let rest = dynamic(light: 0xB65C66, dark: 0xF2A0A6)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
