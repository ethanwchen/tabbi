#!/usr/bin/env swift
// Renders the DMG window background for an edition as two PNGs, 660x400 at
// 72 dpi and 1320x800 at 144 dpi, which make-dmg.sh merges into one HiDPI TIFF.
//
//   usage: swift packaging/dmg/render-background.swift <name> <output-dir>
//
// The art is drawn from code (no binary design files) so it stays reproducible
// and reviewable, like scripts/make-icon.swift. Geometry must match
// packaging/dmg/settings.py: icons are 128 pt, centered at (150, 180) and
// (510, 180) in a 660x400 window.
//
// Finder draws the icon labels itself, and over a background picture it draws
// them black even in Dark Mode (checked on macOS 26). So the art is dark like
// the notch, and each label sits on a light pill that keeps black text sharp.
//
// The window's 400 pt height includes Finder's title bar, so only the top
// 368 pt or so are visible; nothing important sits below y = 340.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Layout (points, y-down)

let size = CGSize(width: 660, height: 400)
let iconSize: CGFloat = 128
let appCenter = CGPoint(x: 150, y: 180)
let applicationsCenter = CGPoint(x: 510, y: 180)
/// Where Finder centers a 13 pt label under a 128 pt icon (measured on macOS 26).
let labelCenterY: CGFloat = 263

// MARK: - Palette (mirrors the app icon in scripts/make-icon.swift)

struct RGB {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
    func ns(_ alpha: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// The icon's deep navy field, from its lit top to its shaded bottom.
let ink = RGB(0x24335F)
let inkMid = RGB(0x17214A)
let inkDeep = RGB(0x0D1430)
let inkLight = RGB(0x4660A8)
/// The British Shorthair's pale silver-beige fur, its pink-tan nose and its
/// grey-green eye.
let fur = RGB(0xE6DFD5)
let nose = RGB(0xD29A8A)
let iris = RGB(0x9AA889)
/// The cat's shaded silver-beige, with a relative luminance near 0.5, so
/// Finder's black label text reaches about 11:1 contrast without the pill
/// glaring on the navy.
let labelPill = RGB(0xCAC1B5)

// MARK: - Drawing helpers

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

func glow(_ ctx: CGContext, _ color: RGB, at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(gradient([(0, color.cg(alpha)), (1, color.cg(0))]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// The notch silhouette hanging from the top edge, the same shape as the app icon's.
func notchPath(width w: CGFloat, height h: CGFloat, centerX: CGFloat, shoulder: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let left = centerX - w / 2, right = centerX + w / 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: left - shoulder, y: 0))
    p.addQuadCurve(to: CGPoint(x: left, y: shoulder), control: CGPoint(x: left, y: 0))
    p.addLine(to: CGPoint(x: left, y: h - bottomRadius))
    p.addQuadCurve(to: CGPoint(x: left + bottomRadius, y: h), control: CGPoint(x: left, y: h))
    p.addLine(to: CGPoint(x: right - bottomRadius, y: h))
    p.addQuadCurve(to: CGPoint(x: right, y: h - bottomRadius), control: CGPoint(x: right, y: h))
    p.addLine(to: CGPoint(x: right, y: shoulder))
    p.addQuadCurve(to: CGPoint(x: right + shoulder, y: 0), control: CGPoint(x: right, y: 0))
    p.closeSubpath()
    return p
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: rounded, size: size) ?? base
}

/// Draws one line of text centered on `centerX`, with its cap height centered on `centerY`.
func drawText(_ text: String, font: NSFont, color: NSColor, centerX: CGFloat, centerY: CGFloat, kern: CGFloat = 0) {
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let width = attributed.size().width
    // In a flipped context the origin is the line's top; place the cap height's center on centerY.
    let top = centerY - font.capHeight / 2 - (font.ascender - font.capHeight)
    attributed.draw(at: CGPoint(x: centerX - width / 2, y: top))
}

// MARK: - The background

func drawBackground(in ctx: CGContext, name: String) {
    let bounds = CGRect(origin: .zero, size: size)

    // Base: the icon's ink, lit at the top and deepening toward the bottom.
    ctx.drawLinearGradient(
        gradient([(0, ink.cg()), (0.65, inkMid.cg()), (1, inkDeep.cg())]),
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: bounds.maxY), options: [])
    glow(ctx, inkLight, at: CGPoint(x: bounds.midX, y: 0), radius: 300, alpha: 0.35)

    // Soft light pooling under each icon: the cat's pale fur, then a cool navy blue.
    glow(ctx, fur, at: appCenter, radius: 150, alpha: 0.10)
    glow(ctx, inkLight, at: applicationsCenter, radius: 150, alpha: 0.30)

    // A faint dotted grid gives the dark field some texture without competing.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.035))
    for x in stride(from: CGFloat(12), to: bounds.maxX, by: 24) {
        for y in stride(from: CGFloat(12), to: bounds.maxY, by: 24) {
            ctx.fillEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
        }
    }

    // The notch, with the cat peeking out of it: one half-lidded eye and the icon's checkmark wink.
    let notchWidth: CGFloat = 132, notchHeight: CGFloat = 34
    let notch = notchPath(width: notchWidth, height: notchHeight, centerX: bounds.midX, shoulder: 8, bottomRadius: 12)
    glow(ctx, RGB(0xFFFFFF), at: CGPoint(x: bounds.midX, y: notchHeight), radius: 120, alpha: 0.05)
    ctx.addPath(notch)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.addPath(notch)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.setLineWidth(1)
    ctx.strokePath()
    let eyeY = notchHeight / 2 + 1
    let eye = CGPoint(x: bounds.midX - 12, y: eyeY)
    glow(ctx, iris, at: eye, radius: 11, alpha: 0.5)
    // The heavy lid: a flat top that slopes down toward the nose cuts the round iris.
    let lidOuter = CGPoint(x: eye.x - 6, y: eye.y - 1.5), lidInner = CGPoint(x: eye.x + 6, y: eye.y + 0.5)
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: lidOuter.x, y: lidOuter.y))
    lid.addLine(to: CGPoint(x: lidInner.x, y: lidInner.y))
    lid.addLine(to: CGPoint(x: lidInner.x, y: eye.y + 8))
    lid.addLine(to: CGPoint(x: lidOuter.x, y: eye.y + 8))
    lid.closeSubpath()
    ctx.saveGState()
    ctx.addPath(lid)
    ctx.clip()
    ctx.setFillColor(iris.cg())
    ctx.fillEllipse(in: CGRect(x: eye.x - 4.5, y: eye.y - 4.5, width: 9, height: 9))
    ctx.restoreGState()
    ctx.move(to: CGPoint(x: lidOuter.x + 1, y: lidOuter.y + 0.1))
    ctx.addLine(to: CGPoint(x: lidInner.x - 1, y: lidInner.y - 0.1))
    ctx.setStrokeColor(fur.cg())
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    ctx.strokePath()
    let wink = CGPoint(x: bounds.midX + 12, y: eyeY)
    glow(ctx, fur, at: wink, radius: 11, alpha: 0.35)
    let check = CGMutablePath()
    check.move(to: CGPoint(x: wink.x - 5, y: wink.y))
    check.addLine(to: CGPoint(x: wink.x - 1.5, y: wink.y + 3.5))
    check.addLine(to: CGPoint(x: wink.x + 5, y: wink.y - 4))
    ctx.saveGState()
    ctx.addPath(check)
    ctx.setStrokeColor(fur.cg())
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Title and hint, quiet so the two icons stay the primary element.
    drawText("Install \(name)", font: roundedFont(20, .semibold), color: NSColor(white: 1, alpha: 0.92),
             centerX: bounds.midX, centerY: 74)
    drawText("Drag \(name) into the Applications folder", font: roundedFont(13, .medium),
             color: fur.ns(0.66), centerX: bounds.midX, centerY: 98)

    // The arrow: a gentle arc from the app to Applications, from the cat's pink nose to its pale fur.
    let gap: CGFloat = 20
    let start = CGPoint(x: appCenter.x + iconSize / 2 + gap, y: appCenter.y)
    let end = CGPoint(x: applicationsCenter.x - iconSize / 2 - gap, y: applicationsCenter.y)
    let control = CGPoint(x: (start.x + end.x) / 2, y: appCenter.y - 34)
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: control)

    // Arrowhead along the curve's end tangent (control -> end).
    let angle = atan2(end.y - control.y, end.x - control.x)
    let headLength: CGFloat = 13, headSpread: CGFloat = 0.55
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - headLength * cos(angle - headSpread), y: end.y - headLength * sin(angle - headSpread)))
    head.addLine(to: end)
    head.addLine(to: CGPoint(x: end.x - headLength * cos(angle + headSpread), y: end.y - headLength * sin(angle + headSpread)))

    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(4)
    ctx.addPath(arc)
    ctx.addPath(head)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, nose.cg()), (1, fur.cg())]),
                           start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    glow(ctx, fur, at: end, radius: 26, alpha: 0.22)

    // Label pills, so Finder's black label text reads on the dark art.
    let pillWidth: CGFloat = 116, pillHeight: CGFloat = 22
    for center in [appCenter, applicationsCenter] {
        let pill = CGRect(x: center.x - pillWidth / 2, y: labelCenterY - pillHeight / 2, width: pillWidth, height: pillHeight)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil))
        ctx.setFillColor(labelPill.cg())
        ctx.fillPath()
    }

    // Footer: what happens next, well clear of the bottom edge that the title bar pushes out of view.
    drawText("Then open \(name) from Applications. It lives in your notch.", font: roundedFont(12, .medium),
             color: fur.ns(0.46), centerX: bounds.midX, centerY: 326)
}

func render(name: String, scale: CGFloat) -> CGImage {
    let width = Int(size.width * scale), height = Int(size.height * scale)
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Flip to y-down so coordinates match Finder's icon positions.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    drawBackground(in: ctx, name: name)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// Writes a PNG whose DPI says how many pixels make a point, which tiffutil
/// needs to pair the 1x and 2x pages.
func writePNG(_ image: CGImage, dpi: CGFloat, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
    CGImageDestinationAddImage(dest, image, properties)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: render-background.swift <name> <output-dir>\n".utf8))
    exit(64)
}
let name = args[1]
let output = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
writePNG(render(name: name, scale: 1), dpi: 72, to: output.appendingPathComponent("background.png"))
writePNG(render(name: name, scale: 2), dpi: 144, to: output.appendingPathComponent("background@2x.png"))
print(output.path)
