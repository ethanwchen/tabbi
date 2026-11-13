import CoreGraphics
import Foundation

extension PetArt {
    /// The Study Level rank emblems (`RankArt`), one grid per named rank and
    /// the small star that rings Galaxy II and up.
    static let rank = load("rank")
}

/// The rank emblems, drawn in the pet's sprite language like the Goals
/// badges (`BadgeArt`): a 16 by 16 grid per named rank in
/// `Pets/PetArt/rank.json` (format `pets.v1`), stamped one pixel in from
/// the edge of an 18 by 18 canvas and colored through the rank's own
/// `RankPalette`. Galaxy II and up add one small gold star per numeral in
/// the free corners (up to four), so every rank past Nebula still looks
/// its own while the title keeps counting.
///
/// The grids carry their outline as drawn, and colors are a plain role
/// lookup, so the Mac and the Windows port draw the same pixels
/// (`shared/fixtures/progression/levels.json`).
public enum RankArt {
    /// The canvas side, in sprite pixels.
    public static let size = 18
    /// The emblem's own grid side, stamped at (1, 1).
    public static let emblemSize = 16
    /// The most stars around the Galaxy emblem (from Galaxy V on).
    public static let maxPips = 4
    /// Where each star sits, centered in a corner the round emblem leaves
    /// free, in the order they are added: top right, top left, bottom
    /// left, bottom right. Each is the top-left corner of the 3 by 3 star.
    static let pipOrigins: [(x: Int, y: Int)] = [(15, 0), (0, 0), (0, 15), (15, 15)]

    static func gridName(_ tier: StudyRank.Tier) -> String {
        "emblem" + tier.rawValue.prefix(1).uppercased() + tier.rawValue.dropFirst()
    }

    /// The composed emblem: the tier's grid and the rank's stars.
    public static func canvas(_ rank: StudyRank) -> PetCanvas {
        var canvas = PetCanvas(width: size, height: size)
        canvas.stamp(PetArt.rank.grid(gridName(rank.tier)), x: 1, y: 1)
        for origin in pipOrigins.prefix(rank.pips) {
            canvas.stamp(PetArt.rank.grid("pip"), x: origin.x, y: origin.y)
        }
        return canvas
    }

    /// The emblem's pixels as colors, row-major, nil for transparent.
    public static func colors(_ rank: StudyRank) -> [PetColor?] {
        let palette = RankPalette.palette(for: rank.tier)
        return canvas(rank).pixels.map { $0.map { palette[$0] } }
    }

    /// The emblem as a crisp image at a whole number of device pixels per
    /// sprite pixel, cached.
    public static func image(_ rank: StudyRank, scale: Int) -> CGImage? {
        RankImageCache.shared.image(rank, scale: max(1, scale))
    }

    /// Whole device pixels per sprite pixel for `pixelSize` points on a
    /// display: a fractional product falls back to the display's own scale,
    /// as the badges do, so the art never blurs.
    public static func scale(pixelSize: CGFloat, displayScale: CGFloat) -> Int {
        BadgeArt.scale(pixelSize: pixelSize, displayScale: displayScale)
    }
}

/// The colors each rank fills its emblem's roles with. The grids use
/// costume roles as slots: `O` the outline, `C` the body, `D` its lower
/// right shade, `W` the bright core or swirl, `L` the highlight, `Y` the
/// hottest point (the Galaxy's gold core), `T` a second color (the comet's
/// tail, the nebula's pink) and `Z` the sparkles. Galaxy's stars are gold
/// (`Y`) around a white center (`Z`).
public enum RankPalette {
    public struct Colors: Hashable, Sendable {
        public var outline, body, shade, core, light, hot, second, sparkle: PetColor
    }

    public static func colors(for tier: StudyRank.Tier) -> Colors {
        func hex(_ outline: String, _ body: String, _ shade: String, _ core: String, _ light: String,
                 _ hot: String, _ second: String, _ sparkle: String) -> Colors {
            Colors(outline: PetColor(hex: outline)!, body: PetColor(hex: body)!, shade: PetColor(hex: shade)!,
                   core: PetColor(hex: core)!, light: PetColor(hex: light)!, hot: PetColor(hex: hot)!,
                   second: PetColor(hex: second)!, sparkle: PetColor(hex: sparkle)!)
        }
        switch tier {
        case .spark: return hex("#2A1A14", "#FFD66B", "#E0A23A", "#FFF3C4", "#FFF8E1", "#FFFFFF", "#FFD66B", "#FFF3C4")
        case .ember: return hex("#2A1A14", "#FF8A3D", "#D2452A", "#FFC94D", "#FFB27A", "#FFF4D6", "#FF8A3D", "#FFF3C4")
        case .comet: return hex("#14202A", "#8FD8FF", "#4A9BD6", "#F2FBFF", "#DFF5FF", "#FFFFFF", "#5FB8F0", "#FFFFFF")
        case .nova: return hex("#2A1420", "#FF9BD2", "#D45C9E", "#FFE3F2", "#FFD0EA", "#FFFFFF", "#FF9BD2", "#FFFFFF")
        case .nebula: return hex("#1C1430", "#A88BFF", "#6E54C8", "#EDE6FF", "#D9CCFF", "#FFFFFF", "#FF9BD2", "#F4F1FF")
        case .galaxy: return hex("#0E1030", "#4654C8", "#2E3790", "#C8D0FF", "#DDE2FF", "#FFD66B", "#4654C8", "#FFFFFF")
        }
    }

    /// A pet palette with the rank's colors in the emblem slots.
    public static func palette(for tier: StudyRank.Tier) -> PetPalette {
        let colors = colors(for: tier)
        return PetPalette([
            .outline: colors.outline, .costumeBase: colors.body, .costumeShade: colors.shade, .belly: colors.core,
            .eyeLight: colors.light, .gold: colors.hot, .costumeTrim: colors.second,
            .effect: colors.sparkle,
        ])
    }
}

/// Rendered emblems by rank and scale. Ranks past Galaxy V look alike, so
/// the cache keys on the tier and the stars shown, which keeps it small.
final class RankImageCache: @unchecked Sendable {
    private struct Key: Hashable {
        let tier: StudyRank.Tier
        let pips: Int
        let scale: Int
    }

    static let shared = RankImageCache()
    private let lock = NSLock()
    private var cache: [Key: CGImage] = [:]

    func image(_ rank: StudyRank, scale: Int) -> CGImage? {
        let key = Key(tier: rank.tier, pips: rank.pips, scale: scale)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()
        guard let image = SpriteImage.render(RankArt.colors(rank), width: RankArt.size, height: RankArt.size,
                                             scale: scale) else { return nil }
        lock.lock(); defer { lock.unlock() }
        cache[key] = image
        return image
    }
}

/// Draws sprite colors as a premultiplied RGBA image, every sprite pixel an
/// exact `scale` block, never interpolated, like `PetRenderer.render`.
enum SpriteImage {
    static func render(_ colors: [PetColor?], width side: Int, height: Int, scale: Int) -> CGImage? {
        let width = side * scale, pixelHeight = height * scale
        var bytes = [UInt8](repeating: 0, count: width * pixelHeight * 4)
        for sy in 0..<height {
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
        return CGImage(width: width, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
