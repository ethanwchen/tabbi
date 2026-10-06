import SwiftUI
import XCTest
import TabbiKitCore
import TabbiKit

/// `ImageRenderer` can't capture live materials, so the snapshots would hide
/// whether the Liquid Glass theme styles its cards at all. These renders
/// prove the painted glass (sheen and lit rim) is there where snapshots and
/// Reduce Transparency see it, and that Midnight stays flat.
@MainActor
final class GlassSurfaceRenderingTests: XCTestCase {
    override func tearDown() {
        Theme.apply(ThemeCatalog.midnight)
        super.tearDown()
    }

    func testLiquidGlassCardsArePaintedAsLitGlass() throws {
        let glass = try render(ThemeCatalog.liquidGlass)
        let flat = try render(ThemeCatalog.midnight)
        // Inside the card near the top: the sheen is clearly brighter than a flat card.
        XCTAssertGreaterThan(glass.brightness(x: 0.5, y: 0.15), flat.brightness(x: 0.5, y: 0.15) + 0.06)
        // The glass is lit from above: brighter at the top than the bottom.
        XCTAssertGreaterThan(glass.brightness(x: 0.5, y: 0.15), glass.brightness(x: 0.5, y: 0.85) + 0.04)
        // A flat card is the same all the way down.
        XCTAssertEqual(flat.brightness(x: 0.5, y: 0.15), flat.brightness(x: 0.5, y: 0.85), accuracy: 0.01)
    }

    private func render(_ theme: AppTheme) throws -> Bitmap {
        Theme.apply(theme)
        let view = Card { Color.clear.frame(width: 160, height: 80) }
            .padding(8)
            .background(Color.black)
            .environment(\.drawsLiquidGlass, false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(Bitmap(image))
    }
}

/// An RGBA copy of a rendered image, sampled at relative positions.
private struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        self.width = width
        self.height = height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        pixels = data
    }

    /// Mean of the RGB channels (0...1) at a point given as fractions of the
    /// width and height, measured from the top-left.
    func brightness(x: Double, y: Double) -> Double {
        let px = min(Int(Double(width) * x), width - 1)
        let py = min(Int(Double(height) * y), height - 1)
        let i = (py * width + px) * 4
        return (Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / (3 * 255)
    }
}
