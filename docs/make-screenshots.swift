#!/usr/bin/env swift
// Builds the README screenshots in docs/images from the app's demo snapshots.
//
//     swift docs/make-screenshots.swift              # render demo snapshots, then compose
//     swift docs/make-screenshots.swift <snapshots>  # compose from an existing snapshot folder
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

/// Renders fresh demo snapshots into a temporary folder and returns it.
func renderDemoSnapshots() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tabbi-snapshots-\(ProcessInfo.processInfo.processIdentifier)")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "run", "-c", "release", "Tabbi", "--snapshot", directory.path]
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

let arguments = CommandLine.arguments.dropFirst()
let snapshots = arguments.first.map { URL(fileURLWithPath: $0) } ?? renderDemoSnapshots()
defer { if arguments.isEmpty { try? FileManager.default.removeItem(at: snapshots) } }
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func notch(_ name: String) -> Bitmap {
    var bitmap = Bitmap(contentsOf: snapshots.appendingPathComponent("\(name).png"))
    cutOutNotch(&bitmap)
    return bitmap
}

/// Snapshot file name → README image name.
let modules = [
    ("open-spotify", "now-playing"),
    ("open-system", "system"),
    ("open-claudeUsage", "claude-usage"),
    ("open-planner", "today"),
    ("open-claudeAsk", "ask-claude"),
]

// Hero: the Now Playing panel on a wide strip of desktop.
compose(notch("open-spotify"), canvasWidth: 2000, cropHeight: 560, cornerRadius: 24)
    .write(to: outputDirectory.appendingPathComponent("hero.png"))

// Closed: the compact live activity beside the camera housing.
compose(notch("closed"), canvasWidth: 1200, cropHeight: 160, cornerRadius: 24)
    .write(to: outputDirectory.appendingPathComponent("closed.png"))

for (snapshot, name) in modules {
    compose(notch(snapshot), canvasWidth: 1360, cropHeight: 520, cornerRadius: 24)
        .write(to: outputDirectory.appendingPathComponent("\(name).png"))
}
