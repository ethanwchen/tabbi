#!/usr/bin/env swift
// Builds the README screenshots and the GitHub social preview in docs/images
// from the app's demo snapshots, and the launch demo videos in
// docs/launch/video when ffmpeg is installed.
//
//     swift docs/make-screenshots.swift                         # render demo snapshots, then compose
//     swift docs/make-screenshots.swift <essentials> <medicine>  # compose from existing snapshot folders
//
// The Essentials kit's snapshots (Midnight theme) give the everyday tabs, and
// the Med School kit's (Cozy theme, with the pet) give the study tabs, the
// animated hero and onboarding, so the README shows both looks.
//
// The snapshot renderer draws the notch on a flat grey stand-in desktop. This
// script cuts the notch out of that backdrop (keeping its anti-aliased edge)
// and places it on a dark, wallpaper-like gradient so the screenshots look
// like the top of a real Mac screen. Demo mode (TABBI_DEMO=1) keeps the
// data realistic and private: no Spotify, Calendar, network, or claude CLI.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = root.appendingPathComponent("docs/images")

/// Grey level of `SnapshotRenderer`'s stand-in desktop (`Color(white: 0.16)`).
let backdropLevel = 41

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-screenshots: \(message)\n".utf8))
    exit(1)
}

// MARK: - Snapshots

/// Renders fresh demo snapshots of one kit into a temporary folder and returns it.
func renderDemoSnapshots(kit: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tabbi-snapshots-\(kit)-\(ProcessInfo.processInfo.processIdentifier)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run", "-c", "release", "Tabbi", "--snapshot", directory.path, "--kit", kit]
    process.currentDirectoryURL = root
    var environment = ProcessInfo.processInfo.environment
    environment["TABBI_DEMO"] = "1"
    process.environment = environment
    do { try process.run() } catch { fail("could not run swift: \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("snapshot rendering failed") }
    return directory
}

// MARK: - Pixels

/// An 8-bit premultiplied RGBA bitmap that can be read and written directly.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { fail("cannot read \(url.path)") }
        self.init(width: image.width, height: image.height)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        withContext { $0.draw(image, in: rect) }
    }

    /// Runs `body` with a bitmap context backed by `pixels` (origin bottom-left).
    mutating func withContext(_ body: (CGContext) -> Void) {
        let (width, height) = (self.width, self.height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { fail("cannot create a bitmap context") }
            body(context)
        }
    }

    func cgImage() -> CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    func write(to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { fail("cannot write \(url.path)") }
        CGImageDestinationAddImage(destination, cgImage(), nil)
        guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
        print(url.path)
    }
}

/// Makes the stand-in desktop transparent, leaving only the notch.
///
/// A flood fill from the image border removes every backdrop-coloured pixel
/// connected to the outside, so greys inside the panel are never touched. The
/// notch's anti-aliased rim (greys between black and the backdrop) becomes
/// partially transparent black, so the edge stays smooth on any background.
func cutOutNotch(_ bitmap: inout Bitmap) {
    let (width, height) = (bitmap.width, bitmap.height)
    func isBackdrop(_ index: Int) -> Bool {
        let offset = index * 4
        return (0..<3).allSatisfy { abs(Int(bitmap.pixels[offset + $0]) - backdropLevel) <= 1 }
    }

    var removed = [Bool](repeating: false, count: width * height)
    var stack: [Int] = []
    for x in 0..<width { stack += [x, (height - 1) * width + x] }
    for y in 0..<height { stack += [y * width, y * width + width - 1] }
    while let index = stack.popLast() {
        guard !removed[index], isBackdrop(index) else { continue }
        removed[index] = true
        let (x, y) = (index % width, index / width)
        if x > 0 { stack.append(index - 1) }
        if x < width - 1 { stack.append(index + 1) }
        if y > 0 { stack.append(index - width) }
        if y < height - 1 { stack.append(index + width) }
    }

    var rim: [Int] = []
    for index in 0..<(width * height) where !removed[index] {
        let (x, y) = (index % width, index / width)
        let touchesBackdrop = [(-1, 0), (1, 0), (0, -1), (0, 1)].contains { dx, dy in
            let (nx, ny) = (x + dx, y + dy)
            return nx >= 0 && nx < width && ny >= 0 && ny < height && removed[ny * width + nx]
        }
        if touchesBackdrop { rim.append(index) }
    }

    for index in 0..<(width * height) where removed[index] {
        for channel in 0..<4 { bitmap.pixels[index * 4 + channel] = 0 }
    }
    for index in rim {
        let offset = index * 4
        let r = Int(bitmap.pixels[offset]), g = Int(bitmap.pixels[offset + 1]), b = Int(bitmap.pixels[offset + 2])
        // Only plain greys are blended edge pixels; anything coloured is content.
        guard max(r, g, b) - min(r, g, b) <= 2, max(r, g, b) < backdropLevel else { continue }
        let coverage = 1 - Double(max(r, g, b)) / Double(backdropLevel)
        bitmap.pixels[offset] = 0
        bitmap.pixels[offset + 1] = 0
        bitmap.pixels[offset + 2] = 0
        bitmap.pixels[offset + 3] = UInt8((coverage * 255).rounded())
    }
}

// MARK: - Wallpaper

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// A dark, softly lit gradient in the spirit of a macOS wallpaper. Glows stay in
/// cool violet and blue so the module accents inside the notch stand out.
func drawWallpaper(in context: CGContext, size: CGSize) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(colorsSpace: space, colors: [color(0x2A2D4A), color(0x15162A)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

    let glows: [(x: CGFloat, y: CGFloat, radius: CGFloat, hex: UInt32, alpha: CGFloat)] = [
        (0.10, 1.00, 0.55, 0x7B5CFF, 0.55), // violet, top left
        (0.92, 0.90, 0.50, 0x2F7DFF, 0.45), // blue, top right
        (0.55, -0.20, 0.50, 0x4B3DB8, 0.35), // indigo, bottom center
    ]
    for glow in glows {
        let center = CGPoint(x: glow.x * size.width, y: glow.y * size.height)
        let radius = glow.radius * max(size.width, size.height)
        let gradient = CGGradient(
            colorsSpace: space, colors: [color(glow.hex, glow.alpha), color(glow.hex, 0)] as CFArray, locations: [0, 1]
        )!
        context.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: []
        )
    }

    // Faint vignette so edges recede on README's light and dark themes alike.
    let vignette = CGGradient(
        colorsSpace: space, colors: [color(0x000000, 0), color(0x000000, 0.35)] as CFArray, locations: [0.55, 1]
    )!
    let center = CGPoint(x: size.width / 2, y: size.height * 0.75)
    context.drawRadialGradient(
        vignette, startCenter: center, startRadius: 0, endCenter: center,
        endRadius: hypot(size.width, size.height) * 0.6, options: [.drawsAfterEndLocation]
    )
}

/// Draws the cut-out notch at the top center of a wallpaper canvas.
///
/// `cropHeight` trims the snapshot's empty bottom (in snapshot pixels) so the
/// canvas ends a fixed margin below the panel.
func compose(_ notch: Bitmap, canvasWidth: Int, cropHeight: Int, cornerRadius: CGFloat) -> Bitmap {
    var canvas = Bitmap(width: canvasWidth, height: cropHeight)
    let size = CGSize(width: canvasWidth, height: cropHeight)
    canvas.withContext { context in
        let bounds = CGRect(origin: .zero, size: size)
        context.addPath(CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        context.clip()
        drawWallpaper(in: context, size: size)
        let x = CGFloat(canvasWidth - notch.width) / 2
        let y = size.height - CGFloat(notch.height)
        context.draw(notch.cgImage(), in: CGRect(x: x, y: y, width: CGFloat(notch.width), height: CGFloat(notch.height)))
    }
    return canvas
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments.count == 2 else {
    fail("pass no arguments, or an Essentials and a Med School snapshot folder")
}
let productivity = arguments.first.map { URL(fileURLWithPath: $0) } ?? renderDemoSnapshots(kit: "essentials")
let medicine = arguments.last.map { URL(fileURLWithPath: $0) } ?? renderDemoSnapshots(kit: "medicine")
defer {
    if arguments.isEmpty {
        try? FileManager.default.removeItem(at: productivity)
        try? FileManager.default.removeItem(at: medicine)
    }
}
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func notch(_ name: String, in folder: URL) -> Bitmap {
    var bitmap = Bitmap(contentsOf: folder.appendingPathComponent("\(name).png"))
    cutOutNotch(&bitmap)
    return bitmap
}

func write(_ bitmap: Bitmap, as name: String) {
    bitmap.write(to: outputDirectory.appendingPathComponent("\(name).png"))
}

// Closed: the compact live activities beside the camera housing.
write(compose(notch("closed", in: productivity), canvasWidth: 1200, cropHeight: 160, cornerRadius: 24), as: "closed")
write(compose(notch("closed-pet", in: medicine), canvasWidth: 1200, cropHeight: 160, cornerRadius: 24), as: "closed-pet")

/// Feature grid tiles: snapshot file name, folder, README image name. Every
/// tile has the same size so the README grid lines up.
let tiles = [
    ("open-spotify", productivity, "now-playing"),
    ("open-planner", productivity, "today"),
    ("open-schedule", productivity, "schedule"),
    ("open-claudeUsage", productivity, "claude-usage"),
    ("open-system", productivity, "system"),
    ("open-claudeAsk", productivity, "ask-claude"),
    ("open-study", medicine, "study"),
    ("open-anki", medicine, "anki"),
    ("open-party", medicine, "party"),
    ("open-closet", medicine, "closet"),
    ("onboarding-kit", medicine, "onboarding"),
]
for (snapshot, folder, name) in tiles {
    write(compose(notch(snapshot, in: folder), canvasWidth: 1360, cropHeight: 520, cornerRadius: 24), as: name)
}

// MARK: - Animation

extension Bitmap {
    /// A copy redrawn at `scale` with high-quality interpolation.
    func scaled(by scale: CGFloat) -> Bitmap {
        let size = CGSize(width: (CGFloat(width) * scale).rounded(), height: (CGFloat(height) * scale).rounded())
        var result = Bitmap(width: Int(size.width), height: Int(size.height))
        let image = cgImage()
        result.withContext { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        return result
    }
}

/// Smooth start and end, like the app's springs (no linear motion).
func ease(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }

/// One wallpaper frame with notches drawn on top, each with its own opacity and
/// a scale anchored at the top center, as the notch grows from the camera housing.
func frame(_ layers: [(notch: Bitmap, alpha: CGFloat, scale: CGFloat)], width: Int, height: Int) -> Bitmap {
    var canvas = Bitmap(width: width, height: height)
    let size = CGSize(width: width, height: height)
    canvas.withContext { context in
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 24, cornerHeight: 24, transform: nil))
        context.clip()
        drawWallpaper(in: context, size: size)
        context.interpolationQuality = .high
        for layer in layers where layer.alpha > 0 {
            let w = CGFloat(layer.notch.width) * layer.scale
            let h = CGFloat(layer.notch.height) * layer.scale
            context.setAlpha(layer.alpha)
            context.draw(layer.notch.cgImage(), in: CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h))
        }
    }
    return canvas
}

/// Writes a looping GIF. Each frame shows for its own delay, so a held state is
/// one frame rather than many, which keeps the file small.
func writeGIF(_ frames: [(Bitmap, Double)], as name: String) {
    let url = outputDirectory.appendingPathComponent("\(name).gif")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
    ] as CFDictionary)
    for (bitmap, delay) in frames {
        CGImageDestinationAddImage(destination, bitmap.cgImage(), [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
    print(url.path)
}

/// The README hero: the closed notch with the pet opens into Study, switches
/// through a few tabs and the pet page, then closes again. Frames come from the
/// Med School kit's demo snapshots, drawn a little over half the snapshot scale
/// so the GIF stays under 2 MB.
func heroAnimation(from folder: URL) -> [(Bitmap, Double)] {
    let scale: CGFloat = 0.7
    let (width, height) = (1020, 380)
    let closed = notch("closed-pet", in: folder).scaled(by: scale)
    let pages = ["open-study", "open-planner", "open-anki", "open-party", "open-closet"]
        .map { notch($0, in: folder).scaled(by: scale) }
    let steps = 6
    let stepDelay = 0.05
    var frames: [(Bitmap, Double)] = []

    func resize(closed: Bitmap, open: Bitmap, opening: Bool) {
        for step in 1..<steps {
            var t = ease(CGFloat(step) / CGFloat(steps))
            if !opening { t = 1 - t }
            // The closed wings are gone a quarter of the way in, so the
            // two never read as a double exposure.
            let grow = 0.5 + 0.5 * t
            frames.append((frame([(closed, max(0, 1 - 4 * t), 1), (open, t, grow)], width: width, height: height), stepDelay))
        }
    }

    frames.append((frame([(closed, 1, 1)], width: width, height: height), 1.4))
    resize(closed: closed, open: pages[0], opening: true)
    // Tabs switch with a cut: a crossfade between two busy panels reads as a
    // double exposure, and the selected tab moving along the header already
    // shows what changed.
    for page in pages {
        frames.append((frame([(page, 1, 1)], width: width, height: height), 1.8))
    }
    resize(closed: closed, open: pages[pages.count - 1], opening: false)
    return frames
}

writeGIF(heroAnimation(from: medicine), as: "hero")

// MARK: - Social preview

/// A rounded system font, the same family the app uses for its type.
func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// GitHub's repository social preview (1280x640): the open Study panel at the
/// top, then the icon, name and pitch. GitHub crops about 40 pt from each edge
/// in some places, so everything stays inside that safe area.
func socialPreview(notch: Bitmap, icon: Bitmap) -> Bitmap {
    let size = CGSize(width: 1280, height: 640)
    var canvas = Bitmap(width: Int(size.width), height: Int(size.height))
    canvas.withContext { context in
        drawWallpaper(in: context, size: size)

        // The panel hangs from the top edge like the real notch.
        let scale: CGFloat = 0.8
        let notchSize = CGSize(width: CGFloat(notch.width) * scale, height: CGFloat(notch.height) * scale)
        context.interpolationQuality = .high
        context.draw(notch.cgImage(), in: CGRect(
            x: (size.width - notchSize.width) / 2, y: size.height - notchSize.height,
            width: notchSize.width, height: notchSize.height
        ))

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }

        let name = NSAttributedString(string: "Tabbi", attributes: [
            .font: roundedFont(size: 60, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let pitch = NSAttributedString(string: "A little cat for your laptop notch.", attributes: [
            .font: roundedFont(size: 26, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.72),
        ])
        let iconSide: CGFloat = 76
        let gap: CGFloat = 20
        let nameSize = name.size()
        let rowWidth = iconSide + gap + nameSize.width
        let rowBottom: CGFloat = 124
        context.draw(icon.cgImage(), in: CGRect(
            x: (size.width - rowWidth) / 2, y: rowBottom, width: iconSide, height: iconSide
        ))
        name.draw(at: CGPoint(
            x: (size.width - rowWidth) / 2 + iconSide + gap,
            y: rowBottom + (iconSide - nameSize.height) / 2
        ))
        let pitchSize = pitch.size()
        pitch.draw(at: CGPoint(x: (size.width - pitchSize.width) / 2, y: rowBottom - 24 - pitchSize.height))
    }
    return canvas
}

write(
    socialPreview(notch: notch("open-study", in: medicine), icon: Bitmap(contentsOf: outputDirectory.appendingPathComponent("icon.png"))),
    as: "social-preview"
)

// MARK: - Demo video

/// One caption line in the app's rounded type, centered on `centerY` (from the bottom).
func drawCaption(_ text: String, size: CGFloat, alpha: CGFloat, centerY: CGFloat, in context: CGContext, width: CGFloat) {
    guard alpha > 0 else { return }
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let caption = NSAttributedString(string: text, attributes: [
        .font: roundedFont(size: size, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.9 * alpha),
    ])
    let captionSize = caption.size()
    caption.draw(at: CGPoint(x: (width - captionSize.width) / 2, y: centerY - captionSize.height / 2))
}

/// Opacity of a caption shown from `start` to `end` seconds, with short fades.
func captionAlpha(at time: Double, from start: Double, to end: Double) -> CGFloat {
    let fade = 0.3
    guard time >= start, time < end else { return 0 }
    return ease(CGFloat(min(1, (time - start) / fade, (end - time) / fade)))
}

/// Renders the storyboard in docs/launch/video-storyboard.md: the closed notch
/// with the pet, open into Timer, cut through Today, Anki, Party and the
/// Closet, close again, then the icon and link. The last frame matches the
/// first, so the video loops cleanly. Frames go straight to ffmpeg as raw RGBA.
func renderDemoVideo(from folder: URL, width: Int, height: Int, scale: CGFloat, captionSize: CGFloat, to url: URL) {
    let fps = 30
    let duration = 20.0
    let size = CGSize(width: width, height: height)
    var wallpaper = Bitmap(width: width, height: height)
    wallpaper.withContext { drawWallpaper(in: $0, size: size) }
    let wallpaperImage = wallpaper.cgImage()
    let closed = notch("closed-pet", in: folder).cgImage()
    let shots: [(snapshot: String, start: Double, end: Double, caption: String)] = [
        ("open-study", 3.0, 6.0, "A focus timer that never hides behind a window."),
        ("open-planner", 6.0, 9.0, "Your tasks and what's next, at a glance."),
        ("open-anki", 9.0, 12.0, "Anki cards due, one click to study."),
        ("open-party", 12.0, 15.0, "Study with friends."),
        ("open-closet", 15.0, 17.5, "Your cat earns outfits as you study."),
    ]
    let pages = shots.map { notch($0.snapshot, in: folder).cgImage() }
    let icon = Bitmap(contentsOf: outputDirectory.appendingPathComponent("icon.png")).cgImage()
    // The open panel ends about 470 of the snapshot's 520 pixels down; captions
    // sit a little above the middle of the space below it.
    let panelBottom = size.height - 470 * scale
    let captionY = panelBottom * 0.58

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(width)x\(height)",
        "-r", "\(fps)", "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", url.path,
    ]
    let pipe = Pipe()
    process.standardInput = pipe
    do { try process.run() } catch { fail("could not run ffmpeg: \(error)") }

    func draw(_ image: CGImage, alpha: CGFloat, scale layerScale: CGFloat, in context: CGContext) {
        guard alpha > 0 else { return }
        let w = CGFloat(image.width) * layerScale
        let h = CGFloat(image.height) * layerScale
        context.setAlpha(alpha)
        context.draw(image, in: CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h))
        context.setAlpha(1)
    }

    var canvas = Bitmap(width: width, height: height)
    for index in 0..<Int(duration * Double(fps)) {
        let time = Double(index) / Double(fps)
        canvas.withContext { context in
            context.interpolationQuality = .high
            context.draw(wallpaperImage, in: CGRect(origin: .zero, size: size))
            switch time {
            case ..<2.5:
                // Slow push in on the closed notch.
                draw(closed, alpha: 1, scale: scale * (1 + 0.06 * ease(CGFloat(time / 2.5))), in: context)
                drawCaption("A little cat for your laptop notch.", size: captionSize,
                            alpha: captionAlpha(at: time, from: 0.2, to: 2.5), centerY: captionY, in: context, width: size.width)
            case ..<3.0, 17.5..<18.0:
                // The notch grows from the camera housing, or shrinks back.
                let opening = time < 3.0
                let progress = CGFloat((time - (opening ? 2.5 : 17.5)) / 0.5)
                let t = ease(opening ? progress : 1 - progress)
                draw(closed, alpha: max(0, 1 - 4 * t), scale: scale * (opening ? 1.06 : 1), in: context)
                draw(opening ? pages[0] : pages[pages.count - 1], alpha: t, scale: scale * (0.5 + 0.5 * t), in: context)
            case ..<17.5:
                let shot = shots.lastIndex { time >= $0.start } ?? 0
                draw(pages[shot], alpha: 1, scale: scale, in: context)
                drawCaption(shots[shot].caption, size: captionSize,
                            alpha: captionAlpha(at: time, from: shots[shot].start, to: shots[shot].end),
                            centerY: captionY, in: context, width: size.width)
            default:
                // The closed notch with the icon and the link, fading out
                // before the end so the loop starts on the same frame.
                draw(closed, alpha: 1, scale: scale, in: context)
                let alpha = captionAlpha(at: time, from: 18.2, to: 19.8)
                let iconSide = captionSize * 2.2
                context.setAlpha(alpha)
                context.draw(icon, in: CGRect(
                    x: (size.width - iconSide) / 2, y: captionY + captionSize * 0.9, width: iconSide, height: iconSide
                ))
                context.setAlpha(1)
                drawCaption("Free and open source. tabbinotch.com", size: captionSize,
                            alpha: alpha, centerY: captionY, in: context, width: size.width)
            }
        }
        pipe.fileHandleForWriting.write(Data(canvas.pixels))
    }
    try? pipe.fileHandleForWriting.close()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("ffmpeg could not write \(url.path)") }
    print(url.path)
}

let videoDirectory = root.appendingPathComponent("docs/launch/video")
let ffmpegCheck = Process()
ffmpegCheck.executableURL = URL(fileURLWithPath: "/usr/bin/env")
ffmpegCheck.arguments = ["ffmpeg", "-version"]
ffmpegCheck.standardOutput = FileHandle.nullDevice
ffmpegCheck.standardError = FileHandle.nullDevice
if (try? ffmpegCheck.run()) != nil, ({ ffmpegCheck.waitUntilExit(); return ffmpegCheck.terminationStatus == 0 })() {
    try? FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
    renderDemoVideo(from: medicine, width: 1920, height: 1080, scale: 1.3, captionSize: 46,
                    to: videoDirectory.appendingPathComponent("tabbi-demo.mp4"))
    renderDemoVideo(from: medicine, width: 1080, height: 1080, scale: 0.86, captionSize: 38,
                    to: videoDirectory.appendingPathComponent("tabbi-demo-square.mp4"))
} else {
    print("make-screenshots: ffmpeg not found, skipping the demo videos")
}
