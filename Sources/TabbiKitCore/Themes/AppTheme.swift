import Foundation

/// Identifies a theme. Open like `ModuleID`, so an id a newer Tabbi or a kit
/// names survives a round trip through an older build.
public struct ThemeID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public var description: String { rawValue }

    public static let midnight: ThemeID = "midnight"
    public static let graphite: ThemeID = "graphite"
    public static let liquidGlass: ThemeID = "liquidGlass"
    public static let neon: ThemeID = "neon"
    public static let monochrome: ThemeID = "monochrome"
    public static let cozy: ThemeID = "cozy"
    public static let sakura: ThemeID = "sakura"
    public static let forest: ThemeID = "forest"
    public static let blueberryMilk: ThemeID = "blueberryMilk"
    public static let strawberryMilk: ThemeID = "strawberryMilk"
    public static let taro: ThemeID = "taro"
    public static let matchaLatte: ThemeID = "matchaLatte"
    public static let bananaMilk: ThemeID = "bananaMilk"
    public static let deepSea: ThemeID = "deepSea"
    public static let cherrySoda: ThemeID = "cherrySoda"
    public static let stargazer: ThemeID = "stargazer"
    public static let mintChoco: ThemeID = "mintChoco"
    public static let cottonCandy: ThemeID = "cottonCandy"
}

/// An sRGB color with opacity, in 0...1 components, so themes can live in
/// data (`themes.json`) and be tested without SwiftUI.
public struct ThemeColor: Hashable, Sendable, Decodable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// A gray (or white with `opacity`) at `level` brightness.
    public init(white level: Double, opacity: Double = 1) {
        self.init(red: level, green: level, blue: level, opacity: opacity)
    }

    /// The same color at another opacity.
    public func opacity(_ value: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, opacity: value)
    }

    /// Mixes `fraction` (0...1) of `other` into this color.
    public func mixed(with other: ThemeColor, by fraction: Double) -> ThemeColor {
        let t = min(max(fraction, 0), 1)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return ThemeColor(red: mix(red, other.red), green: mix(green, other.green),
                          blue: mix(blue, other.blue), opacity: mix(opacity, other.opacity))
    }

    /// Relative luminance (WCAG 2), ignoring opacity.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// This color painted at its opacity over an opaque `base`.
    public func composited(over base: ThemeColor) -> ThemeColor {
        ThemeColor(red: base.red + (red - base.red) * opacity,
                   green: base.green + (green - base.green) * opacity,
                   blue: base.blue + (blue - base.blue) * opacity)
    }

    /// WCAG contrast ratio between two opaque colors (1...21).
    public func contrast(with other: ThemeColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public init(_ accent: ModuleAccent) {
        self.init(red: accent.red, green: accent.green, blue: accent.blue)
    }

    private enum CodingKeys: String, CodingKey { case white, red, green, blue, opacity }

    /// Reads `themes.json`'s color form: `{"white": w}` for a gray, or
    /// `red`, `green` and `blue`; `opacity` defaults to 1.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        if let white = try container.decodeIfPresent(Double.self, forKey: .white) {
            self.init(white: white, opacity: opacity)
        } else {
            self.init(red: try container.decode(Double.self, forKey: .red),
                      green: try container.decode(Double.self, forKey: .green),
                      blue: try container.decode(Double.self, forKey: .blue), opacity: opacity)
        }
    }
}

/// The colors of the open panel. The panel body is always opaque and its top
/// edge always black, so the open notch stays continuous with the hardware
/// cutout (like the Dynamic Island); a theme adds a soft `glow` toward the
/// bottom instead of repainting the whole panel.
public struct ThemePalette: Hashable, Sendable, Decodable {
    /// The panel body. Opaque in every theme.
    public var background: ThemeColor
    /// A soft color that rises from the bottom edge of the panel; nil for a
    /// flat body.
    public var glow: ThemeColor?
    public var surface: ThemeColor
    public var surfaceHover: ThemeColor
    public var stroke: ThemeColor
    public var primaryText: ThemeColor
    public var secondaryText: ThemeColor
    public var tertiaryText: ThemeColor
    public var success: ThemeColor
    public var warning: ThemeColor
    public var danger: ThemeColor
    /// The theme's own key color, nil when every module keeps its own accent
    /// (as the theme's `accents` treats it). When set, the active module's
    /// ring, selected tab, primary button and chips all wear it, so the
    /// whole panel reads as one color (see `AppTheme.accent(_:)`).
    public var accent: ThemeColor?
    /// Text and symbols drawn on an `accent` fill (a primary button's
    /// label); nil for the panel `background`, the black every theme used
    /// before themes had accents.
    public var onAccent: ThemeColor?

    public init(background: ThemeColor = ThemeColor(white: 0), glow: ThemeColor? = nil,
                surface: ThemeColor, surfaceHover: ThemeColor, stroke: ThemeColor,
                primaryText: ThemeColor, secondaryText: ThemeColor, tertiaryText: ThemeColor,
                success: ThemeColor, warning: ThemeColor, danger: ThemeColor,
                accent: ThemeColor? = nil, onAccent: ThemeColor? = nil) {
        self.background = background
        self.glow = glow
        self.surface = surface
        self.surfaceHover = surfaceHover
        self.stroke = stroke
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.success = success
        self.warning = warning
        self.danger = danger
        self.accent = accent
        self.onAccent = onAccent
    }
}

/// How a theme treats each module's accent color, so one theme can mute or
/// warm every module without the modules knowing. A theme with its own
/// `ThemePalette.accent` still names one: it colors what has to tell modules
/// apart (`AppTheme.identityAccent(_:)`), and builds that predate theme
/// accents use it for everything.
public enum AccentTreatment: String, Hashable, Sendable, CaseIterable, Decodable {
    /// The module's own accent.
    case original
    /// Grayscale at the accent's brightness, lifted so it reads on black.
    case monochrome
    /// Fully saturated and bright, for a glowing look.
    case vivid
    /// Mixed toward a warm cream, for the cozy themes' pastel look.
    case pastel

    /// The contrast against black a vivid accent keeps, so it still reads as text.
    public static let minimumContrast = 4.5

    /// The accent `base` becomes under this treatment.
    public func apply(to base: ModuleAccent) -> ThemeColor {
        let color = ThemeColor(base)
        switch self {
        case .original:
            return color
        case .monochrome:
            // Perceived lightness, kept in a band that reads on black.
            let gray = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
            return ThemeColor(white: 0.55 + gray * 0.4)
        case .vivid:
            let high = max(color.red, color.green, color.blue)
            let low = min(color.red, color.green, color.blue)
            guard high > low else { return ThemeColor(white: 1) }
            // Stretch the channels to the full 0...1 range: same hue, full
            // saturation and brightness.
            func stretch(_ c: Double) -> Double { (c - low) / (high - low) }
            let saturated = ThemeColor(red: stretch(color.red), green: stretch(color.green), blue: stretch(color.blue))
            // Pure blues and violets are too dark to read as text on black,
            // so lift them toward white just enough to reach 4.5:1.
            let black = ThemeColor(white: 0)
            var lift = 0.0
            while saturated.mixed(with: ThemeColor(white: 1), by: lift).contrast(with: black) < Self.minimumContrast,
                  lift < 1 {
                lift += 0.05
            }
            return saturated.mixed(with: ThemeColor(white: 1), by: lift)
        case .pastel:
            return color.mixed(with: ThemeColor(red: 1.0, green: 0.94, blue: 0.86), by: 0.35)
        }
    }
}

/// The type family a theme sets in.
public enum ThemeTypeface: String, Hashable, Sendable, CaseIterable, Decodable {
    /// SF Pro Rounded, the Tabbi default.
    case rounded
    /// SF Pro, for the cooler themes.
    case standard
}

/// How lively a theme's animations are.
public enum ThemeMotion: String, Hashable, Sendable, CaseIterable, Decodable {
    case standard
    /// Slower, softer springs with less bounce, for the cozy themes.
    case gentle

    /// `spec` as this theme plays it: unchanged for `.standard`; for
    /// `.gentle`, 30% longer with 0.08 less bounce (never below none), so a
    /// cozy theme keeps every motion token's character but calmer.
    public func adjusted(_ spec: SpringSpec) -> SpringSpec {
        switch self {
        case .standard: spec
        case .gentle: SpringSpec(duration: spec.duration * 1.3, bounce: max(spec.bounce - 0.08, 0))
        }
    }
}

/// What small floating controls (icon buttons, the tab bar selection) sit on.
public enum ThemeControlStyle: String, Hashable, Sendable, CaseIterable, Decodable {
    /// The palette's opaque surface colors.
    case solid
    /// Liquid Glass where the system offers it (see `ControlMaterial`).
    case glass
}

/// The material a control is actually drawn with on this Mac.
///
/// Apple's guidance: Liquid Glass belongs only to the control layer, never
/// to content, and it falls back to a standard material before macOS 26 and
/// to an opaque fill whenever Reduce Transparency is on.
public enum ControlMaterial: Hashable, Sendable {
    /// `glassEffect`, macOS 26 and later.
    case glass
    /// A standard blur material (macOS 14 and 15).
    case material
    /// The palette's opaque surface.
    case opaque

    /// Resolves a theme's control style for this system.
    public static func resolve(_ style: ThemeControlStyle, glassAvailable: Bool,
                               reduceTransparency: Bool) -> ControlMaterial {
        guard style == .glass, !reduceTransparency else { return .opaque }
        return glassAvailable ? .glass : .material
    }
}

/// What content surfaces (cards) are drawn as.
public enum ThemeSurfaceStyle: String, Hashable, Sendable, CaseIterable, Decodable {
    /// The palette's flat surface color.
    case flat
    /// Frosted glass: a live material where the system can draw one, always
    /// under a drawn `GlassSheen`, so the look survives snapshots and
    /// Reduce Transparency.
    case glass
}

/// The drawn light of a glass surface: a fill that is brighter at the top,
/// a specular glint near the top-leading corner and a rim lit from above.
/// It is plain paint, so it shows the same in the live app, in
/// `ImageRenderer` snapshots (which can't capture materials) and with
/// Reduce Transparency on.
public struct GlassSheen: Hashable, Sendable, Decodable {
    /// The fill at the top edge.
    public var fillTop: ThemeColor
    /// The fill at the bottom edge.
    public var fillBottom: ThemeColor
    /// The glint's center color; it fades out toward the middle.
    public var glint: ThemeColor
    /// The rim at the top edge, where the light catches it.
    public var rimTop: ThemeColor
    /// The rim at the bottom edge.
    public var rimBottom: ThemeColor

    public init(fillTop: ThemeColor, fillBottom: ThemeColor, glint: ThemeColor,
                rimTop: ThemeColor, rimBottom: ThemeColor) {
        self.fillTop = fillTop
        self.fillBottom = fillBottom
        self.glint = glint
        self.rimTop = rimTop
        self.rimBottom = rimBottom
    }

    /// Clear glass lit from above, tuned so white text stays legible on it.
    /// Read from `themes.json`.
    public static var standard: GlassSheen { ThemeCatalog.file.glassSheen }

    /// The brightest the fill gets (top edge plus glint) over `base`, for
    /// checking text contrast.
    public func brightest(over base: ThemeColor) -> ThemeColor {
        glint.composited(over: fillTop.composited(over: base))
    }
}

/// Which group a theme is listed under in the picker.
///
/// `themes.json` writes a theme's group as `family`, which every build reads
/// and which stays `classic` or `cozy`, plus an optional `group` that builds
/// knowing newer groups (`sweet`) prefer. So a file with a new group still
/// decodes in a build that predates it, which lists the theme under its
/// `family`.
public enum ThemeFamily: String, Hashable, Sendable, CaseIterable, Decodable {
    /// Calm, hardware-black looks.
    case classic
    /// Warm, soft looks made for studying.
    case cozy
    /// Milk, candy and soda colors, each owning its accent. Written as
    /// `group`, with `family` `cozy` for older builds.
    case sweet

    /// The values `family` may take, which every build since themes reads.
    public static let baseFamilies: [ThemeFamily] = [.classic, .cozy]
}

/// A complete look for the open panel: colors, accent treatment, type,
/// motion and controls. The closed notch is pure black in every theme.
public struct AppTheme: Identifiable, Hashable, Sendable, Decodable {
    public var id: ThemeID
    public var name: String
    /// One line for the picker.
    public var summary: String
    public var family: ThemeFamily
    public var palette: ThemePalette
    public var accents: AccentTreatment
    public var typeface: ThemeTypeface
    public var motion: ThemeMotion
    public var controls: ThemeControlStyle
    public var surfaces: ThemeSurfaceStyle

    public init(id: ThemeID, name: String, summary: String, family: ThemeFamily, palette: ThemePalette,
                accents: AccentTreatment = .original, typeface: ThemeTypeface = .rounded,
                motion: ThemeMotion = .standard, controls: ThemeControlStyle = .solid,
                surfaces: ThemeSurfaceStyle = .flat) {
        self.id = id
        self.name = name
        self.summary = summary
        self.family = family
        self.palette = palette
        self.accents = accents
        self.typeface = typeface
        self.motion = motion
        self.controls = controls
        self.surfaces = surfaces
    }

    /// The name in the user's language. `themes.json` holds the English,
    /// which the Windows port reads too, so the translation is looked up in
    /// the catalog under `theme.<id>` (a name such as Midnight also names a
    /// fur color, so the English text can't be the key); a theme the catalog
    /// lacks shows its name as written.
    public var displayName: String {
        Bundle.tabbi.localizedString(forKey: "theme.\(id.rawValue)", value: name, table: nil)
    }

    /// The summary in the user's language, looked up by its English text
    /// like the seasonal events' taglines.
    public var displaySummary: String {
        Bundle.tabbi.localizedString(forKey: summary, value: summary, table: nil)
    }

    /// The accent a module with `base` shows in this theme: the theme's own
    /// key color when it has one (`palette.accent`), so the ring, the
    /// selected tab, the primary button and the chips all match it, or else
    /// `base` as `accents` treats it.
    public func accent(_ base: ModuleAccent) -> ThemeColor {
        palette.accent ?? accents.apply(to: base)
    }

    /// `base` as `accents` treats it, even when the theme has a key color:
    /// for what has to tell modules apart, such as module icons listed side
    /// by side or another module's item in Today's list, and for colors with
    /// a meaning of their own (the favorite heart).
    public func identityAccent(_ base: ModuleAccent) -> ThemeColor {
        accents.apply(to: base)
    }

    /// Text and symbols on an `accent(_:)` fill: the palette's `onAccent`,
    /// or the panel background when the theme doesn't set one.
    public var onAccent: ThemeColor {
        palette.onAccent ?? palette.background
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, family, group, palette, accents, typeface, motion, controls, surfaces
    }

    /// Reads `family`, then `group` when it names a family this build knows,
    /// so a group from a newer build falls back to the theme's `family`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let family = try container.decode(ThemeFamily.self, forKey: .family)
        guard ThemeFamily.baseFamilies.contains(family) else {
            throw DecodingError.dataCorruptedError(forKey: .family, in: container,
                                                   debugDescription: "family is classic or cozy; newer groups go in group")
        }
        let group = (try? container.decodeIfPresent(String.self, forKey: .group)).flatMap { $0 }
        self.init(id: try container.decode(ThemeID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  summary: try container.decode(String.self, forKey: .summary),
                  family: group.flatMap(ThemeFamily.init(rawValue:)) ?? family,
                  palette: try container.decode(ThemePalette.self, forKey: .palette),
                  accents: try container.decode(AccentTreatment.self, forKey: .accents),
                  typeface: try container.decode(ThemeTypeface.self, forKey: .typeface),
                  motion: try container.decode(ThemeMotion.self, forKey: .motion),
                  controls: try container.decode(ThemeControlStyle.self, forKey: .controls),
                  surfaces: try container.decode(ThemeSurfaceStyle.self, forKey: .surfaces))
    }
}
