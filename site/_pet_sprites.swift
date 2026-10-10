// Exports the pet sprites for the home page's interactive demo
// (site/js/demo.js) with the app's own pet composer and renderer, so the
// demo's cat is the app's cat, pixel for pixel.
//
//   swift build
//   site/_pet_sprites.sh
//
// Writes site/img/demo/pet-<look>.png and site/img/demo/pets.json.
// Each look is the starter British Shorthair in one outfit: one PNG atlas,
// one row per animation, frames left to right, each a 32 px sprite scaled
// by an integer factor with every sprite pixel an exact square block
// (nearest-neighbor). pets.json says where each animation's row is and
// how long each frame stays on screen.
//
// The app's `PetItemEffect.flicker` names an animated effect for the flame
// headband that the app's renderer does not draw yet. The demo shows it
// by splitting each frame of that look into short steps that trade the
// flame's gold and red pixels, which is the effect the hook describes.
import CoreGraphics
import Foundation
import TabbiKitCore

let scale = 1
let breed = PetBreed.britishShorthair
let animations: [PetAnimation] = [.idle, .blink, .celebrate, .typing]
/// How long one flicker step lasts, in seconds.
let flickerStep: TimeInterval = 0.16

struct Look {
    let id: String
    let outfit: PetOutfit
    let accessories: [PetAccessory]
    var flickers = false
}

let looks: [Look] = [
    Look(id: "plain", outfit: .none, accessories: []),
    Look(id: "crown", outfit: .none, accessories: [.tinyCrown]),
    Look(id: "hoodie", outfit: .cozyHoodie, accessories: []),
    Look(id: "wizard", outfit: .wizardRobe, accessories: [.wizardHat]),
    Look(id: "scholar", outfit: .none, accessories: [.scarf, .roundGlasses]),
    Look(id: "dino", outfit: .dinosaurHoodie, accessories: []),
    Look(id: "flame", outfit: .none, accessories: [.flameHeadband], flickers: true),
    Look(id: "laurel", outfit: .none, accessories: [.goldenLaurel]),
    Look(id: "cap", outfit: .none, accessories: [.backwardsCap]),
    Look(id: "medal", outfit: .none, accessories: [.teamMedal]),
]

enum ExportError: Error { case context, encode(String) }

/// The flame's pixels with gold and red traded, so alternating the two
/// canvases makes it flicker. Only pixels the bare pet does not have change.
func flickered(_ canvas: PetCanvas, bare: PetCanvas) -> PetCanvas {
    var copy = canvas
    for y in 0..<canvas.height {
        for x in 0..<canvas.width where bare[x, y] != canvas[x, y] {
            switch canvas[x, y] {
            case .gold: copy[x, y] = .heart
            case .heart: copy[x, y] = .gold
            default: break
            }
        }
    }
    return copy
}

/// The clip's frames as (canvas, duration) steps; a flickering look splits
/// each frame into short steps that alternate the flame.
func steps(of clip: PetClip, look: Look, bare: PetClip) -> [(PetCanvas, TimeInterval)] {
    guard look.flickers else { return clip.frames.map { ($0.canvas, $0.duration) } }
    var result: [(PetCanvas, TimeInterval)] = []
    var lit = false
    for (frame, bareFrame) in zip(clip.frames, bare.frames) {
        let count = max(1, Int((frame.duration / flickerStep).rounded()))
        let alternate = flickered(frame.canvas, bare: bareFrame.canvas)
        for _ in 0..<count {
            result.append((lit ? alternate : frame.canvas, frame.duration / Double(count)))
            lit.toggle()
        }
    }
    return result
}

/// Writes `pixels` (straight RGBA, row-major) as an 8-bit indexed PNG. A pet
/// uses a few dozen exact colors, so this is lossless and about a fifth of
/// the size ImageIO writes for the same RGBA image.
func writeIndexedPNG(_ pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
    var colors: [UInt32: UInt8] = [:]
    var palette: [UInt32] = []
    var rows = Data(capacity: (width + 1) * height)
    for y in 0..<height {
        rows.append(0) // filter: none
        for x in 0..<width {
            let i = (y * width + x) * 4
            // Every fully transparent pixel is the same color.
            let rgba = pixels[i + 3] == 0 ? 0 : pixels[i..<i + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if colors[rgba] == nil {
                guard palette.count < 256 else { throw ExportError.encode("over 256 colors in \(url.path)") }
                colors[rgba] = UInt8(palette.count)
                palette.append(rgba)
            }
            rows.append(colors[rgba]!)
        }
    }
    func chunk(_ type: String, _ body: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { data.append(contentsOf: $0) }
        let typed = Data(type.utf8) + body
        data.append(typed)
        withUnsafeBytes(of: crc32(typed).bigEndian) { data.append(contentsOf: $0) }
        return data
    }
    var header = Data()
    withUnsafeBytes(of: UInt32(width).bigEndian) { header.append(contentsOf: $0) }
    withUnsafeBytes(of: UInt32(height).bigEndian) { header.append(contentsOf: $0) }
    header.append(contentsOf: [8, 3, 0, 0, 0]) // 8-bit, indexed, deflate, no filter set, no interlace
    let plte = Data(palette.flatMap { [UInt8($0 >> 24), UInt8($0 >> 16 & 0xFF), UInt8($0 >> 8 & 0xFF)] })
    let trns = Data(palette.map { UInt8($0 & 0xFF) })
    // `compressed(using: .zlib)` gives a raw deflate stream; PNG wants it
    // wrapped in a zlib header and an Adler-32 checksum.
    guard let deflated = try? (rows as NSData).compressed(using: .zlib) as Data else {
        throw ExportError.encode(url.path)
    }
    var zlib = Data([0x78, 0xDA]) + deflated
    withUnsafeBytes(of: adler32(rows).bigEndian) { zlib.append(contentsOf: $0) }
    var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    png += chunk("IHDR", header) + chunk("PLTE", plte) + chunk("tRNS", trns) + chunk("IDAT", zlib) + chunk("IEND", Data())
    try png.write(to: url)
}

func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }
    return ~crc
}

func adler32(_ data: Data) -> UInt32 {
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in data {
        a = (a + UInt32(byte)) % 65521
        b = (b + a) % 65521
    }
    return b << 16 | a
}

func export(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let side = PetComposer.frameSize * scale
    var manifestLooks: [String: Any] = [:]
    for look in looks {
        let profile = PetProfile(name: "Mochi", breed: breed, outfit: look.outfit, accessories: look.accessories)
        let rows = animations.map { animation in
            let clip = PetComposer.clip(animation, for: breed, outfit: look.outfit, accessories: look.accessories)
            return (animation, steps(of: clip, look: look, bare: PetComposer.clip(animation, for: breed)))
        }
        let columns = rows.map(\.1.count).max() ?? 1
        let width = side * columns, height = side * rows.count
        // Sprite pixels are opaque or clear, so premultiplied RGBA reads back
        // as straight RGBA.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ExportError.context }
        context.interpolationQuality = .none
        var clips: [String: Any] = [:]
        for (row, (animation, frames)) in rows.enumerated() {
            for (column, (canvas, _)) in frames.enumerated() {
                guard let image = PetRenderer.render(canvas, palette: profile.palette, scale: scale) else { continue }
                // CoreGraphics is bottom-up.
                let y = side * (rows.count - 1 - row)
                context.draw(image, in: CGRect(x: side * column, y: y, width: side, height: side))
            }
            clips[animation.rawValue] = [
                "row": row,
                "loops": animation.loops,
                "durations": frames.map { ($0.1 * 1000).rounded() },
            ]
        }
        let file = "pet-\(look.id).png"
        try writeIndexedPNG(pixels, width: width, height: height, to: folder.appendingPathComponent(file))
        manifestLooks[look.id] = ["file": file, "clips": clips]
        print("wrote \(file)")
    }
    let manifest: [String: Any] = ["frame": side, "scale": scale, "looks": manifestLooks]
    let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: folder.appendingPathComponent("pets.json"))
    print("wrote pets.json")
}

let arguments = CommandLine.arguments.dropFirst()
try export(to: URL(fileURLWithPath: arguments.first ?? "site/img/demo"))
