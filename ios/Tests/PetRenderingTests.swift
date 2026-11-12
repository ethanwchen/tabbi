import CoreGraphics
import Foundation
import Testing
import TabbiKitCore
@testable import TabbiPhone

/// The iPhone draws the same pixels as the Mac: every bare breed's sitting
/// frame, rendered by the shared `PetRenderer` at the whole-pixel scale the
/// app uses, matches `shared/fixtures/pets/rendered.json` pixel for pixel.
@Suite struct PetRenderingTests {
    struct RenderedFile: Decodable {
        struct Dress: Decodable {
            let breed: String
            let outfit: String
            let accessories: [String]
        }

        struct Frame: Decodable {
            let dress: Dress
            let furTint: String?
            let colors: [String]
            let rle: String
        }

        let schema: String
        let frameSize: Int
        let frames: [Frame]
    }

    static let file: RenderedFile? = try? Fixtures.decode(RenderedFile.self, from: "rendered")

    /// The bare breeds in their own colors.
    static var bareBreeds: [String] {
        (file?.frames ?? []).filter { $0.furTint == nil && $0.dress.outfit == "none" && $0.dress.accessories.isEmpty }
            .map(\.dress.breed)
    }

    @Test func fixtureCoversEveryBreed() throws {
        let file = try #require(Self.file)
        #expect(file.schema == "tabbi.pets.golden")
        #expect(file.frameSize == PetComposer.frameSize)
        #expect(Set(Self.bareBreeds) == Set(PetBreed.allCases.map(\.rawValue)))
    }

    @Test(arguments: Self.bareBreeds)
    func sittingFrameMatchesTheFixture(_ breedName: String) throws {
        let frame = try #require(Self.file?.frames.first {
            $0.dress.breed == breedName && $0.furTint == nil && $0.dress.outfit == "none" && $0.dress.accessories.isEmpty
        })
        let breed = try #require(PetBreed(rawValue: breedName))
        let profile = PetProfile(name: "", breed: breed)
        // The app's hero pet: 6 points per sprite pixel on a 3x screen.
        let scale = PixelPet.devicePixels(per: 6, displayScale: 3)
        #expect(scale == 18)
        let image = try #require(PetRenderer.render(profile.sittingCanvas(), palette: profile.palette, scale: scale))
        #expect(image.width == 32 * scale && image.height == 32 * scale)
        let pixels = try #require(Self.rgba(image))

        let rows = Self.decodeRunLength(frame.rle)
        #expect(rows.count == 32)
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        for (y, row) in rows.enumerated() {
            for (x, symbol) in row.enumerated() {
                // Every device pixel of the sprite pixel's square is the same
                // color: check two opposite corners.
                for (dx, dy) in [(0, 0), (scale - 1, scale - 1)] {
                    let offset = ((y * scale + dy) * image.width + x * scale + dx) * 4
                    let alpha = pixels[offset + 3]
                    if symbol == "." {
                        #expect(alpha == 0, "\(breedName) (\(x), \(y)) should be clear")
                    } else {
                        let index = try #require(letters.firstIndex(of: symbol))
                        let expected = try #require(PetColor(hex: frame.colors[index]))
                        let hex = String(format: "#%02X%02X%02X", pixels[offset], pixels[offset + 1], pixels[offset + 2])
                        #expect(alpha == 255 && hex == expected.hex, "\(breedName) (\(x), \(y)): \(hex) is not \(expected.hex)")
                    }
                }
            }
        }
    }

    @Test func pixelSizesSnapToWholeDevicePixels() {
        #expect(PixelPet.devicePixels(per: 6, displayScale: 3) == 18)
        #expect(PixelPet.devicePixels(per: 6, displayScale: 2) == 12)
        #expect(PixelPet.devicePixels(per: 1, displayScale: 3) == 3)
        // A fractional size rounds down to whole device pixels, never below one.
        #expect(PixelPet.devicePixels(per: 0.9, displayScale: 3) == 2)
        #expect(PixelPet.devicePixels(per: 0.1, displayScale: 2) == 1)
    }

    @Test func trimmingKeepsThePetsPixels() {
        let canvas = PetProfile.starter(.cat).sittingCanvas()
        let trimmed = canvas.trimmed(margin: 1)
        let bounds = canvas.opaqueBounds!
        #expect(trimmed.width == bounds.maxX - bounds.minX + 3)
        #expect(trimmed.height <= canvas.height)
        #expect(trimmed.pixels.compactMap { $0 }.count == canvas.pixels.compactMap { $0 }.count)
    }

    /// The image's premultiplied RGBA bytes, read back as drawn.
    static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        // A bitmap context's first row is the image's top row.
        return drawn ? bytes : nil
    }

    /// Run-length rows as the fixture writes them (shared/fixtures/pets/README.md).
    static func decodeRunLength(_ text: String) -> [String] {
        text.split(separator: "/", omittingEmptySubsequences: false).map { row in
            var out = "", count = ""
            for character in row {
                if character.isNumber {
                    count.append(character)
                } else {
                    out += String(repeating: character, count: Int(count) ?? 1)
                    count = ""
                }
            }
            return out
        }
    }
}
