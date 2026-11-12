import CoreGraphics
import Foundation

/// The Radiant marker: a 9 by 9 four-pointed star pip on the corner of a
/// Closet tile once its item is upgraded. It is drawn like the Goals badges
/// (`BadgeArt`): the grid in `radiant.json` uses the badge slots (`C` rim,
/// `D` shade, `W` bright core, `L` highlight, `O` outline), colored from the
/// Gold badge palette by a plain lookup, with no dark-coat rim.
public enum RadiantMarkerArt {
    public static var size: Int { RadiantArt.shared.marker.count }

    public static var canvas: PetCanvas {
        let rows = RadiantArt.shared.marker
        var canvas = PetCanvas(width: rows.first?.count ?? 0, height: rows.count)
        canvas.stamp(SpriteGrid(art: rows.joined(separator: "\n")), x: 0, y: 0)
        return canvas
    }

    /// The marker's pixels as colors, row-major, nil for transparent.
    public static var colors: [PetColor?] {
        let palette = BadgePalette.palette(for: .tier(.gold))
        return canvas.pixels.map { $0.map { palette[$0] } }
    }

    /// The marker at a whole number of device pixels per sprite pixel.
    public static func image(scale: Int) -> CGImage? {
        let side = size, scale = max(1, scale)
        let width = side * scale
        var bytes = [UInt8](repeating: 0, count: width * width * 4)
        for (i, color) in colors.enumerated() {
            guard let color else { continue }
            let a = UInt16(color.alpha)
            let rgb = [color.red, color.green, color.blue].map { UInt8(UInt16($0) * a / 255) }
            for dy in 0..<scale {
                var offset = (((i / side) * scale + dy) * width + (i % side) * scale) * 4
                for _ in 0..<scale {
                    bytes[offset] = rgb[0]; bytes[offset + 1] = rgb[1]; bytes[offset + 2] = rgb[2]
                    bytes[offset + 3] = color.alpha
                    offset += 4
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
