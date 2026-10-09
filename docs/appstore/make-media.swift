#!/usr/bin/env swift
// Builds the Mac App Store screenshots in docs/appstore/screenshots and the
// App Preview video in docs/appstore/preview from the App Store edition's
// demo snapshots.
//
//     swift docs/appstore/make-media.swift                         # render demo snapshots, then compose
//     swift docs/appstore/make-media.swift <essentials> <medicine>  # compose from existing snapshot folders
//
// Snapshot folders passed in must come from
// `TABBI_DEMO=1 swift run Tabbi --snapshot <dir> --edition appstore --kit <kit> --scale 2.7 --transparent`.
//
// Snapshots come from `--edition appstore`, so no tab the App Store build
// leaves out can show up, and from demo mode, so the data is realistic and
// private (no music app, Calendar, network or claude CLI). Each screenshot
// is 2880x1800 (16:10), a flattened 8-bit sRGB PNG with no alpha, as App
// Store Connect requires. A 1280x800 copy of each goes to `small/` to check
// that the captions and the panel still read at the size the store shows.
//
// Every shot shares one layout: a cream canvas with a soft golden glow, a
// one-line Fredoka caption at the top, and below it the top edge of a generic
// screen (an original warm wallpaper, a menu bar strip and a black notch)
// with the real open Tabbi panel hanging from it. No device bezel is drawn,
// since Apple only allows its own unmodified device frames.
//
// The App Preview is a 1920x1080 H.264 movie at 30 fps with a silent stereo
// AAC track, built only from the same scenes: the panel opens out of the
// notch, then each scene holds its caption for a few seconds and crossfades
// to the next, and an end card with the app icon closes it.

import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = root.appendingPathComponent("docs/appstore/screenshots")
let fontURL = root.appendingPathComponent("docs/appstore/fonts/Fredoka.ttf")
let canvasSize = CGSize(width: 2880, height: 1800)
let smallSize = CGSize(width: 1280, height: 800)

/// Pixels per point of the panel snapshots. Rendering at the final size keeps
/// the panel crisp: it is drawn 1:1, never scaled up.
let panelScale = 2.7

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-media: \(message)\n".utf8))
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
        "swift", "run", "Tabbi", "--snapshot", directory.path, "--edition", "appstore", "--kit", kit,
        "--scale", String(panelScale), "--transparent",
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

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read \(url.path)") }
    return image
}

/// The panel without the snapshot's transparent margin, so it can be placed
/// by its visible edges.
func trimmed(_ image: CGImage) -> CGImage {
    let (width, height) = (image.width, image.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    // Row 0 of `pixels` is the top of the image. Faint anti-aliasing counts
    // as empty so the box hugs the shape.
    var (minX, minY, maxX, maxY) = (width, height, -1, -1)
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { fail("a panel snapshot is empty") }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
}

// MARK: - Drawing helpers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Fredoka (SIL Open Font License, bundled in docs/appstore/fonts) at a weight
/// on its variable `wght` axis: 500 is Medium, 600 SemiBold.
func fredoka(size: CGFloat, weight: CGFloat) -> CTFont {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
          let base = descriptors.first
    else { fail("cannot load \(fontURL.path)") }
    let wght = 0x7767_6874 // 'wght'
    let descriptor = CTFontDescriptorCreateCopyWithVariation(base, wght as CFNumber, weight)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

/// Draws one line of text centered on `centerX` with its top (the font's
/// ascent line) at `top`, in a top-left coordinate space. Returns the bottom
/// of the line (the descent line).
@discardableResult
func drawCentered(_ text: String, font: CTFont, color: CGColor, centerX: CGFloat, top: CGFloat, in context: CGContext) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
    context.saveGState()
    // Text draws upright in a flipped context only with a flipped text matrix.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: centerX - width / 2, y: top + ascent)
    CTLineDraw(line, context)
    context.restoreGState()
    return top + ascent + descent
}

func roundedRect(_ rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
    // Top-left coordinates: minY is the top edge.
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
    path.closeSubpath()
    return path
}

func radialGlow(_ hex: UInt32, alpha: CGFloat, center: CGPoint, radius: CGFloat, in context: CGContext) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// MARK: - Scene

/// The generic screen's top edge, below the caption, running off the bottom
/// of the canvas. Its notch is a plain black shape at roughly the panel's
/// scale; the open panel hangs over it.
func screenRect(in canvas: CGSize) -> CGRect {
    CGRect(x: (canvas.width - 1840) / 2, y: 470, width: 1840, height: canvas.height - 470 + 80)
}

let menuBarHeight: CGFloat = 74
let notchSize = CGSize(width: 400, height: 80)

/// An original warm wallpaper: an apricot sky over three layers of soft
/// rolling hills, with a low sun. Calm and bright so the black panel stands
/// out without the picture competing for attention.
func drawWallpaper(in context: CGContext, rect: CGRect) {
    let sky = CGGradient(
        colorsSpace: sRGB, colors: [color(0xF9D9B5), color(0xF5BE93), color(0xEFA27C)] as CFArray, locations: [0, 0.6, 1]
    )!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    radialGlow(0xFFF1D6, alpha: 0.9, center: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + 700), radius: 420, in: context)

    let hills: [(base: CGFloat, amplitude: CGFloat, phase: CGFloat, waves: CGFloat, hex: UInt32)] = [
        (880, 70, 0.3, 1.3, 0xE8946E),
        (1000, 60, 1.9, 1.7, 0xDC7F5E),
        (1130, 50, 3.4, 1.1, 0xCB6B50),
    ]
    for hill in hills {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...96 {
            let t = CGFloat(step) / 96
            let x = rect.minX + t * rect.width
            let y = rect.minY + hill.base - hill.amplitude * sin(t * .pi * 2 * hill.waves + hill.phase)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(hill.hex))
        context.fillPath()
    }
}

/// A small original pixel cat (a ginger tabby sitting and looking up), drawn
/// with nearest neighbour pixels as a quiet nod to the app's pet.
let catArt = """
    .o..........o...
    .oo........oo...
    .oPo......oPo...
    .oPPooooooPPo...
    .ogggggggggggo..
    oggGgggggggGggo.
    oggggggggggggggo
    oggKWggggggKWggo
    oggKKggggggKKggo
    ogpgggwNNwgggpgo
    .oggggwwwwggggo.
    ..oogggggggg oo.
    ...ogggwwgggo...
    ..oggggwwggggo..
    ..ogGgwwwwgGgo.oo
    ..oggwwwwwwggo.og
    ..oggwwwwwwggoog.
    ..ogGggggggGgoog.
    ..ogggggggggggo..
    ..owwoooooowwo...
    """

let catColors: [Character: UInt32] = [
    "o": 0x2A231D, "g": 0xF0A257, "G": 0xD9823A, "P": 0xF2A0A6, "p": 0xF7B9B2,
    "K": 0x2A231D, "W": 0xFFFFFF, "w": 0xFFF6EA, "N": 0xE57F86,
]

func drawCat(in context: CGContext, origin: CGPoint, pixel: CGFloat, facingLeft: Bool) {
    let rows = catArt.split(separator: "\n").map(Array.init)
    let columns = rows.map(\.count).max() ?? 0
    for (row, line) in rows.enumerated() {
        for (column, symbol) in line.enumerated() {
            guard let hex = catColors[symbol] else { continue }
            let x = facingLeft ? CGFloat(columns - 1 - column) : CGFloat(column)
            context.setFillColor(color(hex))
            context.fill(CGRect(x: origin.x + x * pixel, y: origin.y + CGFloat(row) * pixel, width: pixel, height: pixel))
        }
    }
}

struct Shot {
    let file: String
    let snapshot: String
    let folder: URL
    let caption: String
    let subcaption: String?
    var dark = false
    /// Which lower corner the cat sits in.
    var catOnLeft = true
}

func notchRect(in canvas: CGSize) -> CGRect {
    CGRect(x: canvas.width / 2 - notchSize.width / 2, y: screenRect(in: canvas).minY, width: notchSize.width, height: notchSize.height)
}

/// A critically damped spring from 0 to 1, close to the app's own open
/// animation, so the preview never moves linearly.
func spring(_ t: CGFloat) -> CGFloat {
    guard t > 0 else { return 0 }
    let omega: CGFloat = 9
    return min(1, 1 - (1 + omega * t) * exp(-omega * t))
}

/// Composes one shot into an opaque RGB bitmap of `canvas` size (pixels at
/// the screenshot scale). `reveal` below 1 draws the panel partway out of the
/// notch, for the preview's opening: a black shape grows from the notch to
/// the panel's size and the panel's content grows and fades in with it.
/// Without `captions` it is the bare backdrop the preview passes through
/// between scenes.
func compose(_ shot: Shot, canvas: CGSize = canvasSize, reveal: CGFloat = 1, captions: Bool = true) -> CGImage {
    let panel = trimmed(loadImage(shot.folder.appendingPathComponent("\(shot.snapshot).png")))
    let screen = screenRect(in: canvas)
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    // Lay out in top-left coordinates like the design spec.
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)

    let background: UInt32 = shot.dark ? 0x2A231D : 0xFBF7F0
    let ink: UInt32 = shot.dark ? 0xFBF7F0 : 0x2A231D
    context.setFillColor(color(background))
    context.fill(CGRect(origin: .zero, size: canvas))

    let panelSize = CGSize(width: panel.width, height: panel.height)
    let panelRect = CGRect(x: (canvas.width - panelSize.width) / 2, y: screen.minY, width: panelSize.width, height: panelSize.height)
    radialGlow(0xF4D57E, alpha: shot.dark ? 0.18 : 0.25, center: CGPoint(x: panelRect.midX, y: panelRect.midY), radius: 1300, in: context)

    let captionBottom = !captions ? 0 : drawCentered(
        shot.caption, font: fredoka(size: 128, weight: 600), color: color(ink),
        centerX: canvas.width / 2, top: 140, in: context
    )
    if captions, let subcaption = shot.subcaption {
        drawCentered(
            subcaption, font: fredoka(size: 56, weight: 500), color: color(ink, 0.7),
            centerX: canvas.width / 2, top: captionBottom + 32 - 20, in: context
        )
    }

    // The screen: wallpaper, menu bar strip and notch, rounded at the top.
    let notch = notchRect(in: canvas)
    context.saveGState()
    context.addPath(roundedRect(screen, topRadius: 40, bottomRadius: 0))
    context.clip()
    drawWallpaper(in: context, rect: screen)
    context.setFillColor(color(0xFFFFFF, 0.85))
    context.fill(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: menuBarHeight))
    context.addPath(roundedRect(notch, topRadius: 0, bottomRadius: 28))
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    // The cat sits on the wallpaper in a lower corner, clear of the panel.
    let pixel: CGFloat = 11
    let catWidth = 17 * pixel, catHeight = 20 * pixel
    let catX = shot.catOnLeft ? screen.minX + 150 : screen.maxX - 150 - catWidth
    drawCat(in: context, origin: CGPoint(x: catX, y: canvas.height - 90 - catHeight), pixel: pixel, facingLeft: !shot.catOnLeft)

    guard reveal > 0 else { return context.makeImage()! }
    // Shadow offsets ignore the flip, so a negative height falls downward.
    let shadow = { (strength: CGFloat) in
        context.setShadow(offset: CGSize(width: 0, height: -40), blur: 80, color: color(0x2A231D, 0.25 * strength))
    }
    let contentAlpha = min(1, max(0, (reveal - 0.45) / 0.55))
    if reveal < 1 {
        // The growing black shape, from the notch to the panel's frame.
        let lerp = { (a: CGFloat, b: CGFloat) in a + (b - a) * reveal }
        let shape = CGRect(
            x: lerp(notch.minX, panelRect.minX), y: screen.minY,
            width: lerp(notch.width, panelRect.width), height: lerp(notch.height, panelRect.height)
        )
        context.saveGState()
        shadow(reveal)
        context.addPath(roundedRect(shape, topRadius: 0, bottomRadius: lerp(28, 64)))
        context.setFillColor(color(0x000000, 1 - contentAlpha))
        context.fillPath()
        context.restoreGState()
        // The content grows with the shape, scaled down, never up.
        context.saveGState()
        context.setAlpha(contentAlpha)
        context.translateBy(x: shape.minX, y: shape.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(panel, in: CGRect(origin: .zero, size: shape.size))
        context.restoreGState()
        return context.makeImage()!
    }

    // The panel, drawn 1:1 with its soft shadow. The image is drawn through a
    // local flip so it stays upright in the top-left space.
    context.saveGState()
    shadow(1)
    context.translateBy(x: panelRect.minX, y: panelRect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .none
    context.draw(panel, in: CGRect(origin: .zero, size: panelSize))
    context.restoreGState()

    return context.makeImage()!
}

/// A smaller copy for the readability check, scaled with high quality.
func scaled(_ image: CGImage, to size: CGSize) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: size))
    return context.makeImage()!
}

/// Writes an opaque 8-bit sRGB PNG (App Store Connect rejects alpha).
func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
    print(url.path)
}

// MARK: - App Preview

let previewDirectory = root.appendingPathComponent("docs/appstore/preview")
let previewSize = CGSize(width: 1920, height: 1080)
/// The preview's scenes are composed at the screenshots' pixel scale on a
/// 16:9 canvas, then scaled down to `previewSize`, so the panel is never
/// scaled up.
let previewCanvas = CGSize(width: 2880, height: 1620)
let iconURL = root.appendingPathComponent("docs/brand/assets/tabbi-icon-1024.png")
let framesPerSecond: Int32 = 30

/// The closing card: the app icon and name on the cream canvas.
func composeEndCard(canvas: CGSize) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color(0xFBF7F0))
    context.fill(CGRect(origin: .zero, size: canvas))
    radialGlow(0xF4D57E, alpha: 0.25, center: CGPoint(x: canvas.width / 2, y: canvas.height / 2), radius: 1300, in: context)

    // The icon file has the standard transparent margin around its shape.
    let iconSide: CGFloat = 640
    let iconRect = CGRect(x: (canvas.width - iconSide) / 2, y: 250, width: iconSide, height: iconSide)
    context.saveGState()
    context.translateBy(x: iconRect.minX, y: iconRect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.draw(loadImage(iconURL), in: CGRect(origin: .zero, size: iconRect.size))
    context.restoreGState()

    let nameBottom = drawCentered(
        "Tabbi", font: fredoka(size: 160, weight: 600), color: color(0x2A231D),
        centerX: canvas.width / 2, top: iconRect.maxY + 10, in: context
    )
    drawCentered(
        "A cozy little panel in your notch.", font: fredoka(size: 64, weight: 500), color: color(0x2A231D, 0.7),
        centerX: canvas.width / 2, top: nameBottom + 12, in: context
    )
    return context.makeImage()!
}

/// One stretch of the preview. Each scene after the first starts with a
/// transition inside its own duration: the scene before fades to `backdrop`
/// (the scene without caption or panel), then this one fades in from it, so
/// two captions never show on top of each other.
struct PreviewScene {
    let seconds: Double
    let backdrop: CGImage
    /// The frame at a time from the scene's start.
    let frame: (Double) -> CGImage
}

let crossfadeSeconds = 0.6

/// Writes the App Preview: H.264 High at 30 fps and a silent stereo AAC
/// track (App Store Connect expects previews to carry audio).
func writePreview(_ scenes: [PreviewScene], to url: URL) {
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { fail("cannot write \(url.path)") }

    let width = Int(previewSize.width), height = Int(previewSize.height)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 12_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
            AVVideoExpectedSourceFrameRateKey: framesPerSecond,
            AVVideoMaxKeyFrameIntervalKey: framesPerSecond,
        ],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    let sampleRate = 48_000.0
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 256_000,
    ])
    for input in [video, audio] {
        input.expectsMediaDataInRealTime = false
        writer.add(input)
    }
    guard writer.startWriting() else { fail("cannot start the preview: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)

    // Silence as 16-bit interleaved stereo PCM, 1024 frames per buffer.
    var pcm = AudioStreamBasicDescription(
        mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
    )
    var audioFormat: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: &pcm, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &audioFormat
    )
    func silence(at frame: Int, count: Int) -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let bytes = count * 4
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block!, formatDescription: audioFormat!, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample
        )
        return sample!
    }

    // Every frame in order, as (scene, time from the scene start).
    var frames: [(scene: Int, time: Double)] = []
    for (index, scene) in scenes.enumerated() {
        let count = Int((scene.seconds * Double(framesPerSecond)).rounded())
        frames += (0..<count).map { (index, Double($0) / Double(framesPerSecond)) }
    }
    let total = Double(frames.count) / Double(framesPerSecond)
    let totalAudioFrames = Int(total * sampleRate)

    // Each input pulls its data when the writer is ready for it, so neither
    // can starve the other while the writer interleaves them.
    let group = DispatchGroup()
    group.enter()
    var frameIndex = 0
    var lastFrames: [Int: CGImage] = [:]
    video.requestMediaDataWhenReady(on: DispatchQueue(label: "preview.video")) {
        while video.isReadyForMoreMediaData {
            guard frameIndex < frames.count else {
                video.markAsFinished()
                group.leave()
                return
            }
            let (sceneIndex, time) = frames[frameIndex]
            let image = scenes[sceneIndex].frame(time)
            lastFrames[sceneIndex] = image
            let previous = sceneIndex > 0 ? lastFrames[sceneIndex - 1] : nil
            let half = crossfadeSeconds / 2
            let (from, to, fade): (CGImage?, CGImage, CGFloat) = switch previous {
            case let previous? where time < half:
                (previous, scenes[sceneIndex].backdrop, spring(CGFloat(time / half) * 0.7))
            case _? where time < crossfadeSeconds:
                (scenes[sceneIndex].backdrop, image, spring(CGFloat((time - half) / half) * 0.7))
            default:
                (nil, image, 1)
            }

            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer!), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: sRGB,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            context.interpolationQuality = .high
            let bounds = CGRect(origin: .zero, size: previewSize)
            if let from, fade < 1 { context.draw(from, in: bounds) }
            context.setAlpha(fade)
            context.draw(to, in: bounds)
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: framesPerSecond))
            frameIndex += 1
        }
    }
    group.enter()
    var audioWritten = 0
    audio.requestMediaDataWhenReady(on: DispatchQueue(label: "preview.audio")) {
        while audio.isReadyForMoreMediaData {
            guard audioWritten < totalAudioFrames else {
                audio.markAsFinished()
                group.leave()
                return
            }
            let count = min(1024, totalAudioFrames - audioWritten)
            audio.append(silence(at: audioWritten, count: count))
            audioWritten += count
        }
    }
    group.wait()

    let done = DispatchSemaphore(value: 0)
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames.count), timescale: framesPerSecond))
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { fail("preview writing failed: \(String(describing: writer.error))") }
    print(String(format: "%@ (%.1f s)", url.path, total))
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

let smallDirectory = outputDirectory.appendingPathComponent("small")
for directory in [outputDirectory, smallDirectory] {
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

/// The shots in listing order.
let shots: [Shot] = [
    Shot(file: "1-cozy", snapshot: "open-study", folder: medicine,
         caption: "Your notch, but cozy", subcaption: "A little panel of tabs, right where you look."),
    Shot(file: "2-focus", snapshot: "open-focus", folder: essentials,
         caption: "Focus in one glance", subcaption: "A gentle timer with calming sounds.", catOnLeft: false),
    Shot(file: "3-today", snapshot: "open-planner", folder: essentials,
         caption: "Today, right up top", subcaption: "Your to-dos and what is next.", dark: true),
    Shot(file: "4-closet", snapshot: "open-closet", folder: medicine,
         caption: "Earn points, dress your cat", subcaption: "Study time turns into hats and outfits.", catOnLeft: false),
    Shot(file: "5-flashcards", snapshot: "open-anki", folder: medicine,
         caption: "Flashcards between tasks", subcaption: "Review what is due without leaving your work."),
    Shot(file: "6-music", snapshot: "open-spotify", folder: essentials,
         caption: "Music without switching apps", subcaption: "See and control what is playing.", catOnLeft: false),
    Shot(file: "7-free", snapshot: "onboarding-modules", folder: essentials,
         caption: "Free and open source", subcaption: "Pick your tabs and make it yours."),
]
for shot in shots {
    let image = compose(shot)
    writePNG(image, to: outputDirectory.appendingPathComponent("\(shot.file).png"))
    writePNG(scaled(image, to: smallSize), to: smallDirectory.appendingPathComponent("\(shot.file).png"))
}

// The preview reuses the shots: the opening one rises out of the notch, then
// the timer, Today, the wardrobe and flashcards, and the end card. Today uses
// the light canvas here so the background does not flash between scenes.
let previewShots = [shots[0], shots[1], shots[2], shots[3], shots[4]].map { shot -> Shot in
    var light = shot
    light.dark = false
    return light
}
let downscale = { (image: CGImage) in scaled(image, to: previewSize) }
let backdrop = { (shot: Shot) in downscale(compose(shot, canvas: previewCanvas, reveal: 0, captions: false)) }
let closed = downscale(compose(previewShots[0], canvas: previewCanvas, reveal: 0))
let opened = downscale(compose(previewShots[0], canvas: previewCanvas))
let openingStart = 0.6, openingSeconds = 0.9
var scenes = [PreviewScene(seconds: 4.4, backdrop: backdrop(previewShots[0])) { time in
    if time < openingStart { return closed }
    let progress = (time - openingStart) / openingSeconds
    guard progress < 1 else { return opened }
    return downscale(compose(previewShots[0], canvas: previewCanvas, reveal: spring(CGFloat(progress) * 0.8)))
}]
for shot in previewShots.dropFirst() {
    let still = downscale(compose(shot, canvas: previewCanvas))
    scenes.append(PreviewScene(seconds: 3.6, backdrop: backdrop(shot)) { _ in still })
}
// The end card passes through the plain cream canvas.
let cream = CGContext(
    data: nil, width: Int(previewSize.width), height: Int(previewSize.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
cream.setFillColor(color(0xFBF7F0))
cream.fill(CGRect(origin: .zero, size: previewSize))
let endCard = downscale(composeEndCard(canvas: previewCanvas))
scenes.append(PreviewScene(seconds: 4, backdrop: cream.makeImage()!) { _ in endCard })
try? FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
writePreview(scenes, to: previewDirectory.appendingPathComponent("tabbi-app-preview.mp4"))
