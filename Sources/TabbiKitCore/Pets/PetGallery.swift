import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Contact sheets of every pet costume and animation, for reviewing pet art
/// changes without running the app (`--snapshot` writes them as
/// `pets-costumes.png` and `pets-animations.png`).
///
/// A sheet is plain data (rows of cells) so its layout can be tested, and
/// `render(scale:)` draws it with nearest-neighbor pixels on a dark ground
/// like the notch's.
public struct PetGallery: Hashable, Sendable {
    /// One frame in a sheet.
    public struct Cell: Hashable, Sendable {
        public var canvas: PetCanvas
        public var palette: PetPalette
        /// Seconds the frame stays on screen, drawn as a bar under the cell
        /// so timing can be read off the sheet; nil for still poses.
        public var duration: TimeInterval?
        /// Whether the frame belongs to a looping clip (the bar's color).
        public var loops: Bool

        public init(canvas: PetCanvas, palette: PetPalette, duration: TimeInterval? = nil, loops: Bool = false) {
            self.canvas = canvas
            self.palette = palette
            self.duration = duration
            self.loops = loops
        }
    }

    /// Rows of cells; `groupSize` rows in a row make one group, set apart by
    /// a wider gap (one animation's breeds, for example).
    public var rows: [[Cell]]
    public var groupSize: Int

    public init(rows: [[Cell]], groupSize: Int = 1) {
        self.rows = rows
        self.groupSize = max(1, groupSize)
    }

    /// One breed per body shape, in `PetBodyShape` order, so every
    /// silhouette and anchor set shows once.
    public static var bodyShapeBreeds: [PetBreed] {
        PetBodyShape.allCases.compactMap { shape in PetBreed.allCases.first { $0.bodyShape == shape } }
    }

    /// Every look a sheet column shows: bare, then each outfit, then each
    /// accessory on its own.
    public static var looks: [(outfit: PetOutfit, accessories: [PetAccessory])] {
        PetOutfit.allCases.map { ($0, []) } + PetAccessory.allCases.map { (.none, [$0]) }
    }

    /// Dressed in one item per slot, so the animation sheet shows an outfit,
    /// a neck item, glasses and a hat following every frame together.
    public static let dressedLooks: [(breed: PetBreed, outfit: PetOutfit, accessories: [PetAccessory])] = [
        (.orangeTabby, .superheroCape, [.bowTie, .roundGlasses, .partyHat]),
        (.goldenRetriever, .cozyHoodie, [.scarf, .coolSunglasses, .wizardHat]),
    ]

    /// Rows are body shapes, columns are `looks`, all sitting.
    public static func costumes() -> PetGallery {
        PetGallery(rows: bodyShapeBreeds.map { breed in
            looks.map { look in
                Cell(canvas: PetComposer.sitting(breed, outfit: look.outfit, accessories: look.accessories),
                     palette: breed.palette)
            }
        })
    }

    /// One group per animation (in `PetAnimation` order), a row per dressed
    /// look, a column per frame with its duration bar.
    public static func animations() -> PetGallery {
        let rows = PetAnimation.allCases.flatMap { animation in
            dressedLooks.map { look in
                let clip = PetComposer.clip(animation, for: look.breed, outfit: look.outfit,
                                            accessories: look.accessories)
                return clip.frames.map { frame in
                    Cell(canvas: frame.canvas, palette: look.breed.palette, duration: frame.duration,
                         loops: clip.loops)
                }
            }
        }
        return PetGallery(rows: rows, groupSize: dressedLooks.count)
    }

    // MARK: Drawing

    private static let gap = 4
    private static let groupGap = 12
    /// Height of a duration bar and the space above it, in image pixels.
    private static let barHeight = 2
    private static let barSpacing = 2

    private var hasTiming: Bool { rows.contains { $0.contains { $0.duration != nil } } }

    /// The rendered size for `scale` image pixels per sprite pixel.
    public func size(scale: Int) -> (width: Int, height: Int) {
        let cell = PetComposer.frameSize * max(1, scale)
        let rowHeight = cell + (hasTiming ? Self.barSpacing + Self.barHeight : 0)
        let columns = rows.map(\.count).max() ?? 0
        let groups = (rows.count + groupSize - 1) / groupSize
        let gaps = max(0, rows.count - groups) * Self.gap + max(0, groups - 1) * Self.groupGap
        return (columns * cell + max(0, columns - 1) * Self.gap + 2 * Self.gap,
                rows.count * rowHeight + gaps + 2 * Self.gap)
    }

    /// Draws the sheet. Each cell sits on a slightly lighter square so
    /// pixels that touch the frame edge show; a duration bar is one cell
    /// wide per second (capped at the cell), green for loops and amber for
    /// one-shot clips.
    public func render(scale: Int = 2) -> CGImage? {
        let scale = max(1, scale)
        let (width, height) = size(scale: scale)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cell = PetComposer.frameSize * scale
        let rowHeight = cell + (hasTiming ? Self.barSpacing + Self.barHeight : 0)
        var top = Self.gap
        for (index, row) in rows.enumerated() {
            if index > 0 { top += index % groupSize == 0 ? Self.groupGap : Self.gap }
            for (column, item) in row.enumerated() {
                let x = Self.gap + column * (cell + Self.gap)
                // CoreGraphics counts y up from the bottom.
                let frame = CGRect(x: x, y: height - top - cell, width: cell, height: cell)
                context.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1))
                context.fill(frame)
                if let image = PetRenderer.render(item.canvas, palette: item.palette, scale: scale) {
                    context.draw(image, in: frame)
                }
                if let duration = item.duration {
                    let length = max(1, min(cell, Int((duration * Double(cell)).rounded())))
                    context.setFillColor(item.loops
                        ? CGColor(srgbRed: 0.40, green: 0.80, blue: 0.50, alpha: 1)
                        : CGColor(srgbRed: 0.95, green: 0.70, blue: 0.30, alpha: 1))
                    context.fill(CGRect(x: x, y: height - top - cell - Self.barSpacing - Self.barHeight,
                                        width: length, height: Self.barHeight))
                }
            }
            top += rowHeight
        }
        return context.makeImage()
    }

    /// PNG data for `render(scale:)`.
    public func png(scale: Int = 2) -> Data? {
        guard let image = render(scale: scale) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
