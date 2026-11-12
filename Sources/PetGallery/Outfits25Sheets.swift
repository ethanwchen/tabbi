import CoreGraphics
import ImageIO
import Foundation
import TabbiKitCore
import UniformTypeIdentifiers

/// Review sheets for the 25 candidate outfits of the closet round after the
/// mastery outfits: `swift run PetGallery out/ outfits25`.
///
/// - `outfit-<slug>.png`: the item on a spread of breeds that covers every
///   body shape and the dark coats, sitting, in a celebration hop, walking,
///   stretching and napping, at 4x.
/// - `all-<breed>.png` and `all-<breed>-2x.png`: every candidate on one
///   breed, at 4x and at the closed notch's 2x.
/// - `loop-<slug>.png`: each tick of an animated item's loop, sitting and
///   walking, on every body shape.
/// - `cards/<nn>-<slug>-<bsh|black>[-2x].png`: one candidate alone on the
///   British Shorthair or the black cat, idle, at 4x and 2x, for the
///   review page.
///
/// `swift run PetGallery out/ outfits25 dump <item id>` prints the
/// composed frames as palette symbols instead, for drawing new grids.
enum Outfits25Sheets {
    /// The candidates in review order, each one item (a set is an outfit
    /// with a head part).
    static let candidates: [PetItem] = [
        .accessory(.mushroomCap), .accessory(.deerstalker), .accessory(.cactusPot), .accessory(.bookStack),
        .accessory(.strawberryCap), .accessory(.sunHat), .accessory(.aviatorCap), .accessory(.retroHeadset),
        .accessory(.tinyBackpack), .outfit(.librarianCardigan), .outfit(.blanketBurrito), .outfit(.keepersPeacoat),
        .outfit(.koiYukata), .outfit(.gardenOveralls), .outfit(.varsityJacket), .outfit(.paintersSmock),
        .accessory(.monocle), .accessory(.instantCamera), .accessory(.sailorCollar), .accessory(.daisyChain),
        .outfit(.rainSlicker), .outfit(.sushiChef), .outfit(.snowDayPuffer), .accessory(.onsenTowel),
        .accessory(.fireflies),
    ]

    static let breeds: [PetBreed] = [
        .britishShorthair, .blackCat, .tuxedo, .orangeTabby, .sphynx, .scottishFold, .britishLonghair,
        .goldenRetriever, .labrador, .frenchBulldog, .corgi, .dachshund, .poodle, .shihTzu,
    ]

    static let poses: [(PetAnimation, Int)] = [(.idle, 0), (.celebrate, 2), (.walk, 0), (.stretch, 3), (.nap, 0)]

    static func look(_ item: PetItem) -> (outfit: PetOutfit, accessories: [PetAccessory]) {
        switch item {
        case .outfit(let outfit): (outfit, [])
        case .accessory(let accessory): (.none, [accessory])
        }
    }

    static func slug(_ item: PetItem) -> String { fileSlug(item.displayName) }

    /// Writes every sheet, or only the per-item sheets of `only` (item ids).
    static func write(to directory: URL, only: [String] = []) throws {
        let cards = directory.appendingPathComponent("cards", isDirectory: true)
        try FileManager.default.createDirectory(at: cards, withIntermediateDirectories: true)
        for (index, item) in candidates.enumerated() where only.isEmpty || only.contains(item.id) {
            let (outfit, accessories) = look(item)
            var cells: [Cell] = []
            for breed in breeds {
                for (animation, frameIndex) in poses {
                    let clip = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories)
                    let frame = clip.frames[min(frameIndex, clip.frames.count - 1)]
                    cells.append(Cell(label: "\(breed.displayName) \(animation.rawValue)",
                                      canvas: frame.itemFrames.first ?? frame.canvas, palette: breed.palette))
                }
            }
            try writeSheet(cells, columns: 10, title: "\(item.displayName) on every body shape",
                           to: directory.appendingPathComponent("outfit-\(slug(item)).png"))

            if item.loopFrameCount > 1 {
                var ticks: [Cell] = []
                for breed in PetGallery.bodyShapeBreeds {
                    for animation in [PetAnimation.idle, .walk] {
                        let frame = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories).frames[0]
                        ticks += frame.itemFrames.enumerated().map { tick, canvas in
                            Cell(label: "\(breed.displayName) \(tick)", canvas: canvas, palette: breed.palette)
                        }
                    }
                }
                try writeSheet(ticks, columns: item.loopFrameCount, title: "\(item.displayName) loop, sitting and walking",
                               to: directory.appendingPathComponent("loop-\(slug(item)).png"))
            }

            let number = String(format: "%02d", index + 1)
            for (breed, tag) in [(PetBreed.britishShorthair, "bsh"), (.blackCat, "black")] {
                let frame = PetComposer.clip(.idle, for: breed, outfit: outfit, accessories: accessories).frames[0]
                let canvases = frame.itemFrames.isEmpty ? [frame.canvas] : frame.itemFrames
                for (pixel, suffix) in [(4, ""), (2, "-2x")] {
                    try writeSprite(canvases[0], palette: breed.palette, scale: pixel,
                                    to: cards.appendingPathComponent("\(number)-\(slug(item))-\(tag)\(suffix).png"))
                    guard canvases.count > 1 else { continue }
                    for (tick, canvas) in canvases.enumerated() {
                        try writeSprite(canvas, palette: breed.palette, scale: pixel, to: cards.appendingPathComponent(
                            "\(number)-\(slug(item))-\(tag)\(suffix)-tick\(String(format: "%02d", tick)).png"))
                    }
                }
            }
        }
        guard only.isEmpty else { return }
        for breed in [PetBreed.britishShorthair, .blackCat] {
            let cells = candidates.enumerated().map { index, item in
                let (outfit, accessories) = look(item)
                return Cell(label: "\(index + 1) \(item.displayName)",
                            canvas: PetComposer.sitting(breed, outfit: outfit, accessories: accessories),
                            palette: breed.palette)
            }
            try writeSheet(cells, columns: 9, title: "Candidate outfits on \(breed.displayName)",
                           to: directory.appendingPathComponent("all-\(breed.rawValue).png"))
            try writeSheet(cells.map { Cell(label: "", canvas: $0.canvas, palette: $0.palette) }, columns: 9, title: "",
                           scale: 2, to: directory.appendingPathComponent("all-\(breed.rawValue)-2x.png"))
        }
    }

    /// Checks the rules the owner set for every candidate, beyond the unit
    /// tests: no eye covered in any frame or tick of any animation on any
    /// breed (hats and face items included), and an animated item changes
    /// at most 6 pixels on any tick against its still, sitting and walking.
    static func check() -> [String] {
        var problems: [String] = []
        for item in candidates {
            let (outfit, accessories) = look(item)
            for breed in PetBreed.allCases {
                for animation in PetAnimation.allCases {
                    let plain = PetComposer.clip(animation, for: breed).frames
                    let dressed = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories).frames
                    for (index, frame) in dressed.enumerated() {
                        let eyes = eyePoints(plain[index].canvas)
                        for (tick, canvas) in ([frame.canvas] + frame.itemFrames).enumerated() where eyePoints(canvas) != eyes {
                            problems.append("\(item.id) covers an eye on \(breed) \(animation) \(index) tick \(tick)")
                        }
                    }
                }
            }
            guard item.loopFrameCount > 1 else { continue }
            if case .accessory(let accessory) = item, accessory.slot == .aura {
                // Particles in the air: held to the Sparkle Trail's count of
                // pixels on any tick instead.
                func most(_ aura: PetAccessory) -> Int {
                    PetGallery.bodyShapeBreeds.flatMap { breed in
                        [PetAnimation.idle, .walk].flatMap { animation in
                            let frame = PetComposer.clip(animation, for: breed, accessories: [aura]).frames[0]
                            let bare = PetComposer.clip(animation, for: breed).frames[0].canvas
                            return frame.itemFrames.map { zip($0.pixels, bare.pixels).filter { $0 != $1 }.count }
                        }
                    }.max() ?? 0
                }
                let (mine, reference) = (most(accessory), most(.sparkleTrail))
                if mine > reference {
                    problems.append("\(item.id) shows \(mine) pixels on a tick, the Sparkle Trail \(reference)")
                }
                continue
            }
            for breed in PetGallery.bodyShapeBreeds {
                for animation in [PetAnimation.idle, .walk] {
                    let frame = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories).frames[0]
                    let changed = frame.itemFrames.map { canvas in
                        zip(canvas.pixels, frame.canvas.pixels).filter { $0 != $1 }.count
                    }
                    if (changed.max() ?? 0) > 6 || !changed.contains(where: { $0 > 0 }) {
                        problems.append("\(item.id) on \(breed) \(animation) changes \(changed) pixels per tick")
                    }
                }
            }
        }
        return problems
    }

    private static func eyePoints(_ canvas: PetCanvas) -> [Int] {
        canvas.pixels.indices.filter { canvas.pixels[$0] == .eye || canvas.pixels[$0] == .eyeLight }
    }

    /// One sprite on a transparent square, `scale` device pixels per sprite
    /// pixel.
    static func writeSprite(_ canvas: PetCanvas, palette: PetPalette, scale: Int, to url: URL) throws {
        guard let image = PetRenderer.shared.image(for: canvas, palette: palette, scale: scale) else {
            throw GalleryError.encode
        }
        try writePNG(image, to: url)
    }

    /// Prints the composed frames of `id` as palette symbols, one per body
    /// shape and pose, for drawing grids against.
    static func dump(_ id: String?) {
        let item = id.flatMap(PetItem.init(id:))
        let (outfit, accessories) = item.map(look) ?? (.none, [])
        for breed in PetGallery.bodyShapeBreeds {
            for (animation, frameIndex) in poses {
                let clip = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories)
                let frame = clip.frames[min(frameIndex, clip.frames.count - 1)]
                print("== \(breed.rawValue) \(animation.rawValue) \(frameIndex)")
                let canvas = frame.canvas
                print("   " + (0..<canvas.width).map { String($0 % 10) }.joined())
                for y in 0..<canvas.height {
                    let row = (0..<canvas.width).map { canvas[$0, y].map { String($0.symbol) } ?? "." }.joined()
                    print(String(format: "%2d ", y) + row)
                }
            }
        }
    }
}

/// Writes `image` as a PNG.
func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw GalleryError.encode }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
}
