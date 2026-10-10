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

    /// Lightness, chroma, and hue in OKLCH. Fur tones are derived here
    /// rather than in HSL because OKLab lightness steps look even across
    /// hues: "a bit darker" is as visible on pastel blue as on orange, and
    /// yellows and blues no longer drift in brightness.
    public var oklch: (lightness: Double, chroma: Double, hue: Double) {
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.412_221_470_8 * r + 0.536_332_536_3 * g + 0.051_445_992_9 * b)
        let m = cbrt(0.211_903_498_2 * r + 0.680_699_545_1 * g + 0.107_396_956_6 * b)
        let s = cbrt(0.088_302_461_9 * r + 0.281_718_837_6 * g + 0.629_978_700_5 * b)
        let lightness = 0.210_454_255_3 * l + 0.793_617_785_0 * m - 0.004_072_046_8 * s
        let a = 1.977_998_495_1 * l - 2.428_592_205_0 * m + 0.450_593_709_9 * s
        let bb = 0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766_0 * s
        var hue = atan2(bb, a)
        if hue < 0 { hue += 2 * .pi }
        return (lightness, (a * a + bb * bb).squareRoot(), hue)
    }

    /// The OKLCH color, or the closest one sRGB can show: chroma is lowered
    /// (lightness and hue kept) until every channel fits, so a deep shade of
    /// a vivid pick never clips into a different hue.
    public init(oklchLightness lightness: Double, chroma: Double, hue: Double, alpha: UInt8 = 255) {
        let lightness = min(max(lightness, 0), 1)
        func rgb(_ chroma: Double) -> (Double, Double, Double) {
            let a = chroma * cos(hue), b = chroma * sin(hue)
            let l = pow(lightness + 0.396_337_777_4 * a + 0.215_803_757_3 * b, 3)
            let m = pow(lightness - 0.105_561_345_8 * a - 0.063_854_172_8 * b, 3)
            let s = pow(lightness - 0.089_484_177_5 * a - 1.291_485_548_0 * b, 3)
            return (4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s,
                    -1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s,
                    -0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s)
        }
        func fits(_ c: (Double, Double, Double)) -> Bool {
            [c.0, c.1, c.2].allSatisfy { (-0.000_1...1.000_1).contains($0) }
        }
        var fitted = max(chroma, 0)
        if !fits(rgb(fitted)) {
            var low = 0.0, high = fitted
            for _ in 0..<24 {
                let mid = (low + high) / 2
                if fits(rgb(mid)) { low = mid } else { high = mid }
            }
            fitted = low
        }
        func byte(_ linear: Double) -> UInt8 {
            let c = min(max(linear, 0), 1)
            let encoded = c <= 0.003_130_8 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
            return UInt8((encoded * 255).rounded())
        }
        let (r, g, b) = rgb(fitted)
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
/// Each role has a single character used in sprite text grids: uppercase,
/// except `pupil` and `pumpkin`, which came after the uppercase letters ran
/// out and use lowercase letters no pattern zone has.
public enum PetPaletteRole: String, CaseIterable, Codable, Sendable {
    case outline
    case furBase
    case furShade
    case furAccent
    /// Second marking color (calico black patches, beagle saddle).
    case furSpot
    case belly
    /// The iris: the eye's own color (green, blue, copper, or dark brown).
    /// Closed and happy eye lines use it too, so they read on dark fur.
    case eye
    /// The dark center of an open eye. Without it a colored eye is a flat
    /// block of color that stares; with it every breed gets a soft, friendly
    /// look. Kept near-black for every breed.
    case pupil
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
    /// Leafy green: the frog hat, flower crown leaves.
    case leaf
    /// Warm brown leather: the cowboy hat.
    case leather
    /// Deep red folds and hems on heart-red cloth: the superhero cape.
    case crimson
    /// Pumpkin orange, with `leather` for the ribs: the Halloween items.
    case pumpkin

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
        // The alphabet ran out of uppercase letters; `i` is not a zone.
        case .pupil: "i"
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
        case .leaf: "F"
        case .leather: "I"
        case .crimson: "X"
        // Lowercase like `pupil`; `o` is not a zone.
        case .pumpkin: "o"
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

/// How one fur role follows a picked fur color: the pick moved toward
/// darker or lighter fur and softened in chroma, in OKLCH.
///
/// Steps are fractions of the room left between the pick and the darkest
/// (or lightest) fur tone, not fixed offsets, so a cream pick still gets
/// visible shading, a dark pick still gets stripes, and nothing clips to
/// pure black or white.
public struct PetFurTone: Hashable, Sendable {
    /// Negative is darker, positive lighter, as a fraction (-1...1) of the
    /// room toward `darkest` or `lightest`.
    public var step: Double
    /// Multiplies the pick's chroma: shades stay rich but never harsh,
    /// light tones turn soft and creamy.
    public var chroma: Double
    /// Highest lightness the tone may reach. Markings on white fur use it
    /// so a cream pick still shows as a patch.
    public var maxLightness: Double

    public init(step: Double, chroma: Double = 1, maxLightness: Double = PetFurTone.lightest) {
        self.step = min(max(step, -1), 1)
        self.chroma = max(chroma, 0)
        self.maxLightness = maxLightness
    }

    /// The pick itself (the main coat).
    public static let pick = PetFurTone(step: 0)

    /// The pick as a marking on white fur (calico patches, a pied French
    /// Bulldog): never so light that it melts into the white.
    public static let marking = PetFurTone(step: 0, maxLightness: 0.82)

    /// Shading, stripes, points: a deeper, slightly calmer version of the pick.
    public static func darker(_ amount: Double, chroma: Double = 0.9) -> PetFurTone {
        PetFurTone(step: -amount, chroma: chroma)
    }

    /// Feathering, pale muzzles and bellies: a lighter, softer version.
    public static func lighter(_ amount: Double, chroma: Double = 0.7) -> PetFurTone {
        PetFurTone(step: amount, chroma: chroma)
    }

    /// The darkest any derived fur gets (OKLab lightness): a deep brown or
    /// charcoal, never black, so markings never read as holes in the pet.
    public static let darkest = 0.27
    /// The lightest any derived fur gets: soft white, never a glare.
    public static let lightest = 0.97

    public func color(from pick: PetColor) -> PetColor {
        let base = pick.oklch
        var lightness = base.lightness
        if step < 0 {
            lightness += step * max(base.lightness - Self.darkest, 0)
        } else {
            lightness += step * max(Self.lightest - base.lightness, 0)
        }
        lightness = max(min(lightness, maxLightness, Self.lightest), Self.darkest)
        return PetColor(oklchLightness: lightness, chroma: base.chroma * chroma, hue: base.hue, alpha: pick.alpha)
    }
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

    /// The fur roles a fur tint may recolor (see `PetBreed.furTones`). Eyes,
    /// nose, and outline are never tinted, so every face stays readable.
    public static let tintableFurRoles: [PetPaletteRole] = [.furBase, .furShade, .furAccent, .furSpot, .belly]

    /// Overrides that recolor fur from one picked color: each role in
    /// `tones` becomes its tone of the pick, and every other role keeps this
    /// palette's color (white bibs stay white).
    public func furTint(_ pick: PetColor, tones: [PetPaletteRole: PetFurTone]) -> [PetPaletteRole: PetColor] {
        var overrides: [PetPaletteRole: PetColor] = [:]
        for role in Self.tintableFurRoles {
            if let tone = tones[role] { overrides[role] = tone.color(from: pick) }
        }
        return overrides
    }

    /// A copy whose outline stays visible on the black notch. Dark fur with a
    /// dark outline would vanish, so the outline becomes a soft light rim.
    /// Applied after user overrides, so recoloring a pet black is still safe.
    public func withVisibleRim() -> PetPalette {
        guard self[.furBase].luminance < PetPalette.darkFurThreshold,
              self[.outline].luminance < PetPalette.rimMinimumLuminance else { return self }
        var copy = self
        copy[.outline] = rim
        return copy
    }

    /// The light rim (and mouth color) for dark fur: the fur's own hue at a
    /// soft mid tone with little saturation. A fixed tan rim read as a harsh
    /// brown frame around a black cat; a rim in the coat's own hue reads as
    /// a gentle sheen on the fur while still parting it from the black notch.
    public var rim: PetColor {
        let fur = self[.furBase].hsl
        return PetColor(hue: fur.hue, saturation: min(fur.saturation, PetPalette.rimMaximumSaturation),
                        lightness: PetPalette.rimLightness)
    }

    /// Fur darker than this needs a rim (about #555 gray).
    static let darkFurThreshold = 0.09
    /// Outlines at least this bright already read on black.
    static let rimMinimumLuminance = 0.12
    static let rimLightness = 0.5
    static let rimMaximumSaturation = 0.14
    /// Fur around a mouth darker than this (on average) gets a rim-colored
    /// mouth instead of the dark one. It sits where both have about the same
    /// contrast against the fur, so a charcoal or chocolate coat keeps the
    /// crisp dark mouth and only near-black fur gets the light one.
    static let darkMouthBackground = 0.08

    /// Shared, breed-independent colors: eyes, effects, the default costume.
    /// They are the `basePalette` in `Pets/PetArt/breeds.json`.
    static let baseColors = PetArt.breeds.basePalette

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
