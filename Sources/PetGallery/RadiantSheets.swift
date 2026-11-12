import CoreGraphics
import Foundation
import ImageIO
import TabbiKitCore
import UniformTypeIdentifiers

/// `swift run PetGallery out/ radiant` renders the Radiant effects through
/// the real composer (`PetComposer.clip(radiant:)`): per item and intensity
/// a frame strip and a GIF on the British Shorthair and the black cat at 4x
/// and at notch size (2 device pixels per sprite pixel, with the closed
/// notch's ceiling), a sheet on every body shape idling and celebrating,
/// `combos.png` with every pair and triple of Radiant items worn together,
/// and the Radiant marker.
enum RadiantSheets {
    /// The closed notch's ceiling row (`NotchPreviewLayout.petCeilingRow`).
    static let notchCeiling = 2
    static let tick = PetFrame.itemFrameDuration
    static let cats: [(String, PetBreed)] = [("british-shorthair", .britishShorthair), ("black-cat", .blackCat)]

    static func slug(_ item: PetItem) -> String {
        item.displayName.lowercased().filter { $0 != "'" }.replacingOccurrences(of: " ", with: "-")
    }

    /// The look wearing `items` (as Radiant at `intensity`, or plain when nil).
    static func look(_ items: [PetItem], _ intensities: [PetRadiantIntensity?])
        -> (PetOutfit, [PetAccessory], PetRadiantLook) {
        var outfit = PetOutfit.none
        var accessories: [PetAccessory] = []
        var radiant: [PetItem: PetRadiantIntensity] = [:]
        for (item, intensity) in zip(items, intensities) {
            switch item {
            case .outfit(let o): outfit = o
            case .accessory(let a): accessories.append(a)
            }
            if let intensity { radiant[item] = intensity }
        }
        return (outfit, accessories, PetRadiantLook(radiant))
    }

    /// One frame of `animation` through `ticks` ticks of the item clock.
    static func loop(_ items: [PetItem], _ intensities: [PetRadiantIntensity?], breed: PetBreed,
                     animation: PetAnimation = .idle, frame: Int = 0, ticks: Int? = nil, ceiling: Int? = nil) -> [PetCanvas] {
        let (outfit, accessories, radiant) = look(items, intensities)
        let clip = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories, radiant: radiant,
                                    ceiling: ceiling)
        let f = clip.frames[min(frame, clip.frames.count - 1)]
        let all = f.itemFrames.isEmpty ? [f.canvas] : f.itemFrames
        let count = ticks ?? max(all.count, 24)
        return (0..<count).map { all[$0 % all.count] }
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

    static func writeGIF(_ frames: [CGImage], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { throw GalleryError.encode }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: tick, kCGImagePropertyGIFUnclampedDelayTime: tick],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw GalleryError.encode }
    }

    static func palette(_ breed: PetBreed) -> PetPalette { PetProfile(name: "", breed: breed).palette }

    // MARK: Writing

    static func write(to directory: URL) throws {
        let fm = FileManager.default
        for sub in ["strips", "gifs", "sheets"] {
            try fm.createDirectory(at: directory.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let only = ProcessInfo.processInfo.environment["RADIANT_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        for item in PetRadiant.eligibleItems where only?.contains(slug(item)) ?? true {
            for intensity in [nil, PetRadiantIntensity.subtle, .bold] {
                let variant = intensity?.rawValue ?? "normal"
                for (catID, breed) in cats {
                    for (label, scale, ceiling) in [("4x", 4, nil), ("notch", 2, notchCeiling)] as [(String, Int, Int?)] {
                        let frames = loop([item], [intensity], breed: breed, ticks: 24, ceiling: ceiling)
                        let name = "\(slug(item))-\(variant)-\(catID)-\(label)"
                        if let strip = image(frames, palette: palette(breed), scale: scale, background: nil) {
                            try writePNG(strip, to: directory.appendingPathComponent("strips/\(name).png"))
                        }
                        let gif = frames.compactMap { image([$0], palette: palette(breed), scale: scale, background: black) }
                        try writeGIF(gif, to: directory.appendingPathComponent("gifs/\(name).gif"))
                    }
                }
                guard let intensity else { continue }
                try sheet(item, intensity, to: directory.appendingPathComponent("sheets/\(slug(item))-\(variant)-body-shapes.png"))
            }
            print("wrote \(item.displayName)")
        }
        if only == nil || only?.contains("combos") == true {
            try combos(to: directory.appendingPathComponent("combos.png"))
        }
        try writeMarker(to: directory)
        print("wrote \(directory.path)")
    }

    /// Every body shape, idling (the loop on the still pose) and
    /// celebrating (the clip played on the item clock), one column a tick.
    static func sheet(_ item: PetItem, _ intensity: PetRadiantIntensity, to url: URL) throws {
        let breeds = PetGallery.bodyShapeBreeds
        var rows: [(String, PetBreed, [PetCanvas])] = []
        for breed in breeds {
            rows.append(("\(breed.bodyShape.rawValue) idle", breed, loop([item], [intensity], breed: breed, ticks: 24)))
            let (outfit, accessories, radiant) = look([item], [intensity])
            let clip = PetComposer.clip(.celebrate, for: breed, outfit: outfit, accessories: accessories, radiant: radiant)
            let frames = (0..<24).map { t -> PetCanvas in
                let frame = clip.frames[clip.frameIndex(at: Double(t) * tick + tick / 2)]
                return frame.itemFrames.isEmpty ? frame.canvas : frame.itemFrames[t % frame.itemFrames.count]
            }
            rows.append(("\(breed.bodyShape.rawValue) celebrate", breed, frames))
        }
        let title = "\(item.displayName), Radiant \(intensity.rawValue): \(PetRadiant.effectName(item, intensity) ?? "")"
        try grid(rows, title: title, scale: 3, to: url)
    }

    /// Every pair and triple of Radiant items worn together, Bold, on the
    /// British Shorthair and the Shih Tzu, through the whole layout loop.
    static func combos(to url: URL) throws {
        let items = PetRadiant.eligibleItems
        func slot(_ item: PetItem) -> String {
            switch item {
            case .outfit: "outfit"
            case .accessory(let a): String(describing: a.slot)
            }
        }
        var sets: [[PetItem]] = []
        for (i, a) in items.enumerated() {
            for b in items[(i + 1)...] where slot(a) != slot(b) { sets.append([a, b]) }
        }
        for (i, a) in items.enumerated() {
            for (j, b) in items.enumerated() where j > i && slot(a) != slot(b) {
                for c in items[(j + 1)...] where slot(c) != slot(a) && slot(c) != slot(b) { sets.append([a, b, c]) }
            }
        }
        var rows: [(String, PetBreed, [PetCanvas])] = []
        for set in sets {
            for breed in [PetBreed.britishShorthair, .shihTzu] {
                let frames = loop(set, set.map { _ in .bold }, breed: breed)
                // Every other tick, so a whole layout fits on a row.
                let step = max(1, frames.count / 24)
                let label = set.map(\.displayName).joined(separator: " + ") + (breed == .shihTzu ? " (Shih Tzu)" : "")
                rows.append((label, breed, stride(from: 0, to: frames.count, by: step).map { frames[$0] }))
            }
        }
        try grid(rows, title: "Radiant items worn together, Bold, one column per tick (two when they take turns)",
                 scale: 3, labelWidth: 330, to: url)
    }

    static func grid(_ rows: [(String, PetBreed, [PetCanvas])], title: String, scale: Int, labelWidth: Int = 170,
                     to url: URL) throws {
        let side = PetComposer.frameSize * scale, pad = 6, header = 34
        let columns = rows.map(\.2.count).max() ?? 1
        let width = labelWidth + columns * (side + pad) + pad
        let height = header + rows.count * (side + pad) + pad
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GalleryError.context }
        context.interpolationQuality = .none
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func flip(_ y: Int, _ h: Int) -> Int { height - y - h }
        draw(title, size: 15, color: CGColor(gray: 1, alpha: 0.9), at: CGPoint(x: pad, y: flip(10, 15)), in: context)
        for (row, (label, breed, frames)) in rows.enumerated() {
            let y = header + row * (side + pad)
            draw(label, size: 11, color: CGColor(gray: 1, alpha: 0.6), at: CGPoint(x: pad, y: flip(y + side / 2, 11)), in: context)
            for (t, canvas) in frames.enumerated() {
                guard let sprite = PetRenderer.render(canvas, palette: palette(breed), scale: scale) else { continue }
                context.draw(sprite, in: CGRect(x: labelWidth + t * (side + pad), y: flip(y, side), width: side, height: side))
            }
        }
        guard let image = context.makeImage() else { throw GalleryError.encode }
        try writePNG(image, to: url)
    }

    // MARK: The Radiant marker

    static func writeMarker(to directory: URL) throws {
        for scale in [3, 4, 12] {
            guard let image = RadiantMarkerArt.image(scale: scale) else { throw GalleryError.encode }
            try writePNG(image, to: directory.appendingPathComponent("marker-\(scale)x.png"))
        }
    }
}
