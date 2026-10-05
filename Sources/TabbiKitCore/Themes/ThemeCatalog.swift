import Foundation

/// Every theme Tabbi ships, in picker order.
public enum ThemeCatalog {
    /// Used when nothing (settings or kit) picks a theme.
    public static let defaultID: ThemeID = .midnight

    public static let all: [AppTheme] = [midnight, graphite, liquidGlass, neon, monochrome, cozy, sakura, forest]

    /// The theme with `id`, or nil when this build doesn't have it.
    public static func theme(_ id: ThemeID) -> AppTheme? {
        all.first { $0.id == id }
    }

    /// The theme with `id`, falling back to the default so an unknown saved
    /// id (from a newer build) still draws something sensible.
    public static func resolve(_ id: ThemeID) -> AppTheme {
        theme(id) ?? midnight
    }

    /// The theme a kit's `theme` field names, or nil for an id this build
    /// doesn't have. "notch", the name kits used before themes existed, is
    /// Midnight.
    public static func id(forKitValue value: String) -> ThemeID? {
        let id = legacyKitIDs[value] ?? ThemeID(rawValue: value)
        return theme(id)?.id
    }

    static let legacyKitIDs: [String: ThemeID] = ["notch": .midnight]

    // Status colors shared by the classic themes.
    private static let green = ThemeColor(red: 0.30, green: 0.85, blue: 0.48)
    private static let amber = ThemeColor(red: 1.00, green: 0.74, blue: 0.28)
    private static let red = ThemeColor(red: 1.00, green: 0.38, blue: 0.36)

    /// White text and surfaces on black: the original Tabbi look.
    public static let midnight = AppTheme(
        id: .midnight, name: "Midnight", summary: "Hardware black, calm and crisp.", family: .classic,
        palette: ThemePalette(
            surface: ThemeColor(white: 1, opacity: 0.07), surfaceHover: ThemeColor(white: 1, opacity: 0.12),
            stroke: ThemeColor(white: 1, opacity: 0.08), primaryText: ThemeColor(white: 1),
            secondaryText: ThemeColor(white: 1, opacity: 0.62), tertiaryText: ThemeColor(white: 1, opacity: 0.38),
            success: green, warning: amber, danger: red))

    public static let graphite = AppTheme(
        id: .graphite, name: "Graphite", summary: "Cool gray surfaces and plain SF type.", family: .classic,
        palette: ThemePalette(
            glow: ThemeColor(red: 0.36, green: 0.38, blue: 0.42, opacity: 0.24),
            surface: ThemeColor(red: 0.78, green: 0.82, blue: 0.90, opacity: 0.09),
            surfaceHover: ThemeColor(red: 0.78, green: 0.82, blue: 0.90, opacity: 0.15),
            stroke: ThemeColor(red: 0.78, green: 0.82, blue: 0.90, opacity: 0.12),
            primaryText: ThemeColor(red: 0.94, green: 0.95, blue: 0.97),
            secondaryText: ThemeColor(red: 0.88, green: 0.90, blue: 0.94, opacity: 0.64),
            tertiaryText: ThemeColor(red: 0.88, green: 0.90, blue: 0.94, opacity: 0.40),
            success: green, warning: amber, danger: red),
        typeface: .standard)

    /// An opaque black body like the Dynamic Island, with Liquid Glass only
    /// on small floating controls.
    public static let liquidGlass = AppTheme(
        id: .liquidGlass, name: "Liquid Glass", summary: "Black body, glass controls on macOS 26.",
        family: .classic,
        palette: ThemePalette(
            surface: ThemeColor(white: 1, opacity: 0.08), surfaceHover: ThemeColor(white: 1, opacity: 0.14),
            stroke: ThemeColor(white: 1, opacity: 0.14), primaryText: ThemeColor(white: 1),
            secondaryText: ThemeColor(white: 1, opacity: 0.66), tertiaryText: ThemeColor(white: 1, opacity: 0.40),
            success: green, warning: amber, danger: red),
        typeface: .standard, controls: .glass)

    public static let neon = AppTheme(
        id: .neon, name: "Neon", summary: "Vivid accents with a violet glow.", family: .classic,
        palette: ThemePalette(
            glow: ThemeColor(red: 0.55, green: 0.18, blue: 0.95, opacity: 0.22),
            surface: ThemeColor(red: 0.70, green: 0.80, blue: 1.00, opacity: 0.08),
            surfaceHover: ThemeColor(red: 0.70, green: 0.80, blue: 1.00, opacity: 0.14),
            stroke: ThemeColor(red: 0.35, green: 0.95, blue: 1.00, opacity: 0.22),
            primaryText: ThemeColor(white: 1),
            secondaryText: ThemeColor(red: 0.85, green: 0.92, blue: 1.00, opacity: 0.68),
            tertiaryText: ThemeColor(red: 0.85, green: 0.92, blue: 1.00, opacity: 0.42),
            success: ThemeColor(red: 0.20, green: 1.00, blue: 0.60),
            warning: ThemeColor(red: 1.00, green: 0.85, blue: 0.20),
            danger: ThemeColor(red: 1.00, green: 0.25, blue: 0.55)),
        accents: .vivid)

    public static let monochrome = AppTheme(
        id: .monochrome, name: "Monochrome", summary: "Grayscale everything, no distractions.", family: .classic,
        palette: ThemePalette(
            surface: ThemeColor(white: 1, opacity: 0.07), surfaceHover: ThemeColor(white: 1, opacity: 0.12),
            stroke: ThemeColor(white: 1, opacity: 0.10), primaryText: ThemeColor(white: 1),
            secondaryText: ThemeColor(white: 1, opacity: 0.62), tertiaryText: ThemeColor(white: 1, opacity: 0.38),
            success: ThemeColor(white: 0.92), warning: ThemeColor(white: 0.78),
            // Errors keep a soft red: losing them would hide real problems.
            danger: ThemeColor(red: 0.95, green: 0.55, blue: 0.53)),
        accents: .monochrome, typeface: .standard)

    /// The study default: cream text, peach glow, sage and honey status
    /// colors, pastel accents and gentle motion.
    public static let cozy = AppTheme(
        id: .cozy, name: "Cozy", summary: "Warm cream and peach, soft and gentle.", family: .cozy,
        palette: cozyPalette(glow: ThemeColor(red: 0.96, green: 0.60, blue: 0.42, opacity: 0.18),
                             tint: ThemeColor(red: 1.00, green: 0.93, blue: 0.84)),
        accents: .pastel, motion: .gentle)

    public static let sakura = AppTheme(
        id: .sakura, name: "Sakura", summary: "Cherry blossom pink on warm black.", family: .cozy,
        palette: cozyPalette(glow: ThemeColor(red: 0.98, green: 0.52, blue: 0.68, opacity: 0.18),
                             tint: ThemeColor(red: 1.00, green: 0.91, blue: 0.94)),
        accents: .pastel, motion: .gentle)

    public static let forest = AppTheme(
        id: .forest, name: "Forest", summary: "Mossy sage greens, quiet as a walk.", family: .cozy,
        palette: cozyPalette(glow: ThemeColor(red: 0.42, green: 0.68, blue: 0.46, opacity: 0.18),
                             tint: ThemeColor(red: 0.92, green: 1.00, blue: 0.92)),
        accents: .pastel, motion: .gentle)

    /// The cozy themes share one structure: surfaces and text tinted toward
    /// `tint`, a colored `glow`, and soft status colors.
    private static func cozyPalette(glow: ThemeColor, tint: ThemeColor) -> ThemePalette {
        ThemePalette(
            glow: glow,
            surface: tint.opacity(0.08), surfaceHover: tint.opacity(0.14), stroke: tint.opacity(0.10),
            primaryText: tint.mixed(with: ThemeColor(white: 1), by: 0.4),
            secondaryText: tint.opacity(0.66), tertiaryText: tint.opacity(0.42),
            success: ThemeColor(red: 0.62, green: 0.82, blue: 0.58),
            warning: ThemeColor(red: 0.98, green: 0.78, blue: 0.45),
            danger: ThemeColor(red: 0.96, green: 0.52, blue: 0.50))
    }
}
