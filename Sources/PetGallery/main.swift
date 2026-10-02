import CoreGraphics
import CoreText
import Foundation
import ImageIO
import NotchKitCore
import UniformTypeIdentifiers

// Renders pet contact sheets for art review: `swift run PetGallery out/`.
// Everything is drawn on pure black, like the real notch.

let scale = 4
let cellPadding = 16
let labelHeight = 28

struct Cell {
    let label: String
    let canvas: PetCanvas
    let palette: PetPalette
}

/// Lays cells out in rows of `columns` and writes a PNG.
func writeSheet(_ cells: [Cell], columns: Int, title: String, to url: URL) throws {
    let spriteSide = PetComposer.frameSize * scale
    let cellWidth = spriteSide + cellPadding * 2
    let cellHeight = spriteSide + cellPadding + labelHeight
    let titleHeight = 44
    let rows = (cells.count + columns - 1) / columns
    let width = cellWidth * columns
    let height = titleHeight + cellHeight * rows

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw GalleryError.context }
    context.interpolationQuality = .none
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // CoreGraphics is bottom-up; convert from top-left layout coordinates.
    func flip(_ y: Int, _ h: Int) -> Int { height - y - h }

    draw(title, size: 18, color: CGColor(gray: 1, alpha: 0.9), at: CGPoint(x: cellPadding, y: flip(14, 18)), in: context)
    for (index, cell) in cells.enumerated() {
        let column = index % columns, row = index / columns
        let x = column * cellWidth + cellPadding
        let y = titleHeight + row * cellHeight
        if let image = PetRenderer.shared.image(for: cell.canvas, palette: cell.palette, scale: scale) {
            context.draw(image, in: CGRect(x: x, y: flip(y, spriteSide), width: spriteSide, height: spriteSide))
        }
        draw(cell.label, size: 12, color: CGColor(gray: 1, alpha: 0.62),
             at: CGPoint(x: x, y: flip(y + spriteSide + 6, 12)), in: context)
    }

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw GalleryError.encode }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
    print("wrote \(url.path)")
}

func draw(_ text: String, size: CGFloat, color: CGColor, at point: CGPoint, in context: CGContext) {
    let font = CTFontCreateWithName("SF Pro Rounded" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = point
    CTLineDraw(line, context)
}

enum GalleryError: Error {
    case context
    case encode
}

let arguments = CommandLine.arguments.dropFirst()
let outputDirectory = URL(fileURLWithPath: arguments.first ?? "out", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for species in PetSpecies.allCases {
    let cells = PetBreed.breeds(of: species).map { breed in
        Cell(label: breed.displayName, canvas: PetComposer.sitting(breed), palette: breed.palette.withVisibleRim())
    }
    try writeSheet(cells, columns: 4, title: "\(species.displayName) breeds",
                   to: outputDirectory.appendingPathComponent("breeds-\(species.rawValue).png"))
}

// Costumes: every item alone on two breeds, plus full looks.
let looks: [(String, PetOutfit, [PetAccessory])] = [
    ("None", .none, []),
] + PetOutfit.allCases.dropFirst().map { ($0.displayName, $0, []) }
  + PetAccessory.allCases.map { ($0.displayName, .none, [$0]) }
  + [
      ("On call", .scrubs, [.stethoscope, .surgicalCap]),
      ("Attending", .whiteCoat, [.stethoscope, .headMirror]),
      ("Graduate", .whiteCoat, [.roundGlasses, .graduationCap]),
      ("Study day", .none, [.scarf, .roundGlasses, .beanie]),
  ]
for breed in [PetBreed.orangeTabby, .goldenRetriever] {
    let cells = looks.map { label, outfit, accessories in
        Cell(label: label, canvas: PetComposer.sitting(breed, outfit: outfit, accessories: accessories),
             palette: breed.palette.withVisibleRim())
    }
    try writeSheet(cells, columns: 5, title: "Costumes on \(breed.displayName)",
                   to: outputDirectory.appendingPathComponent("costumes-\(breed.rawValue).png"))
}

// Fit check: every breed in two full looks, so each head and body shape is covered.
for (name, outfit, accessories) in [looks[looks.count - 4], looks[looks.count - 1]] {
    let cells = PetBreed.allCases.map { breed in
        Cell(label: breed.displayName, canvas: PetComposer.sitting(breed, outfit: outfit, accessories: accessories),
             palette: breed.palette.withVisibleRim())
    }
    let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
    try writeSheet(cells, columns: 7, title: "Fit check: \(name)",
                   to: outputDirectory.appendingPathComponent("fit-\(slug).png"))
}

// Animation strips: every frame of every animation, with its duration.
// The last strip is dressed, to check that costumes follow every pose.
let strips: [(PetBreed, PetOutfit, [PetAccessory], String)] = [
    (.orangeTabby, .none, [], ""), (.tuxedo, .none, [], ""), (.corgi, .none, [], ""), (.dachshund, .none, [], ""),
    (.goldenRetriever, .scrubs, [.stethoscope, .surgicalCap], "-dressed"),
]
for (breed, outfit, accessories, suffix) in strips {
    var cells: [Cell] = []
    for animation in PetAnimation.allCases {
        let clip = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories)
        for (index, frame) in clip.frames.enumerated() {
            let label = "\(animation.rawValue) \(index + 1) · \(Int(frame.duration * 1000))ms"
            cells.append(Cell(label: label, canvas: frame.canvas, palette: breed.palette.withVisibleRim()))
        }
    }
    try writeSheet(cells, columns: 8, title: "Animations: \(breed.displayName)\(suffix.isEmpty ? "" : ", dressed")",
                   to: outputDirectory.appendingPathComponent("animations-\(breed.rawValue)\(suffix).png"))
}

// Walk check: every breed through the full step cycle, then a few looks.
var walkCells: [Cell] = []
for breed in PetBreed.allCases {
    let clip = PetComposer.clip(.walk, for: breed)
    for (index, frame) in clip.frames.enumerated() {
        walkCells.append(Cell(label: "\(breed.displayName) \(index + 1)", canvas: frame.canvas,
                              palette: breed.palette.withVisibleRim()))
    }
}
for (breed, look) in [(PetBreed.orangeTabby, looks[looks.count - 4]), (.goldenRetriever, looks[looks.count - 3]),
                      (.dachshund, looks[looks.count - 2]), (.tuxedo, looks[looks.count - 1])] {
    let clip = PetComposer.clip(.walk, for: breed, outfit: look.1, accessories: look.2)
    for (index, frame) in clip.frames.enumerated() {
        walkCells.append(Cell(label: "\(look.0) \(index + 1)", canvas: frame.canvas,
                              palette: breed.palette.withVisibleRim()))
    }
}
try writeSheet(walkCells, columns: 8, title: "Walk cycle (150ms per step)",
               to: outputDirectory.appendingPathComponent("walk.png"))

// Stretch check: every breed through the whole bow, then two dressed looks.
var stretchCells: [Cell] = []
let stretchRuns = PetBreed.allCases.map { ($0, $0.displayName, PetOutfit.none, [PetAccessory]()) }
    + [(.corgi, "On call", .scrubs, [.stethoscope, .surgicalCap]), (.siamese, "Graduate", .whiteCoat, [.roundGlasses, .graduationCap])]
for (breed, name, outfit, accessories) in stretchRuns {
    let clip = PetComposer.clip(.stretch, for: breed, outfit: outfit, accessories: accessories)
    for (index, frame) in clip.frames.enumerated() {
        stretchCells.append(Cell(label: "\(name) \(index + 1)", canvas: frame.canvas,
                                 palette: breed.palette.withVisibleRim()))
    }
}
try writeSheet(stretchCells, columns: 9, title: "Stretch (play bow)",
               to: outputDirectory.appendingPathComponent("stretch.png"))

// Recolor check: user overrides through PetProfile, so the real palette path
// (breed, then overrides, then the warm rim) is what gets reviewed.
func hex(_ value: String) -> PetColor { PetColor(hex: value)! }
// Fur goes through PetProfile.tintFur, the one-color picker path, so each
// breed keeps its own light/dark markings.
let furTints: [(String, PetColor?)] = [
    ("Default", nil), ("Cream", hex("#F2D7A6")), ("Lilac", hex("#B4A2C8")),
    ("Chocolate", hex("#6E4632")), ("Black (rim)", hex("#1C1719")),
]
let scrubRecolors: [(String, [PetPaletteRole: PetColor])] = [
    ("Teal scrubs", [:]),
    ("Navy scrubs", [.costumeBase: hex("#3B5B9A"), .costumeShade: hex("#2B4478"), .costumeTrim: hex("#DCE6FF")]),
    ("Ceil scrubs", [.costumeBase: hex("#8FB8E8"), .costumeShade: hex("#6C95C8"), .costumeTrim: hex("#F2F8FF")]),
    ("Wine scrubs", [.costumeBase: hex("#A0405A"), .costumeShade: hex("#7C2E45"), .costumeTrim: hex("#FFE3EA")]),
    ("Lavender scrubs", [.costumeBase: hex("#A99BE0"), .costumeShade: hex("#8578C0"), .costumeTrim: hex("#F4F0FF")]),
]
let knitRecolors: [(String, [PetPaletteRole: PetColor])] = [
    ("Rose knit", [:]),
    ("Mustard knit", [.accessoryBase: hex("#E2B23E"), .accessoryShade: hex("#B98A24")]),
    ("Forest knit", [.accessoryBase: hex("#4E9A6A"), .accessoryShade: hex("#367550")]),
    ("Sky knit", [.accessoryBase: hex("#6FB2E6"), .accessoryShade: hex("#4C8CC0")]),
    ("Plum knit", [.accessoryBase: hex("#9A5AA8"), .accessoryShade: hex("#764084")]),
]
var recolorCells: [Cell] = []
for breed in [PetBreed.orangeTabby, .goldenRetriever, .corgi] {
    for (label, tint) in furTints {
        var profile = PetProfile(name: label, breed: breed)
        profile.tintFur(tint)
        recolorCells.append(Cell(label: label, canvas: profile.sittingCanvas(), palette: profile.palette))
    }
}
let recolorRuns: [(PetBreed, PetOutfit, [PetAccessory], [(String, [PetPaletteRole: PetColor])])] = [
    (.grayTabby, .scrubs, [.stethoscope, .surgicalCap], scrubRecolors),
    (.beagle, .none, [.scarf, .beanie], knitRecolors),
]
for (breed, outfit, accessories, recolors) in recolorRuns {
    for (label, overrides) in recolors {
        let profile = PetProfile(name: label, breed: breed, paletteOverrides: overrides,
                                 outfit: outfit, accessories: accessories)
        recolorCells.append(Cell(label: label, canvas: profile.sittingCanvas(), palette: profile.palette))
    }
}
try writeSheet(recolorCells, columns: 5, title: "Recolors (fur, scrubs, knits)",
               to: outputDirectory.appendingPathComponent("recolors.png"))
