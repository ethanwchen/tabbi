import SwiftUI

/// How WidgetKit draws the widget, mirrored from `WidgetRenderingMode` so the
/// views and their tests can pick a style without a WidgetKit environment.
public enum PetWidgetRendering: Sendable, CaseIterable {
    /// The widget's own colors: the desktop when it is focused, and
    /// Notification Center.
    case fullColor
    /// One tint for everything (the "tinted" and monochrome widget styles
    /// of macOS 26 and later); the system removes the background.
    case accented
    /// Desaturated and blended into the wallpaper (the desktop while an app
    /// is in front, from macOS 14); the system removes the background.
    case vibrant
}

/// The widget's colors: the warm browns, cream and gold of the Tabbi site,
/// as a cream card in light desktop mode and a cocoa one in dark mode. The
/// widget sits on the wallpaper, not on the notch, so it does not use the
/// app's notch-black `Theme`.
///
/// Colors are plain sRGB values picked from the color scheme in the view's
/// environment, which WidgetKit sets for each appearance it renders, rather
/// than dynamic `NSColor`s, whose appearance closure does not survive the
/// archive WidgetKit sends to the process that draws the widget.
///
/// Outside full color the system draws the content in one color or as
/// vibrancy, taking only each pixel's coverage or brightness. Our own colors
/// would turn into solid blocks (an opaque tile hides what is on it) or
/// vanish (dark text), which is how a widget turns blank or white, so those
/// modes use the hierarchical styles the system knows how to draw, and the
/// tiles become faint fills.
struct WidgetPalette {
    /// The container background, which the system removes outside full color.
    var background: Color
    /// The pet's tile and the stat chips.
    var surface: AnyShapeStyle
    var primaryText: AnyShapeStyle
    var secondaryText: AnyShapeStyle
    /// Gold for the streak and the running clock: deeper on cream, so it
    /// keeps its contrast.
    var accent: AnyShapeStyle
    /// The break clock, so a break never reads as focus time.
    var rest: AnyShapeStyle

    init(scheme: ColorScheme, rendering: PetWidgetRendering) {
        let isDark = scheme == .dark
        background = Self.color(isDark ? 0x2A231D : 0xFBF7F0)
        switch rendering {
        case .fullColor:
            surface = AnyShapeStyle(Self.color(isDark ? 0x362D25 : 0xF3EADC))
            primaryText = AnyShapeStyle(Self.color(isDark ? 0xFBF7F0 : 0x2A231D))
            secondaryText = AnyShapeStyle(Self.color(isDark ? 0xA39888 : 0x6E6357))
            accent = AnyShapeStyle(Self.color(isDark ? 0xF4D57E : 0xA9781C))
            rest = AnyShapeStyle(Self.color(isDark ? 0xF2A0A6 : 0xB65C66))
        case .accented, .vibrant:
            surface = AnyShapeStyle(.quaternary)
            primaryText = AnyShapeStyle(.primary)
            secondaryText = AnyShapeStyle(.secondary)
            accent = AnyShapeStyle(.primary)
            rest = AnyShapeStyle(.primary)
        }
    }

    static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}
