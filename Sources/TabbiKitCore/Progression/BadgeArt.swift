import CoreGraphics
import Foundation

/// The Goals badges, drawn in the pet's sprite language: a 28 by 28 grid
/// per tier (`Pets/PetArt/badge.json`, format `pets.v1`) and one 9 by 9
/// glyph per track, stamped on the tier frame's inner disc and colored
/// through a per-tier `BadgePalette`, so one glyph serves every tier the
/// way one costume serves every breed. docs/design/progression.md and
/// `runs/progression/badges-v4/spec.md` (direction A) describe the look.
///
/// The frames carry their outline as drawn and approved (the medal's dark
/// ring and the one pixel line around the rosette, laurel and sparkles),
/// and the colors are a plain role lookup: the pet's lit rim for dark coats
/// is not applied, so the quiet "not yet" coin keeps its dim outline.
public enum BadgeArt {
    /// The grid's side, in sprite pixels.
    public static let size = 28
    /// Points per sprite pixel on the compact and regular panels (42 pt).
    public static let regularPixelSize: CGFloat = 1.5
    /// Points per sprite pixel on the large panel (56 pt).
    public static let largePixelSize: CGFloat = 2
    /// Seconds between the Starlight sparkle's two frames.
    public static let twinkleInterval: TimeInterval = 1.5

    /// The badge's state: a tier reached, or none yet.
    public enum State: Hashable, Sendable, CaseIterable {
        case notYet
        case tier(ProgressTier)

        public static var allCases: [State] { [.notYet] + ProgressTier.allCases.map(State.tier) }

        public init(_ tier: ProgressTier?) { self = tier.map(State.tier) ?? .notYet }

        /// The frame's name in `badge.json`, and the fixture's state name.
        public var name: String {
            switch self {
            case .notYet: "notYet"
            case .tier(.bronze): "bronze"
            case .tier(.silver): "silver"
            case .tier(.gold): "gold"
            case .tier(.starlight): "starlight"
            }
        }

        var frameName: String { "frame" + name.prefix(1).uppercased() + name.dropFirst() }

        /// Where the glyph's top-left corner lands: the inner disc's origin.
        /// The silver medal sits two pixels higher to make room for its
        /// ribbon tails.
        var glyphOrigin: (x: Int, y: Int) { self == .tier(.silver) ? (10, 8) : (10, 10) }
    }

    /// The composed badge: the tier's frame with the track's glyph on it.
    /// `twinkle` picks the Starlight sparkle's second frame (the four point
    /// sparkle shrinks to a dot while the upper left dot grows); other
    /// states have one frame.
    public static func canvas(track: ProgressTrack, state: State, twinkle: Bool = false) -> PetCanvas {
        var canvas = PetCanvas(width: size, height: size)
        let frame = state == .tier(.starlight) && twinkle ? "frameStarlightTwinkle" : state.frameName
        canvas.stamp(PetArt.badge.grid(frame), x: 0, y: 0)
        let origin = state.glyphOrigin
        canvas.stamp(PetArt.badge.grid(glyphName(track)), x: origin.x, y: origin.y)
        return canvas
    }

    static func glyphName(_ track: ProgressTrack) -> String {
        "glyph" + track.rawValue.prefix(1).uppercased() + track.rawValue.dropFirst()
    }

    /// The badge's pixels as colors, row-major, nil for transparent.
    public static func colors(track: ProgressTrack, state: State, twinkle: Bool = false) -> [PetColor?] {
        let palette = BadgePalette.palette(for: state)
        return canvas(track: track, state: state, twinkle: twinkle).pixels.map { $0.map { palette[$0] } }
    }

    /// The badge as a crisp image at a whole number of device pixels per
    /// sprite pixel, cached like pet frames.
    public static func image(track: ProgressTrack, state: State, twinkle: Bool = false, scale: Int) -> CGImage? {
        BadgeImageCache.shared.image(track: track, state: state, twinkle: twinkle, scale: max(1, scale))
    }

    /// Whole device pixels per sprite pixel for a panel: 1.5 pt (or 2 pt on
    /// the large panel) times the display scale; on a 1x display, 1 pt per
    /// sprite pixel rather than a fractional scale, so the art stays crisp.
    public static func scale(pixelSize: CGFloat, displayScale: CGFloat) -> Int {
        let exact = pixelSize * displayScale
        return exact == exact.rounded() ? Int(exact) : max(1, Int(displayScale.rounded()))
    }
}

/// The colors each badge state fills the frame and glyph roles with. The
/// grids use the costume roles as slots: `C` the rim, `D` its lower right
/// shade, `U` the inner disc, `W` the glyph, `L` the two pixel highlight,
/// `O` the outline, `F` and `S` the laurel leaves, `Z` the sparkles.
public enum BadgePalette {
    public struct Colors: Hashable, Sendable {
        public var rim: PetColor
        public var shade: PetColor
        public var inner: PetColor
        public var glyph: PetColor
        public var light: PetColor
        public var outline: PetColor
    }

    public static let leaf = PetColor(hex: "#6CC46A")!
    public static let leafShade = PetColor(hex: "#4C9A4B")!
    public static let sparkle = PetColor(hex: "#F4F1FF")!

    public static func colors(for state: BadgeArt.State) -> Colors {
        func hex(_ rim: String, _ shade: String, _ inner: String, _ glyph: String, _ light: String,
                 _ outline: String) -> Colors {
            Colors(rim: PetColor(hex: rim)!, shade: PetColor(hex: shade)!, inner: PetColor(hex: inner)!,
                   glyph: PetColor(hex: glyph)!, light: PetColor(hex: light)!, outline: PetColor(hex: outline)!)
        }
        switch state {
        case .notYet: return hex("#2B2B30", "#232327", "#18181B", "#4A4A50", "#35353A", "#0D0D0F")
        case .tier(.bronze): return hex("#D9945C", "#A8683A", "#8E5530", "#FFF1DC", "#F2C49A", "#2A1A14")
        case .tier(.silver): return hex("#C7D1DE", "#8E9BAB", "#6F7C8C", "#FFFFFF", "#F6F8FB", "#2A1A14")
        case .tier(.gold): return hex("#F2C14E", "#C98A2A", "#A86E1E", "#FFF7D6", "#FFE9A6", "#2A1A14")
        case .tier(.starlight): return hex("#BDA8FF", "#7C63C8", "#5B47A6", "#FFFFFF", "#F4F1FF", "#2A1A14")
        }
    }

    /// A pet palette with the state's colors in the badge slots.
    public static func palette(for state: BadgeArt.State) -> PetPalette {
        let colors = colors(for: state)
        return PetPalette([
            .costumeBase: colors.rim, .costumeShade: colors.shade, .coat: colors.inner, .belly: colors.glyph,
            .eyeLight: colors.light, .outline: colors.outline, .leaf: leaf, .furShade: leafShade, .effect: sparkle,
        ])
    }
}

/// Rendered badges, one per track, state, sparkle frame and scale: 120 at
/// most per scale, so everything stays cached.
final class BadgeImageCache: @unchecked Sendable {
    private struct Key: Hashable {
        let track: ProgressTrack
        let state: BadgeArt.State
        let twinkle: Bool
        let scale: Int
    }

    static let shared = BadgeImageCache()
    private let lock = NSLock()
    private var cache: [Key: CGImage] = [:]

    func image(track: ProgressTrack, state: BadgeArt.State, twinkle: Bool, scale: Int) -> CGImage? {
        let key = Key(track: track, state: state, twinkle: twinkle, scale: scale)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        let colors = BadgeArt.colors(track: track, state: state, twinkle: twinkle)
        guard let image = Self.render(colors, side: BadgeArt.size, scale: scale) else { return nil }
        lock.lock(); defer { lock.unlock() }
        cache[key] = image
        return image
    }

    /// Premultiplied RGBA, every sprite pixel an exact `scale` block, like
    /// `PetRenderer.render`.
    private static func render(_ colors: [PetColor?], side: Int, scale: Int) -> CGImage? {
        let width = side * scale, height = side * scale
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for sy in 0..<side {
            for sx in 0..<side {
                guard let color = colors[sy * side + sx] else { continue }
                let a = UInt16(color.alpha)
                let premultiplied = [color.red, color.green, color.blue].map { UInt8(UInt16($0) * a / 255) }
                for dy in 0..<scale {
                    var offset = ((sy * scale + dy) * width + sx * scale) * 4
                    for _ in 0..<scale {
                        bytes[offset] = premultiplied[0]
                        bytes[offset + 1] = premultiplied[1]
                        bytes[offset + 2] = premultiplied[2]
                        bytes[offset + 3] = color.alpha
                        offset += 4
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
