import CoreGraphics
import ImageIO
import XCTest
@testable import TabbiKitCore

/// Album covers are decoded at the size Now Playing draws them, and their
/// glow color is read without Core Image, which once took a new `CIContext`
/// per track and peaked at about 200 MB over a playlist.
final class ArtworkThumbnailTests: XCTestCase {
    func testLargeCoverDecodesAtThePanelSize() throws {
        let thumbnail = try XCTUnwrap(ArtworkThumbnail(data: Self.jpeg(width: 3000, height: 3000)))
        XCTAssertEqual(thumbnail.image.width, ArtworkThumbnail.maxPixelSize)
        XCTAssertEqual(thumbnail.image.height, ArtworkThumbnail.maxPixelSize)
    }

    func testWideCoverKeepsItsShape() throws {
        let thumbnail = try XCTUnwrap(ArtworkThumbnail(data: Self.jpeg(width: 1200, height: 600)))
        XCTAssertEqual(thumbnail.image.width, ArtworkThumbnail.maxPixelSize)
        XCTAssertEqual(thumbnail.image.height, ArtworkThumbnail.maxPixelSize / 2)
    }

    func testSmallCoverIsNotScaledUp() throws {
        let thumbnail = try XCTUnwrap(ArtworkThumbnail(data: Self.jpeg(width: 100, height: 100)))
        XCTAssertEqual(thumbnail.image.width, 100)
    }

    func testNonImageDataIsRejected() {
        XCTAssertNil(ArtworkThumbnail(data: Data("not an image".utf8)))
    }

    func testAverageColorOfASolidCoverIsThatColor() throws {
        let thumbnail = try XCTUnwrap(ArtworkThumbnail(data: Self.jpeg(width: 640, height: 640) { context, size in
            context.setFillColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
        }))
        XCTAssertEqual(thumbnail.averageColor.red, 0.8, accuracy: 0.02)
        XCTAssertEqual(thumbnail.averageColor.green, 0.2, accuracy: 0.02)
        XCTAssertEqual(thumbnail.averageColor.blue, 0.4, accuracy: 0.02)
    }

    func testAverageColorWeighsTheWholeCover() throws {
        // Left half black, right half white: the mean is mid gray.
        let thumbnail = try XCTUnwrap(ArtworkThumbnail(data: Self.jpeg(width: 1000, height: 1000) { context, size in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        }))
        for channel in [thumbnail.averageColor.red, thumbnail.averageColor.green, thumbnail.averageColor.blue] {
            XCTAssertEqual(channel, 0.5, accuracy: 0.04)
        }
    }

    /// A playlist's worth of big covers must not grow the app the way one
    /// `CIContext` per cover did (190 to 270 MB at the peak).
    func testDecodingManyLargeCoversKeepsMemoryBounded() throws {
        let covers = (0..<12).map { Self.jpeg(width: 2400, height: 2400, seed: $0) }
        let sampler = FootprintSampler()
        var kept: [ArtworkThumbnail] = []
        for cover in covers {
            try autoreleasepool { kept.append(try XCTUnwrap(ArtworkThumbnail(data: cover))) }
        }
        let growth = sampler.stop()
        XCTAssertEqual(kept.count, covers.count)
        XCTAssertLessThan(growth, 40 << 20, "decoding 12 covers grew the footprint by \(growth >> 20) MB")
    }

    /// A JPEG of `width` by `height`, drawn by `draw` or as colored blobs.
    private static func jpeg(width: Int, height: Int, seed: Int = 0,
                             draw: ((CGContext, CGSize) -> Void)? = nil) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let size = CGSize(width: width, height: height)
        if let draw {
            draw(context, size)
        } else {
            var state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 | 1
            for _ in 0..<60 {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                context.setFillColor(red: CGFloat(state & 0xFF) / 255, green: CGFloat((state >> 8) & 0xFF) / 255,
                                     blue: CGFloat((state >> 16) & 0xFF) / 255, alpha: 1)
                context.fillEllipse(in: CGRect(x: CGFloat((state >> 24) % UInt64(width)),
                                               y: CGFloat((state >> 40) % UInt64(height)),
                                               width: size.width / 4, height: size.height / 4))
            }
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!,
                                   [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
