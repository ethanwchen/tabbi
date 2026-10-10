#!/usr/bin/env swift
// Builds the Mac App Store screenshots in docs/appstore/screenshots and the
// App Preview video in docs/appstore/preview from the App Store edition's
// demo snapshots, following the production spec (eight shots, one layout).
//
//     swift docs/appstore/make-media.swift                                # render everything, then compose
//     swift docs/appstore/make-media.swift <panels> <coach> <accents> [<recording>]   # compose from existing folders
//
// Folders passed in must come from
//     TABBI_DEMO=1 swift run Tabbi --snapshot <panels> --edition appstore --tabs study,planner,anki,spotify,closet --scale 3 --transparent
//     TABBI_DEMO=1 swift run Tabbi --snapshot <coach> --edition appstore --tabs study,planner,anki,spotify,closet --scale 3 --transparent   # or the panels folder again
//     swift run PetGallery <accents> accents
//     TABBI_DEMO=1 TABBI_DEMO_FOCUS_LEFT=1126 swift run -c release Tabbi --record <recording>/opening --part opening --edition appstore --tabs study,planner,anki,spotify,closet
//     TABBI_DEMO=1 TABBI_DEMO_FOCUS_LEFT=5 swift run -c release Tabbi --record <recording>/story --part story --edition appstore --tabs study,planner,anki,spotify,closet
// Without a recording folder the preview is recorded fresh.
//
// Snapshots come from `--edition appstore`, so no tab the App Store build
// leaves out can show up, and from demo mode, so the data is fictional and
// private (no music app, Calendar, network or AI provider). Every shot uses
// the same tabs (Timer, Today, Flashcards, Now Playing and the Closet paw).
// Each screenshot is 2880x1800 (16:10), a flattened 8-bit sRGB PNG with no
// alpha, as App Store Connect requires. Copies at 1280x800 (`small/`) and at
// 540x338 (`gallery/`, the size the web product page shows) are for review.
//
// Layout: a cream canvas with a one-line Fredoka headline and a subcaption,
// over a full-bleed desktop stage (an original dune wallpaper with a plain
// translucent menu bar, no device and no Apple logo) with the real Large
// Tabbi panel hanging from the menu bar, drawn 1:1. The demo pet, Mochi in
// the same outfit as in the panel, sits on the front dune, drawn by the app's
// own pet renderer (PetGallery) and scaled up with nearest neighbor.
// Shot 5 is the night (dark) variant.
//
// The App Preview is a 1920x1080 H.264 movie at 30 fps with a silent stereo
// AAC track: the running app's notch window, recorded at 30 fps by
// `Tabbi --record`, on the same dune desktop with the storyboard's captions.

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
let grainURL = root.appendingPathComponent("site/img/grain.png")
let canvasSize = CGSize(width: 2880, height: 1800)
let reviewSizes = [("small", CGSize(width: 1280, height: 800)), ("gallery", CGSize(width: 540, height: 338))]

/// Pixels per point of the panel snapshots: the Large panel is drawn 1:1 at
/// about 1800 px wide, never scaled up.
let panelScale = 3.0
/// Pixels per point of the closed notch and the coach in shot 2, the one shot
/// without an open panel: the panels' scale, so the notch matches theirs.
let coachScale = panelScale
/// The tabs every shot shows: Essentials plus flashcards, and the Closet paw.
let storeTabs = "study,planner,anki,spotify,closet"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-media: \(message)\n".utf8))
    exit(1)
}

// MARK: - Sources

func run(_ arguments: [String], demo: Bool, environment extra: [String: String] = [:]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = root
    var environment = ProcessInfo.processInfo.environment
    if demo { environment["TABBI_DEMO"] = "1" }
    environment.merge(extra) { $1 }
    process.environment = environment
    do { try process.run() } catch { fail("could not run \(arguments.joined(separator: " ")): \(error)") }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fail("\(arguments.joined(separator: " ")) failed") }
}

func temporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("tabbi-appstore-\(name)-\(ProcessInfo.processInfo.processIdentifier)")
}

/// Renders fresh App Store edition demo snapshots of the store layout.
func renderDemoSnapshots(scale: Double, name: String) -> URL {
    let directory = temporaryFolder(name)
    run(["swift", "run", "Tabbi", "--snapshot", directory.path, "--edition", "appstore", "--tabs", storeTabs,
         "--scale", String(scale), "--transparent"], demo: true)
    return directory
}

/// Writes the demo pet's frames with the app's own pet renderer.
func renderAccents() -> URL {
    let directory = temporaryFolder("accents")
    run(["swift", "run", "PetGallery", directory.path, "accents"], demo: false)
    return directory
}

/// Records the App Preview's two parts from a release build of the running
/// app (`--record`): the opening shows the Timer at 18:42 as the panel opens,
/// and the story starts five seconds before the focus block ends.
func recordPreview() -> URL {
    let directory = temporaryFolder("recording")
    for (part, focusLeft) in [("opening", "1126"), ("story", "5")] {
        run(["swift", "run", "-c", "release", "Tabbi", "--record", directory.appendingPathComponent(part).path, "--part", part,
             "--edition", "appstore", "--tabs", storeTabs], demo: true, environment: ["TABBI_DEMO_FOCUS_LEFT": focusLeft])
    }
    return directory
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("cannot read \(url.path)") }
    return image
}

/// RGBA bytes of an image, row 0 at the top.
func pixels(of image: CGImage) -> [UInt8] {
    let (width, height) = (image.width, image.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bytes
}

/// The box of pixels more opaque than `threshold`, in top-left pixel space.
func opaqueBounds(of image: CGImage, threshold: UInt8 = 8) -> CGRect {
    let bytes = pixels(of: image)
    var (minX, minY, maxX, maxY) = (image.width, image.height, -1, -1)
    for y in 0..<image.height {
        for x in 0..<image.width where bytes[(y * image.width + x) * 4 + 3] > threshold {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { fail("an image is empty") }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// The image without its transparent margin, so it can be placed by its
/// edges. Every pixel that is not fully clear counts, so the faint tail of a
/// shadow is never cut into a hard edge on the light wallpaper.
func trimmed(_ image: CGImage) -> CGImage {
    image.cropping(to: opaqueBounds(of: image, threshold: 0))!
}

// MARK: - Drawing helpers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// `amount` of `other` blended into `hex`.
func mix(_ hex: UInt32, _ other: UInt32, _ amount: Double) -> UInt32 {
    [16, 8, 0].reduce(0) { result, shift in
        let a = Double((hex >> shift) & 0xFF), b = Double((other >> shift) & 0xFF)
        return result | UInt32((a + (b - a) * amount).rounded()) << shift
    }
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

func textLine(_ text: String, font: CTFont, color: CGColor, tracking: CGFloat = 0) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
}

/// Draws one line centered on `centerX` with its baseline at `baseline`, in a
/// top-left coordinate space. The type shrinks (to `minimumSize` at most) when
/// the line would run into the side margins.
func drawCentered(_ text: String, size: CGFloat, minimumSize: CGFloat, weight: CGFloat, tracking: CGFloat,
                  color: CGColor, centerX: CGFloat, baseline: CGFloat, maxWidth: CGFloat, in context: CGContext) {
    var size = size
    var line = textLine(text, font: fredoka(size: size, weight: weight), color: color, tracking: size * tracking)
    while CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth && size > minimumSize {
        size -= 2
        line = textLine(text, font: fredoka(size: size, weight: weight), color: color, tracking: size * tracking)
    }
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    if width > maxWidth { FileHandle.standardError.write(Data("make-media: \"\(text)\" runs into the margins\n".utf8)) }
    context.saveGState()
    // Text draws upright in a flipped context only with a flipped text matrix.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
    CTLineDraw(line, context)
    context.restoreGState()
}

func roundedRect(_ rect: CGRect, topRadius: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> CGPath {
    // Top-left coordinates: minY is the top edge.
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), radius: bottomRight)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), radius: bottomLeft)
    path.closeSubpath()
    return path
}

func radialGlow(_ hex: UInt32, alpha: CGFloat, center: CGPoint, radius: CGFloat, in context: CGContext) {
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Draws `image` upright into `rect` of a top-left context, optionally mirrored.
func drawImage(_ image: CGImage, in rect: CGRect, mirrored: Bool = false, smooth: Bool = true, context: CGContext) {
    context.saveGState()
    context.translateBy(x: mirrored ? rect.maxX : rect.minX, y: rect.maxY)
    context.scaleBy(x: mirrored ? -1 : 1, y: -1)
    context.interpolationQuality = smooth ? .high : .none
    context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    context.restoreGState()
}

// MARK: - Scene

/// Where the desktop stage starts: everything above is the caption block.
let stageTop: CGFloat = 540
/// The menu bar of a notched MacBook Pro screen, 37 pt at the panel's scale.
let menuBarHeight: CGFloat = 37 * panelScale

struct Palette {
    let canvas: UInt32, glow: UInt32, glowAlpha: CGFloat, headline: UInt32, subcaption: UInt32
    let sky: [UInt32], sun: UInt32, sunAlpha: CGFloat, dunes: [UInt32], menuBar: (UInt32, CGFloat)

    static let day = Palette(
        canvas: 0xFBF5EA, glow: 0xFFE6C2, glowAlpha: 0.7, headline: 0x2B1F17, subcaption: 0x6B5546,
        sky: [0xF9D9B5, 0xF5BE93, 0xEFA27C], sun: 0xFFF1D6, sunAlpha: 0.9,
        dunes: [0xE8946E, 0xDC7F5E, 0xCB6B50], menuBar: (0xFFFFFF, 0.55)
    )
    static let night = Palette(
        canvas: 0x231915, glow: 0x5B3B2B, glowAlpha: 0.6, headline: 0xFFF4E6, subcaption: 0xD9C4B0,
        sky: [0x1C1524, 0x1C1524, 0x2A1F33], sun: 0x5B3B5B, sunAlpha: 0.35,
        dunes: [0x3D2B3F, 0x30223A, 0x241A2D], menuBar: (0x000000, 0.45)
    )
}

/// The three dune lines from back to front, measured from the canvas bottom
/// so the same shapes fit the screenshots and the shorter preview canvas.
let duneShapes: [(rise: CGFloat, amplitude: CGFloat, phase: CGFloat, waves: CGFloat)] = [
    (440, 70, 0.3, 1.3), (320, 60, 1.9, 1.7), (190, 50, 3.4, 1.1),
]

func duneY(_ index: Int, x: CGFloat, canvas: CGSize) -> CGFloat {
    let dune = duneShapes[index]
    return canvas.height - dune.rise - dune.amplitude * sin(x / canvas.width * .pi * 2 * dune.waves + dune.phase)
}

/// The original dune wallpaper, full bleed from the stage top, with the sun
/// low behind the panel and, at night, a sky of pixel stars.
func drawStage(_ palette: Palette, night: Bool, canvas: CGSize, top: CGFloat = stageTop, menuBar: CGFloat = menuBarHeight,
               in context: CGContext) {
    let stage = CGRect(x: 0, y: top, width: canvas.width, height: canvas.height - top)
    let sky = CGGradient(colorsSpace: sRGB, colors: palette.sky.map { color($0) } as CFArray, locations: [0, 0.6, 1])!
    context.saveGState()
    context.clip(to: stage)
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: stage.minY), end: CGPoint(x: 0, y: stage.maxY), options: [])
    radialGlow(palette.sun, alpha: palette.sunAlpha, center: CGPoint(x: canvas.width / 2, y: canvas.height - 520),
               radius: 760, in: context)
    if night {
        // 18 stars at 6 px per pixel, placed by a fixed seed so every run matches.
        var seed: UInt64 = 0x7AB81
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        context.setFillColor(color(0xFFF4E6, 0.85))
        for _ in 0..<18 {
            let x = (next() * (canvas.width - 120) / 6).rounded() * 6 + 60
            let y = (stage.minY + menuBar + 30 + next() * (canvas.height - 560 - stage.minY - menuBar)) / 6
            context.fill(CGRect(x: x, y: y.rounded() * 6, width: 6, height: 6))
        }
    }
    for (index, hex) in palette.dunes.enumerated() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: canvas.height))
        for step in 0...96 {
            let x = CGFloat(step) / 96 * canvas.width
            path.addLine(to: CGPoint(x: x, y: duneY(index, x: x, canvas: canvas)))
        }
        path.addLine(to: CGPoint(x: canvas.width, y: canvas.height))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(hex))
        context.fillPath()
    }
    // A plain menu bar: no Apple logo, no menus and no status items.
    context.setFillColor(color(palette.menuBar.0, palette.menuBar.1))
    context.fill(CGRect(x: 0, y: stage.minY, width: canvas.width, height: menuBar))
    context.restoreGState()
}

/// The cream canvas's paper grain, tiled at 3 percent.
func drawGrain(canvas: CGSize, in context: CGContext) {
    let grain = loadImage(grainURL)
    context.saveGState()
    context.setAlpha(0.03)
    context.setBlendMode(.multiply)
    var y: CGFloat = 0
    while y < stageTop {
        var x: CGFloat = 0
        while x < canvas.width {
            drawImage(grain, in: CGRect(x: x, y: y, width: CGFloat(grain.width), height: CGFloat(grain.height)),
                      smooth: false, context: context)
            x += CGFloat(grain.width)
        }
        y += CGFloat(grain.height)
    }
    context.restoreGState()
}

/// One frame of the demo pet from PetGallery's accents. Animated items (the
/// King's Cape) have a frame per tick of their loop; the brightest one, with
/// the glimmer out, is used.
struct PetPose {
    var look = "demo"
    var animation: String
    var frame = 0

    func image(in folder: URL) -> CGImage {
        let ticks = (0..<16).map { folder.appendingPathComponent("accent-\(look)-\(animation)-\(frame)-\($0).png") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !ticks.isEmpty else { fail("no accent frame \(look) \(animation) \(frame) in \(folder.path)") }
        return ticks.map(loadImage).max { brightness($0) < brightness($1) }!
    }

    private func brightness(_ image: CGImage) -> Int {
        let bytes = pixels(of: image)
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) { $0 + Int(bytes[$1]) + Int(bytes[$1 + 1]) }
    }
}

enum Side { case left, center, right }

/// Draws the pet on the front dune at `pixel` screen pixels per sprite pixel
/// (nearest neighbor, integer only), with a soft contact shadow, facing the
/// panel. Returns the box of the pet's visible pixels.
@discardableResult
func drawPet(_ sprite: CGImage, side: Side, pixel: Int, canvas: CGSize, in context: CGContext) -> CGRect {
    let bounds = opaqueBounds(of: sprite, threshold: 0)
    let scale = CGFloat(pixel)
    let centerX: CGFloat = switch side {
    case .left: 380
    case .center: canvas.width / 2
    case .right: canvas.width - 380
    }
    // The front dune's top stays above this line, so the paws always rest
    // on sand.
    let ground = canvas.height - 100
    let width = bounds.width * scale
    context.saveGState()
    context.translateBy(x: centerX, y: ground)
    context.scaleBy(x: 1, y: 0.16)
    radialGlow(0x000000, alpha: 0.12, center: .zero, radius: width * 0.6, in: context)
    context.restoreGState()
    let mirrored = side == .right
    let spriteX = mirrored ? CGFloat(sprite.width) - bounds.maxX : bounds.minX
    let rect = CGRect(
        x: centerX - width / 2 - spriteX * scale, y: ground - bounds.maxY * scale,
        width: CGFloat(sprite.width) * scale, height: CGFloat(sprite.height) * scale
    )
    drawImage(sprite, in: rect, mirrored: mirrored, smooth: false, context: context)
    return CGRect(x: centerX - width / 2, y: ground - bounds.height * scale, width: width, height: bounds.height * scale)
}

struct Shot {
    let file: String
    let caption: String
    let subcaption: String
    /// The open panel snapshot, or nil for the closed notch with the coach.
    var panel: String?
    var night = false
    /// The active module's accent, blended into the glow.
    var tint: UInt32
    /// Where the hero element sits in the panel, as fractions of its size.
    var hero = CGPoint(x: 0.5, y: 0.5)
    var pet: PetPose
    var petSide: Side
    var petPixel = 12
}

/// The closed notch, centered at the top of the stage like a MacBook's: 190
/// by 32 pt at the coach's scale, as the coach snapshot draws it.
func closedNotchRect(in canvas: CGSize) -> CGRect {
    CGRect(x: canvas.width / 2 - 95 * coachScale, y: stageTop, width: 190 * coachScale, height: 32 * coachScale)
}

/// Composes one shot into an opaque RGB bitmap of the canvas size.
func compose(_ shot: Shot) -> CGImage {
    let canvas = canvasSize
    let palette = shot.night ? Palette.night : .day
    let context = CGContext(
        data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    // Lay out in top-left coordinates like the design spec.
    context.translateBy(x: 0, y: canvas.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color(palette.canvas))
    context.fill(CGRect(origin: .zero, size: canvas))
    if !shot.night { drawGrain(canvas: canvas, in: context) }

    let panel = shot.panel.map { trimmed(loadImage(panelFolder.appendingPathComponent("\($0).png"))) }
    let panelRect = panel.map {
        CGRect(x: ((canvas.width - CGFloat($0.width)) / 2).rounded(), y: stageTop, width: CGFloat($0.width), height: CGFloat($0.height))
    } ?? closedNotchRect(in: canvas)
    let hero = CGPoint(x: panelRect.minX + panelRect.width * shot.hero.x, y: panelRect.minY + panelRect.height * shot.hero.y)
    radialGlow(mix(palette.glow, shot.tint, 0.06), alpha: palette.glowAlpha, center: hero, radius: 1400, in: context)

    let margin: CGFloat = 160
    drawCentered(shot.caption, size: 168, minimumSize: 150, weight: 600, tracking: -0.01,
                 color: color(palette.headline), centerX: canvas.width / 2, baseline: 310,
                 maxWidth: canvas.width - margin * 2, in: context)
    drawCentered(shot.subcaption, size: 76, minimumSize: 64, weight: 500, tracking: 0,
                 color: color(palette.subcaption), centerX: canvas.width / 2, baseline: 430,
                 maxWidth: canvas.width - margin * 2, in: context)

    // With the notch closed, the menu bar is as tall as the notch.
    drawStage(palette, night: shot.night, canvas: canvas, menuBar: panel == nil ? closedNotchRect(in: canvas).height : menuBarHeight,
              in: context)
    let pet = drawPet(shot.pet.image(in: accentFolder), side: shot.petSide, pixel: shot.petPixel, canvas: canvas, in: context)
    // The panel's own body, without its soft shadow, must stay clear.
    let body = panel.map { opaqueBounds(of: $0, threshold: 250).offsetBy(dx: panelRect.minX, dy: panelRect.minY) }
    if pet.intersects(body ?? panelRect) {
        FileHandle.standardError.write(Data("make-media: the pet overlaps the panel in \(shot.file)\n".utf8))
    }

    guard let panel else {
        drawCoach(canvas: canvas, in: context)
        return context.makeImage()!
    }
    // The panel 1:1, with the snapshot's own shadow only.
    drawImage(panel, in: panelRect, smooth: false, context: context)
    return context.makeImage()!
}

/// Shot 2: the closed notch centered at the top edge, like a MacBook's, with
/// the pet out beside it, mid-cheer, and the coach's celebration bubble, as
/// the app draws them at one moment. The coach snapshot holds the notch's
/// right part; the rest of the notch is drawn from the app's geometry (190
/// by 32 pt, 10 pt bottom corners). The bubble reaches about 330 pt right of
/// the notch, which sets the scale: at 3 pixels per point (the panels' own)
/// it ends well inside the canvas.
func drawCoach(canvas: CGSize, in context: CGContext) {
    let coach = trimmed(loadImage(coachFolder.appendingPathComponent("coach-celebrate.png")))
    let notch = closedNotchRect(in: canvas)
    let hidden = notch.width - 92 * coachScale
    context.addPath(roundedRect(CGRect(x: notch.minX, y: notch.minY, width: hidden + 2, height: notch.height),
                                topRadius: 0, bottomLeft: 10 * coachScale, bottomRight: 0))
    context.setFillColor(color(0x000000))
    context.fillPath()
    let coachRect = CGRect(x: notch.minX + hidden, y: notch.minY, width: CGFloat(coach.width), height: CGFloat(coach.height))
    if coachRect.maxX > canvas.width - 80 {
        FileHandle.standardError.write(Data("make-media: the coach bubble runs past the canvas margin in shot 2\n".utf8))
    }
    drawImage(coach, in: coachRect, smooth: false, context: context)
}

/// A smaller copy for the readability checks, scaled with high quality.
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
let framesPerSecond: Int32 = 30

/// One part of the footage `Tabbi --record` wrote: the notch window's frames
/// at 2x, each shown from its time until the next one's, and the
/// storyboard's beats.
struct Recording {
    let folder: URL
    let times: [Double]
    let beats: [String: Double]
    let length: Double
    let notchHeight: CGFloat

    init(_ folder: URL) {
        self.folder = folder
        let url = folder.appendingPathComponent("frames.json")
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let times = manifest["frames"] as? [Double], !times.isEmpty,
              let beats = manifest["beats"] as? [[String: Any]],
              let length = manifest["length"] as? Double,
              let scale = manifest["scale"] as? Double,
              let notch = manifest["notch"] as? [String: Double], let height = notch["height"]
        else { fail("no recording in \(folder.path); run Tabbi --record first") }
        self.times = times
        self.beats = Dictionary(uniqueKeysWithValues: beats.compactMap { beat in
            (beat["name"] as? String).flatMap { name in (beat["time"] as? Double).map { (name, $0) } }
        })
        self.length = length
        notchHeight = CGFloat(height * scale)
    }

    func beat(_ name: String) -> Double {
        guard let time = beats[name] else { fail("the recording in \(folder.path) has no beat \(name)") }
        return time
    }

    /// The frame on screen at `time`.
    func frame(at time: Double) -> Int {
        var low = 0, high = times.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if times[middle] <= time { low = middle } else { high = middle - 1 }
        }
        return low
    }

    func image(_ index: Int) -> CGImage {
        loadImage(folder.appendingPathComponent(String(format: "frame-%04d.png", index)))
    }
}

/// One caption pill of the preview, from `start` to `end` in seconds.
struct PreviewCaption {
    let text: String
    let start: Double
    let end: Double
    var small = false
    var icon = false
}

/// The spec's dissolves and caption fades: 8 frames, eased.
let fadeSeconds = 8 / Double(framesPerSecond)

func eased(_ t: Double) -> CGFloat {
    let t = min(1, max(0, t))
    return CGFloat(t * t * (3 - 2 * t))
}

/// The app icon without the macOS icon grid's transparent margin, so the
/// visible icon is 120 px and lines up with the caption pills.
let appIcon = trimmed(loadImage(root.appendingPathComponent("docs/brand/assets/tabbi-icon-1024.png")))

/// Draws a caption pill (Fredoka SemiBold on cream at 92 percent, 28 px
/// corners, 28 by 16 px padding) with its text's left edge and baseline at
/// `origin`, the app icon at 120 px to its left for the closing caption.
/// Returns the pill's top edge.
@discardableResult
func drawCaption(_ caption: PreviewCaption, x: CGFloat, baseline: CGFloat, alpha: CGFloat, in context: CGContext) -> CGFloat {
    let size: CGFloat = caption.small ? 40 : 60
    let line = textLine(caption.text, font: fredoka(size: size, weight: 600), color: color(0x2B1F17))
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    var left = x
    context.saveGState()
    context.setAlpha(alpha)
    let pill = CGRect(x: left, y: baseline - ascent - 16, width: width + 56, height: ascent + descent + 32)
    if caption.icon {
        let side: CGFloat = 120
        drawImage(appIcon, in: CGRect(x: left, y: (pill.midY - side / 2).rounded(), width: side, height: side), context: context)
        left += side + 20
    }
    let placed = pill.offsetBy(dx: left - x, dy: 0)
    context.addPath(CGPath(roundedRect: placed, cornerWidth: 28, cornerHeight: 28, transform: nil))
    context.setFillColor(color(0xFBF5EA, 0.92))
    context.fillPath()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: placed.minX + 28, y: baseline)
    CTLineDraw(line, context)
    context.restoreGState()
    return placed.minY
}

/// The App Preview, composed from the two recorded parts: the dune desktop
/// at 1920x1080 with the notch window drawn 1:1 (2x, so native size) from
/// the top center, the opening, a dissolve to the session's last seconds
/// ("25 minutes later") and the story, with the storyboard's captions
/// bottom left. Only the recording and the caption overlays are on screen
/// (Guideline 2.3.4): no pet, pointer or UI is drawn.
func composePreview(opening: Recording, story: Recording) -> (count: Int, frame: (Int) -> CGImage) {
    // The story joins once the panel's open spring has settled.
    let storyStart = 0.7
    let cut = opening.length
    let total = cut + story.length - storyStart
    let storyTime = { (time: Double) in time - cut + storyStart }
    let outputTime = { (time: Double) in time - storyStart + cut }

    let captions = [
        PreviewCaption(text: "A cozy timer in your notch", start: 0, end: cut),
        PreviewCaption(text: "Every session ends in a cheer", start: cut, end: outputTime(story.beat("closet"))),
        // Above the caption it joins, so it comes after it.
        PreviewCaption(text: "25 minutes later", start: cut, end: cut + 2, small: true),
        PreviewCaption(text: "Earn points, dress your cat", start: outputTime(story.beat("closet")), end: outputTime(story.beat("today"))),
        PreviewCaption(text: "Today, right up top", start: outputTime(story.beat("today")), end: outputTime(story.beat("tomorrow"))),
        PreviewCaption(text: "Plan tomorrow tonight", start: outputTime(story.beat("tomorrow")), end: outputTime(story.beat("music"))),
        PreviewCaption(text: "Music without switching apps", start: outputTime(story.beat("music")), end: outputTime(story.beat("flashcards"))),
        PreviewCaption(text: "Flashcards between tasks", start: outputTime(story.beat("flashcards")), end: outputTime(story.beat("end"))),
        PreviewCaption(text: "Tabbi", start: outputTime(story.beat("end")), end: total, icon: true),
    ]
    for caption in captions where !caption.small && caption.end - caption.start < 2.5 {
        FileHandle.standardError.write(Data("make-media: the preview caption \"\(caption.text)\" shows under 2.5 s\n".utf8))
    }

    let stage: CGImage = {
        let context = CGContext(
            data: nil, width: Int(previewSize.width), height: Int(previewSize.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.translateBy(x: 0, y: previewSize.height)
        context.scaleBy(x: 1, y: -1)
        drawStage(.day, night: false, canvas: previewSize, top: 0, menuBar: opening.notchHeight, in: context)
        return context.makeImage()!
    }()

    // Decoded frames, kept while they are on screen.
    var cache: [String: CGImage] = [:]
    func footage(_ recording: Recording, at time: Double) -> CGImage {
        let index = recording.frame(at: time)
        let key = "\(recording.folder.lastPathComponent)-\(index)"
        if let image = cache[key] { return image }
        if cache.count > 4 { cache.removeAll() }
        let image = recording.image(index)
        cache[key] = image
        return image
    }

    let count = Int((total * Double(framesPerSecond)).rounded())
    return (count, { index in
        let time = Double(index) / Double(framesPerSecond)
        let context = CGContext(
            data: nil, width: Int(previewSize.width), height: Int(previewSize.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.translateBy(x: 0, y: previewSize.height)
        context.scaleBy(x: 1, y: -1)
        // The stage with a frame on it, faded as one layer, so a dissolve
        // never lets the stage show through the panel.
        func layer(_ image: CGImage, alpha: CGFloat) {
            context.saveGState()
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawImage(stage, in: CGRect(origin: .zero, size: previewSize), smooth: false, context: context)
            let left = ((previewSize.width - CGFloat(image.width)) / 2).rounded()
            drawImage(image, in: CGRect(x: left, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)),
                      smooth: false, context: context)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        if time < cut {
            layer(footage(opening, at: time), alpha: 1)
        } else {
            let dissolve = eased((time - cut) / fadeSeconds)
            if dissolve < 1 { layer(footage(opening, at: cut), alpha: 1) }
            layer(footage(story, at: storyTime(time)), alpha: dissolve)
        }
        var top: CGFloat = 1000
        for caption in captions where time >= caption.start && time < caption.end {
            // Each caption fades in and out over 8 frames; the first is
            // there from frame one and the last stays to the end.
            let fadeIn = caption.start == 0 ? 1 : eased((time - caption.start) / fadeSeconds)
            let fadeOut = caption.end >= total ? 1 : eased((caption.end - time) / fadeSeconds)
            let baseline = caption.small ? top - 36 : 1000
            let pillTop = drawCaption(caption, x: 64, baseline: baseline, alpha: min(fadeIn, fadeOut), in: context)
            if !caption.small { top = pillTop }
        }
        return context.makeImage()!
    })
}

/// Writes the App Preview: H.264 High at 30 fps and a silent stereo AAC
/// track (App Store Connect expects previews to carry audio).
func writePreview(frameCount: Int, frame: @escaping (Int) -> CGImage, to url: URL) {
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

    let total = Double(frameCount) / Double(framesPerSecond)
    let totalAudioFrames = Int(total * sampleRate)

    // Each input pulls its data when the writer is ready for it, so neither
    // can starve the other while the writer interleaves them.
    let group = DispatchGroup()
    group.enter()
    var frameIndex = 0
    video.requestMediaDataWhenReady(on: DispatchQueue(label: "preview.video")) {
        while video.isReadyForMoreMediaData {
            guard frameIndex < frameCount else {
                video.markAsFinished()
                group.leave()
                return
            }
            let image = frame(frameIndex)

            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer!), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: sRGB,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            )!
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: previewSize))
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
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: framesPerSecond))
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { fail("preview writing failed: \(String(describing: writer.error))") }
    print(String(format: "%@ (%.1f s)", url.path, total))
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || (3...4).contains(arguments.count) else {
    fail("pass no arguments, or a panel snapshot folder, a coach snapshot folder, an accents folder and optionally a recording folder")
}
let panelFolder = arguments.isEmpty ? renderDemoSnapshots(scale: panelScale, name: "panels") : URL(fileURLWithPath: arguments[0])
// The coach shares the panels' scale, so one render serves both.
let coachFolder = arguments.isEmpty ? panelFolder : URL(fileURLWithPath: arguments[1])
let accentFolder = arguments.isEmpty ? renderAccents() : URL(fileURLWithPath: arguments[2])
let recordingFolder = URL(fileURLWithPath: "/tmp/none")
defer {
    let temporary = (arguments.isEmpty ? [panelFolder, accentFolder] : []) + (arguments.count == 4 ? [] : [recordingFolder])
    for folder in temporary { try? FileManager.default.removeItem(at: folder) }
}

let reviewDirectories = reviewSizes.map { (outputDirectory.appendingPathComponent($0.0), $0.1) }
for directory in [outputDirectory] + reviewDirectories.map(\.0) {
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

/// Module accents: Timer, Today, Closet, Now Playing and Flashcards.
let orange: UInt32 = 0xFF9F43, purple: UInt32 = 0xA78BFA, gold: UInt32 = 0xF5C451
let green: UInt32 = 0x4ADE80, blue: UInt32 = 0x60A5FA

/// The shots in listing order (the spec's ordered set; the weekly recap
/// ships in the App Store build, so the closer is 8a).
let shots: [Shot] = [
    Shot(file: "1-timer", caption: "A cozy timer in your notch", subcaption: "Focus with a little cat who cheers you on.",
         panel: "open-large-study", tint: orange, hero: CGPoint(x: 0.22, y: 0.5),
         pet: PetPose(animation: "typing", frame: 2), petSide: .left),
    Shot(file: "2-cheer", caption: "Every session ends in a cheer", subcaption: "Your cat celebrates, and you earn points.",
         tint: orange, pet: PetPose(animation: "celebrate", frame: 2), petSide: .center),
    Shot(file: "3-closet", caption: "Earn points, dress your cat", subcaption: "Every focus day fills your chart.",
         panel: "open-large-closet", tint: gold, hero: CGPoint(x: 0.25, y: 0.5),
         pet: PetPose(animation: "idle"), petSide: .right, petPixel: 13),
    Shot(file: "4-today", caption: "Today, right up top", subcaption: "Tasks, calendar and your timer at a glance.",
         panel: "open-large-planner", tint: purple, pet: PetPose(animation: "typing", frame: 6), petSide: .left),
    Shot(file: "5-tomorrow", caption: "Plan tomorrow tonight", subcaption: "Look back at yesterday, then line up tomorrow.",
         panel: "open-planner-tomorrow", night: true, tint: purple,
         pet: PetPose(animation: "sleep"), petSide: .left),
    Shot(file: "6-music", caption: "Music without switching apps", subcaption: "Play, skip and like songs from the notch.",
         panel: "open-large-spotify", tint: green, hero: CGPoint(x: 0.25, y: 0.5),
         pet: PetPose(look: "headphones", animation: "coffee", frame: 4), petSide: .right),
    Shot(file: "7-flashcards", caption: "Flashcards between tasks", subcaption: "See what is due and review in one click.",
         panel: "open-large-anki", tint: blue, pet: PetPose(animation: "typing", frame: 9), petSide: .left),
    Shot(file: "8-recap", caption: "Your week, wrapped up", subcaption: "Hours focused, best day and your cat's new look.",
         panel: "open-recap-large-heavy", tint: gold, pet: PetPose(animation: "celebrate", frame: 3), petSide: .right),
]
for shot in shots {
    let image = compose(shot)
    writePNG(image, to: outputDirectory.appendingPathComponent("\(shot.file).png"))
    for (directory, size) in reviewDirectories {
        writePNG(scaled(image, to: size), to: directory.appendingPathComponent("\(shot.file).png"))
    }
}

