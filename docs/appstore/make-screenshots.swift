#!/usr/bin/env swift
// Builds the Mac App Store screenshots in docs/appstore/screenshots from the
// App Store edition's demo snapshots.
//
//     swift docs/appstore/make-screenshots.swift                         # render demo snapshots, then compose
//     swift docs/appstore/make-screenshots.swift <essentials> <medicine>  # compose from existing snapshot folders
//
// Snapshots come from `--edition appstore`, so no tab the App Store build
// leaves out can show up. Each screenshot is 2880x1800 (a 1440x900 pt Retina
// screen, which App Store Connect accepts for Mac apps): the open notch hangs
// from the top edge of a soft wallpaper, with a short caption below it. The
// files are JPEG without alpha, which App Store Connect requires and which
// keeps them small. Demo mode (TABBI_DEMO=1) keeps the data realistic and
// private: no Spotify, Calendar, network, or claude CLI.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = root.appendingPathComponent("docs/appstore/screenshots")
let canvasSize = CGSize(width: 2880, height: 1800)

/// Grey level of `SnapshotRenderer`'s stand-in desktop (`Color(white: 0.16)`).
let backdropLevel = 41

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-screenshots: \(message)\n".utf8))
    exit(1)
}

// MARK: - Snapshots

/// Renders fresh App Store edition demo snapshots of one kit into a temporary folder.
func renderDemoSnapshots(kit: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tabbi-appstore-snapshots-\(kit)-\(ProcessInfo.processInfo.processIdentifier)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "swift", "run", "-c", "release", "Tabbi", "--snapshot", directory.path,
        "--edition", "appstore", "--kit", kit,
    ]
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

    /// Rows from the top down to the last one with any visible pixel.
    var contentHeight: Int {
        // Row 0 of `pixels` is the top of the image.
        for row in stride(from: height - 1, through: 0, by: -1) {
            let start = row * width * 4
            if stride(from: start + 3, to: start + width * 4, by: 4).contains(where: { pixels[$0] > 0 }) {
                return row + 1
            }
        }
        return 0
    }

    /// Writes an opaque JPEG (App Store Connect rejects screenshots with alpha).
    func writeJPEG(to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { fail("cannot write \(url.path)") }
        CGImageDestinationAddImage(destination, cgImage(), [
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
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

// MARK: - Composition

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// A soft twilight wallpaper: a muted blue to plum gradient with two gentle
/// glows tinted by the shot's module accent, light enough that the black notch
/// reads as part of the screen edge and calm enough not to compete with it.
func drawWallpaper(in context: CGContext, size: CGSize, glow: UInt32) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let base = CGGradient(
        colorsSpace: space, colors: [color(0x3B4470), color(0x2A2A4E), color(0x1E1C36)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    context.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

    let glows: [(x: CGFloat, y: CGFloat, radius: CGFloat, hex: UInt32, alpha: CGFloat)] = [
        (0.08, 0.95, 0.55, 0x8C7BFF, 0.45),
        (0.92, 0.10, 0.60, glow, 0.30),
        (0.70, 0.95, 0.40, 0x5A8CFF, 0.30),
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
}

/// A rounded system font, the same family the app uses for its type.
func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// Panel scale over the 2x snapshot. Larger than life (a real 1440x900 pt
/// screen would show it at 1) so the panel stays readable in the store's
/// smaller previews, and small enough that the text stays crisp.
let notchScale: CGFloat = 1.75

/// One screenshot: the cut-out notch hanging from the top center, then a
/// headline and a line of detail centered in the space below it.
func screenshot(notch: Bitmap, headline: String, detail: String, glow: UInt32) -> Bitmap {
    var canvas = Bitmap(width: Int(canvasSize.width), height: Int(canvasSize.height))
    canvas.withContext { context in
        drawWallpaper(in: context, size: canvasSize, glow: glow)

        let notchSize = CGSize(width: CGFloat(notch.width) * notchScale, height: CGFloat(notch.height) * notchScale)
        context.interpolationQuality = .high
        context.draw(notch.cgImage(), in: CGRect(
            x: (canvasSize.width - notchSize.width) / 2, y: canvasSize.height - notchSize.height,
            width: notchSize.width, height: notchSize.height
        ))

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }

        let title = NSAttributedString(string: headline, attributes: [
            .font: roundedFont(size: 104, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let subtitle = NSAttributedString(string: detail, attributes: [
            .font: roundedFont(size: 52, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.72),
        ])
        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        let gap: CGFloat = 28
        let blockHeight = titleSize.height + gap + subtitleSize.height
        // Centered between the panel's real bottom edge (the snapshot keeps
        // empty backdrop below it) and the canvas bottom, nudged up a little
        // toward the optical center.
        let space = canvasSize.height - CGFloat(notch.contentHeight) * notchScale
        let bottom = (space - blockHeight) / 2 + 60
        subtitle.draw(at: CGPoint(x: (canvasSize.width - subtitleSize.width) / 2, y: bottom))
        title.draw(at: CGPoint(x: (canvasSize.width - titleSize.width) / 2, y: bottom + subtitleSize.height + gap))
    }
    return canvas
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments.count == 2 else {
    fail("pass no arguments, or an Essentials and a Med School snapshot folder")
}
let essentials = arguments.first.map { URL(fileURLWithPath: $0) } ?? renderDemoSnapshots(kit: "essentials")
let medicine = arguments.last.map { URL(fileURLWithPath: $0) } ?? renderDemoSnapshots(kit: "medicine")
defer {
    if arguments.isEmpty {
        try? FileManager.default.removeItem(at: essentials)
        try? FileManager.default.removeItem(at: medicine)
    }
}
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// The shots in listing order: snapshot, folder, caption, glow tint, file name.
/// Now Playing is left out because its panel shows another company's app badge.
let shots: [(String, URL, String, String, UInt32, String)] = [
    ("open-planner", essentials, "Your day, one click away", "Tasks and what is next, right in the notch.", 0x9B7BFF, "1-today"),
    ("open-study", medicine, "Study in focused rounds", "Pick a method, track your time, earn points.", 0xF2A65A, "2-study"),
    ("open-closet", medicine, "A little study buddy", "Dress up your pet with the points you earn.", 0xF2C14E, "3-pet"),
    ("open-focus", essentials, "Stay in the zone", "A focus timer with calming sounds.", 0x3FD6B8, "4-focus"),
    ("open-schedule", essentials, "See where the day goes", "Plan your hours on a simple timeline.", 0xF07A63, "5-schedule"),
]
for (snapshot, folder, headline, detail, glow, name) in shots {
    var notch = Bitmap(contentsOf: folder.appendingPathComponent("\(snapshot).png"))
    cutOutNotch(&notch)
    screenshot(notch: notch, headline: headline, detail: detail, glow: glow)
        .writeJPEG(to: outputDirectory.appendingPathComponent("\(name).jpg"))
}
