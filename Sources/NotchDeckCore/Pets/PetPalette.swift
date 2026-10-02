import Foundation

/// An 8-bit sRGB color. Pet art uses a handful of flat colors, so a tiny
/// value type keeps palettes `Codable`, hashable, and free of AppKit.
public struct PetColor: Hashable, Codable, Sendable, CustomStringConvertible {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
        } else {
            self.init(red: UInt8(value >> 24 & 0xFF), green: UInt8(value >> 16 & 0xFF),
                      blue: UInt8(value >> 8 & 0xFF), alpha: UInt8(value & 0xFF))
        }
    }

    /// Uppercase `#RRGGBB`, plus `AA` when not fully opaque.
    public var hex: String {
        alpha == 255
            ? String(format: "#%02X%02X%02X", red, green, blue)
            : String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    public var description: String { hex }

    /// Relative luminance (0...1, WCAG formula). Used to decide whether a fur
    /// color needs a light rim to stay visible on the black notch.
    public var luminance: Double {
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Hue, saturation, and lightness, each 0...1. Fur tinting works in HSL
    /// because "same hue, a bit darker" is exactly how fur shades relate.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxC = max(r, g, b), minC = min(r, g, b)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxC {
        case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        case g: hue = (b - r) / delta + 2
        default: hue = (r - g) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, min(saturation, 1), lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double, alpha: UInt8 = 255) {
        let l = min(max(lightness, 0), 1), s = min(max(saturation, 0), 1)
        let chroma = (1 - abs(2 * l - 1)) * s
        let h6 = hue * 6
        let x = chroma * (1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(h6) % 6 {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = l - chroma / 2
        func byte(_ v: Double) -> UInt8 { UInt8(min(max((v + m) * 255, 0), 255).rounded()) }
        self.init(red: byte(r), green: byte(g), blue: byte(b), alpha: alpha)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let color = PetColor(hex: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid color \(raw)"))
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// What a sprite pixel *means*, not what color it is. Sprite grids paint
/// roles; a palette turns roles into colors. That is what makes every breed,
/// costume, and user recolor work from the same hand-drawn art.
///
/// Each role has a single uppercase character used in sprite text grids.
public enum PetPaletteRole: String, CaseIterable, Codable, Sendable {
    case outline
    case furBase
    case furShade
    case furAccent
    /// Second marking color (calico black patches, beagle saddle).
    case furSpot
    case belly
    case eye
    case eyeLight
    case nose
    /// Cat mouth lines. Resolved against the fur around them (see
    /// `PetCanvas.colors(using:)`), so a mouth reads on both a white muzzle
    /// and black fur.
    case mouth
    case blush
    /// Scrubs and the matching surgical cap (user-recolorable).
    case costumeBase
    case costumeShade
    case costumeTrim
    /// White coat. Kept separate from the scrubs roles so recolored scrubs
    /// never tint the coat.
    case coat
    case coatShade
    /// Cozy knit items and stethoscope tubing (user-recolorable).
    case accessoryBase
    case accessoryShade
    /// Dark gear: graduation cap, head mirror band, pens.
    case ink
    /// Glasses frames, graduation tassel.
    case gold
    /// Stethoscope chest piece, head mirror.
    case metal
    /// Light effect pixels: sleep "z", sparkles, speech bubble fill.
    case effect
    /// Celebration heart.
    case heart

    /// The grid character for this role.
    public var symbol: Character {
        switch self {
        case .outline: "O"
        case .furBase: "B"
        case .furShade: "S"
        case .furAccent: "A"
        case .furSpot: "K"
        case .belly: "W"
        case .eye: "E"
        case .eyeLight: "L"
        case .nose: "N"
        case .mouth: "R"
        case .blush: "P"
        case .costumeBase: "C"
        case .costumeShade: "D"
        case .costumeTrim: "T"
        case .coat: "U"
        case .coatShade: "V"
        case .accessoryBase: "G"
        case .accessoryShade: "J"
        case .ink: "Q"
        case .gold: "Y"
        case .metal: "M"
        case .effect: "Z"
        case .heart: "H"
        }
    }

    public init?(symbol: Character) {
        guard let role = Self.allCases.first(where: { $0.symbol == symbol }) else { return nil }
        self = role
    }

    /// Roles a user may recolor from the customization UI. Eyes, outline,
    /// and effects stay fixed so every pet keeps the same readable style.
    public static let userEditable: [PetPaletteRole] = [
        .furBase, .furShade, .furAccent, .furSpot, .belly, .costumeBase, .costumeShade, .costumeTrim,
        .accessoryBase, .accessoryShade,
    ]
}

/// A complete role -> color table. Breeds define a default palette; a pet
/// profile layers user overrides on top with `applying(_:)`.
public struct PetPalette: Hashable, Codable, Sendable {
    public private(set) var colors: [PetPaletteRole: PetColor]

    /// Every role must have a color so rendering never hits a hole; missing
    /// entries fall back to `PetPalette.base`.
    public init(_ colors: [PetPaletteRole: PetColor]) {
        var filled = PetPalette.baseColors
        filled.merge(colors) { _, new in new }
        self.colors = filled
    }

    public subscript(role: PetPaletteRole) -> PetColor {
        get { colors[role] ?? PetPalette.baseColors[role]! }
        set { colors[role] = newValue }
    }

    /// A copy with `overrides` replacing the matching roles.
    public func applying(_ overrides: [PetPaletteRole: PetColor]) -> PetPalette {
        var copy = self
        for (role, color) in overrides { copy[role] = color }
        return copy
    }

    /// The fur roles that `furTint(_:)` recolors. Spots and the belly keep
    /// their breed colors so tuxedo, calico, and corgi markings survive.
    public static let tintableFurRoles: [PetPaletteRole] = [.furBase, .furShade, .furAccent]

    /// Overrides that recolor all fur roles from one picked color.
    ///
    /// `furAccent` means different things per breed (darker stripes on a
    /// tabby, lighter feathering on a golden), so setting each role to a
    /// fixed color would invert some breeds' markings. Instead the picked
    /// color becomes `furBase`, and every other fur role keeps the picked
    /// hue while shifting lightness by as much as it differed from this
    /// palette's `furBase`. Each breed's light/dark structure is preserved.
    public func furTint(_ color: PetColor) -> [PetPaletteRole: PetColor] {
        let base = self[.furBase].hsl
        let target = color.hsl
        var overrides: [PetPaletteRole: PetColor] = [.furBase: color]
        for role in Self.tintableFurRoles where role != .furBase {
            let original = self[role].hsl
            overrides[role] = PetColor(hue: target.hue, saturation: target.saturation,
                                       lightness: target.lightness + original.lightness - base.lightness)
        }
        return overrides
    }

    /// A copy whose outline stays visible on the black notch. Dark fur with a
    /// dark outline would vanish, so the outline becomes a warm light rim.
    /// Applied after user overrides, so recoloring a pet black is still safe.
    public func withVisibleRim() -> PetPalette {
        guard self[.furBase].luminance < PetPalette.darkFurThreshold,
              self[.outline].luminance < PetPalette.rimMinimumLuminance else { return self }
        var copy = self
        copy[.outline] = PetPalette.warmRim
        return copy
    }

    /// Fur darker than this needs a rim (about #555 gray).
    static let darkFurThreshold = 0.09
    /// Outlines at least this bright already read on black.
    static let rimMinimumLuminance = 0.12
    public static let warmRim = PetColor(hex: "#9C7A68")!
    /// Fur around a mouth darker than this (on average) gets a rim-colored
    /// mouth instead of the dark one.
    static let darkMouthBackground = 0.15

    /// Shared, breed-independent colors: eyes, effects, the default costume.
    static let baseColors: [PetPaletteRole: PetColor] = [
        .outline: PetColor(hex: "#2A1A14")!,
        .furBase: PetColor(hex: "#E9A25B")!,
        .furShade: PetColor(hex: "#C87A3E")!,
        .furAccent: PetColor(hex: "#A85A2A")!,
        .furSpot: PetColor(hex: "#3A3036")!,
        .belly: PetColor(hex: "#FFF1DC")!,
        .eye: PetColor(hex: "#1E1420")!,
        .eyeLight: PetColor(hex: "#FFFFFF")!,
        .nose: PetColor(hex: "#E77A8C")!,
        .mouth: PetColor(hex: "#2A1A14")!,
        .blush: PetColor(hex: "#FF9AAE")!,
        .costumeBase: PetColor(hex: "#5BC0BE")!,
        .costumeShade: PetColor(hex: "#3E9593")!,
        .costumeTrim: PetColor(hex: "#E8FFFB")!,
        .coat: PetColor(hex: "#F6F8FB")!,
        .coatShade: PetColor(hex: "#C3CCD9")!,
        .accessoryBase: PetColor(hex: "#E0607A")!,
        .accessoryShade: PetColor(hex: "#B04460")!,
        .ink: PetColor(hex: "#3F4A78")!,
        .gold: PetColor(hex: "#F2C14E")!,
        .metal: PetColor(hex: "#C9D3DD")!,
        .effect: PetColor(hex: "#F4F1FF")!,
        .heart: PetColor(hex: "#FF5C7A")!,
    ]

    public static let base = PetPalette([:])

    // Codable as a flat `{ "furBase": "#RRGGBB", ... }` object.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: String].self)
        var colors: [PetPaletteRole: PetColor] = [:]
        for (key, hex) in raw {
            if let role = PetPaletteRole(rawValue: key), let color = PetColor(hex: hex) { colors[role] = color }
        }
        self.init(colors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: colors.map { ($0.key.rawValue, $0.value) }))
    }
}
