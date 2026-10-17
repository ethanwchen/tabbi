import CoreGraphics
import Foundation
import ImageIO

/// An album cover decoded at the size Now Playing draws it, plus its mean
/// color for the panel's glow.
///
/// Covers arrive far larger than they show: Spotify's are 640 pixels, and a
/// Music track's embedded art is often 1400 to 3000. The panel draws one at
/// 112 points at most (`maxPixelSize`), so the cover is decoded straight to
/// that size with ImageIO and never exists at full size in memory. The mean
/// color is read from that small picture with Core Graphics. It used to come
/// from Core Image's `CIAreaAverage` on the full cover, with a new
/// `CIContext` for every track: that took about 190 to 270 MB at its peak
/// over a playlist and left tens of megabytes behind.
public struct ArtworkThumbnail: @unchecked Sendable {
    /// The cover, at most `maxPixelSize` on its long edge.
    public let image: CGImage
    /// Mean red, green and blue of the cover, each 0...1 (sRGB).
    public let averageColor: (red: Double, green: Double, blue: Double)

    /// The panel's 112 point cover on a 2x screen at the Large panel size
    /// (9/8), rounded up. The closed notch's 20 point cover uses the same.
    public static let maxPixelSize = 256

    /// Decodes `data` (any format ImageIO reads), or nil when it isn't an
    /// image.
    public init?(data: Data, maxPixelSize: Int = ArtworkThumbnail.maxPixelSize) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              let color = Self.averageColor(of: image)
        else { return nil }
        self.image = image
        averageColor = color
    }

    /// Side of the grid the cover is shrunk to before averaging: large
    /// enough that the shrink is a fair box filter, small enough to sum in
    /// no time.
    private static let averagingSide = 16

    /// The mean of the cover's pixels, by shrinking it onto a small grid
    /// and averaging that. Transparent pixels count for nothing.
    static func averageColor(of image: CGImage) -> (red: Double, green: Double, blue: Double)? {
        let side = averagingSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var red = 0, green = 0, blue = 0, alpha = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[index])
            green += Int(pixels[index + 1])
            blue += Int(pixels[index + 2])
            alpha += Int(pixels[index + 3])
        }
        // Premultiplied, so dividing by the summed alpha un-premultiplies.
        guard alpha > 0 else { return (0, 0, 0) }
        let total = Double(alpha)
        return (Double(red) / total, Double(green) / total, Double(blue) / total)
    }
}
