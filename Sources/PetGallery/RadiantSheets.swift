import CoreGraphics
import Foundation
import ImageIO
import TabbiKitCore
import UniformTypeIdentifiers

/// `swift run PetGallery out/ radiant` renders every Radiant design through
/// the real composer and renderer: per item and intensity a frame strip and a
/// GIF on the British Shorthair and the black cat at 4x and at notch size
/// (2 device pixels per sprite pixel, with the closed notch's ceiling), a
/// sheet on every body shape idling and celebrating, the Radiant marker, and
/// `manifest.json` with each effect's pixel budget and rule checks over all
/// 19 breeds and every animation.
enum RadiantSheets {
    typealias Item = RadiantCatalog.Item

    enum Variant: String, CaseIterable {
        case normal, subtle, bold
        func effect(_ item: Item) -> RadiantEffect? {
            switch self {
            case .normal: nil
            case .subtle: item.subtle
            case .bold: item.bold
            }
        }
    }

    /// The closed notch's ceiling row (`NotchPreviewLayout.petCeilingRow`:
    /// a 32 pt bar, the pet lifted 1 pt, a 1 pt margin).
    static let notchCeiling = 2
    static let tick = PetFrame.itemFrameDuration
    static let cats: [(String, PetBreed)] = [("british-shorthair", .britishShorthair), ("black-cat", .blackCat)]

    // MARK: Composing

    /// Every frame of `animation` for each tick of `loop`: `[frame][tick]`.
    static func frames(_ item: Item, _ effect: RadiantEffect?, breed: PetBreed, animation: PetAnimation,
                       loop: Int, ceiling: Int?) -> [[PetCanvas]] {
        let full = PetComposer.clip(animation, for: breed, outfit: item.outfit, accessories: item.accessories)
        let bare = PetComposer.clip(animation, for: breed)
        let notch = ceiling.map {
            PetComposer.clip(animation, for: breed, outfit: item.outfit, accessories: item.accessories, ceiling: $0)
        }
        return full.frames.indices.map { i in
            (0..<loop).map { t in
                let scene = scene(full.frames[i], bare.frames[i], notch?.frames[i], tick: t, animation: animation,
                                  ceiling: ceiling)
                guard let effect else { return scene.dressed }
                return scene.render(effect.layer(scene, tick: t))
            }
        }
    }

    static func ticks(_ frame: PetFrame, _ t: Int) -> PetCanvas {
        frame.itemFrames.isEmpty ? frame.canvas : frame.itemFrames[t % frame.itemFrames.count]
    }

    static func scene(_ dressed: PetFrame, _ bare: PetFrame, _ notch: PetFrame?, tick t: Int, animation: PetAnimation,
                      ceiling: Int?) -> RadiantScene {
        let full = ticks(dressed, t)
        let plain = bare.canvas
        var item: [Int: PetPaletteRole] = [:]
        for i in full.pixels.indices where full.pixels[i] != nil && full.pixels[i] != plain.pixels[i] {
            item[i] = full.pixels[i]
        }
        guard let notch else {
            return RadiantScene(dressed: full, bare: plain, item: item, animation: animation, ceiling: nil)
        }
        let shown = ticks(notch, t)
        let dy = shift(from: full, to: shown)
        let width = full.width
        var moved: [Int: PetPaletteRole] = [:]
        for (i, role) in item {
            let j = i + dy * width
            if j >= 0, j < full.pixels.count, shown.pixels[j] == role { moved[j] = role }
        }
        return RadiantScene(dressed: shown, bare: plain.shifted(x: 0, y: dy), item: moved, animation: animation,
                            ceiling: ceiling)
    }

    /// How far the notch's clip moved the frame down to clear its ceiling.
    static func shift(from full: PetCanvas, to shown: PetCanvas) -> Int {
        let pet = full.pixels.indices.filter {
            full.pixels[$0].map { !RadiantScene.effectRoles.contains($0) } ?? false
        }
        return (0...12).max { a, b in score(a) < score(b) } ?? 0
        func score(_ d: Int) -> Int {
            pet.filter { i in
                let j = i + d * full.width
                return j < shown.pixels.count && shown.pixels[j] == full.pixels[i]
            }.count
        }
    }

    // MARK: Images

    static func image(_ canvases: [PetCanvas], palette: PetPalette, scale: Int, background: CGColor?) -> CGImage? {
        let side = PetComposer.frameSize * scale
        guard let context = CGContext(
            data: nil, width: side * canvases.count, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        if let background {
            context.setFillColor(background)
            context.fill(CGRect(x: 0, y: 0, width: side * canvases.count, height: side))
        }
        for (n, canvas) in canvases.enumerated() {
            guard let sprite = PetRenderer.render(canvas, palette: palette, scale: scale) else { continue }
            context.draw(sprite, in: CGRect(x: n * side, y: 0, width: side, height: side))
        }
        return context.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GalleryError.encode }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
    }

    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { throw GalleryError.encode }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                kCGImagePropertyGIFUnclampedDelayTime: delay],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
    }

    static func palette(_ breed: PetBreed) -> PetPalette { PetProfile(name: "", breed: breed).palette }

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    // MARK: Writing

    static func write(to directory: URL) throws {
        let fm = FileManager.default
        for sub in ["strips", "gifs", "sheets"] {
            try fm.createDirectory(at: directory.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let only = ProcessInfo.processInfo.environment["RADIANT_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let skipChecks = ProcessInfo.processInfo.environment["RADIANT_NO_CHECKS"] != nil
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        var manifest: [[String: Any]] = []
        for item in RadiantCatalog.items where only?.contains(item.id) ?? true {
            var entry: [String: Any] = ["id": item.id, "name": item.name, "price": item.price,
                                        "radiantPrice": item.price * 5, "normalLoop": item.petItem.loopFrameCount]
            for variant in Variant.allCases {
                // The normal item plays on the loop of the effect it sits beside.
                let effect = variant.effect(item)
                let loop = effect?.loop ?? item.bold.loop
                for (catID, breed) in cats {
                    for (label, scale, ceiling) in [("4x", 4, nil), ("notch", 2, notchCeiling)] as [(String, Int, Int?)] {
                        let idle = frames(item, effect, breed: breed, animation: .idle, loop: loop, ceiling: ceiling)
                        let name = "\(item.id)-\(variant.rawValue)-\(catID)-\(label)"
                        if let strip = image(idle[0], palette: palette(breed), scale: scale, background: nil) {
                            try writePNG(strip, to: directory.appendingPathComponent("strips/\(name).png"))
                        }
                        // The GIF plays the real idle (its head nod) on the item
                        // clock, long enough that both come round together.
                        let clip = PetComposer.clip(.idle, for: breed)
                        let length = loop / gcd(loop, 40) * 40
                        let gif = (0..<length).compactMap { t in
                            image([idle[clip.frameIndex(at: Double(t) * tick + 1e-6)][t % loop]], palette: palette(breed),
                                  scale: scale, background: black)
                        }
                        try writeGIF(gif, delay: tick, to: directory.appendingPathComponent("gifs/\(name).gif"))
                    }
                }
                guard let effect else { continue }
                try sheet(item, variant, effect, to: directory.appendingPathComponent(
                    "sheets/\(item.id)-\(variant.rawValue)-body-shapes.png"))
                var info: [String: Any] = ["name": effect.name, "loop": effect.loop, "summary": effect.summary]
                if !skipChecks { info["checks"] = checks(item, effect) }
                entry[variant.rawValue] = info
            }
            if !skipChecks { entry["normalBudget"] = normalBudget(item) }
            manifest.append(entry)
            print("wrote \(item.name)")
        }
        try writeMarker(to: directory)
        let data = try JSONSerialization.data(withJSONObject: ["tickMs": Int(tick * 1000), "items": manifest],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent(only == nil ? "manifest.json" : "manifest-partial.json"))
        print("wrote \(directory.path)")
    }

    /// Every body shape, idling (the loop on the still pose) and
    /// celebrating (the clip played on the item clock), one column a tick.
    static func sheet(_ item: Item, _ variant: Variant, _ effect: RadiantEffect, to url: URL) throws {
        let scale = 3, side = PetComposer.frameSize * scale, pad = 6, labelWidth = 170, header = 34
        let breeds = PetGallery.bodyShapeBreeds
        let columns = effect.loop
        let width = labelWidth + columns * (side + pad) + pad
        let height = header + breeds.count * 2 * (side + pad) + pad
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GalleryError.context }
        context.interpolationQuality = .none
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func flip(_ y: Int, _ h: Int) -> Int { height - y - h }
        draw("\(item.name), Radiant \(variant.rawValue): \(effect.name) (\(effect.loop) ticks of 150 ms)", size: 15,
             color: CGColor(gray: 1, alpha: 0.9), at: CGPoint(x: pad, y: flip(10, 15)), in: context)
        for (row, breed) in breeds.enumerated() {
            for (k, animation) in [PetAnimation.idle, .celebrate].enumerated() {
                let y = header + (row * 2 + k) * (side + pad)
                draw("\(breed.bodyShape.rawValue) \(animation.rawValue)", size: 11, color: CGColor(gray: 1, alpha: 0.6),
                     at: CGPoint(x: pad, y: flip(y + side / 2, 11)), in: context)
                let all = frames(item, effect, breed: breed, animation: animation, loop: effect.loop, ceiling: nil)
                let clip = PetComposer.clip(animation, for: breed)
                for t in 0..<columns {
                    let index = animation == .idle ? 0 : clip.frameIndex(at: Double(t) * tick + tick / 2)
                    guard let sprite = PetRenderer.render(all[index][t], palette: palette(breed), scale: scale) else { continue }
                    context.draw(sprite, in: CGRect(x: labelWidth + t * (side + pad), y: flip(y, side), width: side, height: side))
                }
            }
        }
        guard let image = context.makeImage() else { throw GalleryError.encode }
        try writePNG(image, to: url)
    }

    // MARK: Checks

    static func diff(_ a: PetCanvas, _ b: PetCanvas) -> Int { zip(a.pixels, b.pixels).filter { $0 != $1 }.count }

    /// The rules and the pixel budget, over every breed, animation, frame and
    /// tick, at full size and under the notch's ceiling.
    static func checks(_ item: Item, _ effect: RadiantEffect) -> [String: Any] {
        var eyes = 0, face = 0, bounds = 0, ceilingHits = 0
        var stillTest = 0, stillAll = 0, stepAll = 0, addedAll = 0
        var worst = ""
        for breed in PetBreed.allCases {
            for animation in PetAnimation.allCases {
                for ceiling in [nil, notchCeiling] as [Int?] {
                    let radiant = frames(item, effect, breed: breed, animation: animation, loop: effect.loop, ceiling: ceiling)
                    let normal = frames(item, nil, breed: breed, animation: animation, loop: effect.loop, ceiling: ceiling)
                    let bare = PetComposer.clip(animation, for: breed, ceiling: ceiling)
                    for (i, ticks) in radiant.enumerated() {
                        let faceBox = scene(PetComposer.clip(animation, for: breed).frames[i], bare.frames[i], nil, tick: 0,
                                            animation: animation, ceiling: nil).faceBox
                        for (t, canvas) in ticks.enumerated() {
                            let plain = normal[i][t]
                            var added = 0
                            for y in 0..<canvas.height {
                                for x in 0..<canvas.width where canvas[x, y] != plain[x, y] {
                                    added += 1
                                    if let under = plain[x, y], RadiantScene.eyeRoles.contains(under) { eyes += 1 }
                                    if let under = plain[x, y], RadiantScene.faceRoles.contains(under) { face += 1 }
                                    if ceiling == nil, let f = faceBox, x >= f.minX, x <= f.maxX, y >= f.minY, y <= f.maxY,
                                       plain[x, y] != nil, bare.frames[i].canvas[x, y] == plain[x, y] { face += 1 }
                                    // New pixels keep a one-pixel margin inside the frame (a glint on an
                                    // item that already reaches the edge, like the cloud, is not new extent).
                                    if plain[x, y] == nil, x < 1 || x > canvas.width - 2 || y < 1 || y > canvas.height - 2 { bounds += 1 }
                                    if let ceiling, y < ceiling, canvas[x, y] != nil { ceilingHits += 1 }
                                }
                            }
                            addedAll = max(addedAll, added)
                            let vsStill = diff(canvas, ticks[0])
                            if ceiling == nil, i == 0, animation == .idle || animation == .walk {
                                if vsStill > stillTest { worst = "\(breed.rawValue) \(animation.rawValue) tick \(t)" }
                                stillTest = max(stillTest, vsStill)
                            }
                            stillAll = max(stillAll, vsStill)
                            if t > 0 { stepAll = max(stepAll, diff(canvas, ticks[t - 1])) }
                        }
                    }
                }
            }
        }
        return ["eyeViolations": eyes, "faceViolations": face, "boundsViolations": bounds,
                "ceilingViolations": ceilingHits, "maxVsStillTestPoses": stillTest, "worstTestPose": worst,
                "maxVsStillAllPoses": stillAll, "maxTickToTick": stepAll, "maxAddedOverNormal": addedAll]
    }

    /// The normal item's own loop, measured the same way (only the rain
    /// cloud moves).
    static func normalBudget(_ item: Item) -> [String: Int] {
        var still = 0, step = 0
        for breed in PetGallery.bodyShapeBreeds {
            for animation in [PetAnimation.idle, .walk] {
                let ticks = frames(item, nil, breed: breed, animation: animation, loop: item.bold.loop, ceiling: nil)[0]
                for (t, canvas) in ticks.enumerated() {
                    still = max(still, diff(canvas, ticks[0]))
                    if t > 0 { step = max(step, diff(canvas, ticks[t - 1])) }
                }
            }
        }
        return ["maxVsStillTestPoses": still, "maxTickToTick": step]
    }

    // MARK: The Radiant marker

    /// A 9 by 9 four-pointed star pip for the Closet tile's corner, in the
    /// Goals badges' roles and gold colors: `C` rim, `D` shade, `W` bright
    /// core, `L` highlight, `O` outline, drawn with its outline like a badge.
    static let marker = [
        "....O....",
        "...OLO...",
        "...OCO...",
        ".OOCWCOO.",
        "OLCWWWCDO",
        ".OOCWDOO.",
        "...ODO...",
        "...ODO...",
        "....O....",
    ]

    static func writeMarker(to directory: URL) throws {
        let palette = BadgePalette.palette(for: .tier(.gold))
        let grid = SpriteGrid(art: marker.joined(separator: "\n"))
        var canvas = PetCanvas(width: grid.width, height: grid.height)
        canvas.stamp(grid, x: 0, y: 0)
        for scale in [3, 4, 12] {
            guard let context = CGContext(
                data: nil, width: grid.width * scale, height: grid.height * scale, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw GalleryError.context }
            // A plain role lookup, like the badges: no rim.
            for y in 0..<grid.height {
                for x in 0..<grid.width {
                    guard let role = canvas[x, y] else { continue }
                    let c = palette[role]
                    context.setFillColor(CGColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255,
                                                 blue: CGFloat(c.blue) / 255, alpha: CGFloat(c.alpha) / 255))
                    context.fill(CGRect(x: x * scale, y: (grid.height - 1 - y) * scale, width: scale, height: scale))
                }
            }
            guard let image = context.makeImage() else { throw GalleryError.encode }
            try writePNG(image, to: directory.appendingPathComponent("marker-\(scale)x.png"))
        }
    }
}
