import CoreGraphics
import Foundation
import ImageIO
import TabbiKitCore
import UniformTypeIdentifiers

/// Review sheets for the Closet's Goals badges (`BadgeArt`):
/// `swift run PetGallery out/ badges` writes every track at every state at
/// the regular panel's 3 device pixels per sprite pixel (`badges-1x.png`),
/// at 12 (`badges-4x.png`), and at 3 on a Strawberry Milk card
/// (`badges-sweet-1x.png`), so the quiet coin's visibility on a Sweet card
/// can be checked.
enum BadgeSheets {
    static func write(to directory: URL) throws {
        let black = CGColor(red: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1)
        let sweet = CGColor(red: 79 / 255, green: 52 / 255, blue: 64 / 255, alpha: 1)
        try sheet(scale: 3, card: black, to: directory.appendingPathComponent("badges-1x.png"))
        try sheet(scale: 12, card: black, to: directory.appendingPathComponent("badges-4x.png"))
        try sheet(scale: 3, card: sweet, to: directory.appendingPathComponent("badges-sweet-1x.png"))
    }

    private static func sheet(scale: Int, card: CGColor, to url: URL) throws {
        let states = BadgeArt.State.allCases
        let side = BadgeArt.size * scale, pad = 4 * scale, label = 150, header = 28
        let cell = side + pad * 2
        let width = label + cell * states.count + 16, height = header + cell * ProgressTrack.allCases.count + 16
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GalleryError.context }
        context.interpolationQuality = .none
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(card)
        context.fill(CGRect(x: label, y: 0, width: cell * states.count + 16, height: height - header))
        func flip(_ y: Int, _ h: Int) -> Int { height - y - h }
        for (column, state) in states.enumerated() {
            draw(state.name, size: 12, color: CGColor(gray: 1, alpha: 0.8),
                 at: CGPoint(x: label + 8 + column * cell + 4, y: flip(8, 12)), in: context)
        }
        for (row, track) in ProgressTrack.allCases.enumerated() {
            let y = header + row * cell
            draw(track.rawValue, size: 12, color: CGColor(gray: 1, alpha: 0.8),
                 at: CGPoint(x: 8, y: flip(y + cell / 2, 12)), in: context)
            for (column, state) in states.enumerated() {
                guard let image = BadgeArt.image(track: track, state: state, scale: scale) else { continue }
                context.draw(image, in: CGRect(x: label + 8 + column * cell + pad, y: flip(y + pad, side),
                                               width: side, height: side))
            }
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GalleryError.encode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
        print("wrote \(url.path)")
    }
}
