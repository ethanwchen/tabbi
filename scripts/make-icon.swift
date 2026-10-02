#!/usr/bin/env swift
// Renders the NotchDeck app icon with CoreGraphics and builds Resources/AppIcon.icns.
//
//   usage: swift scripts/make-icon.swift [--preview <file.png>]
//
// The icon is drawn from code (no binary source art) so it stays reproducible and
// reviewable. Every size in the .iconset is rendered natively rather than downscaled
// from 1024 px, which keeps the small sizes crisp.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (mirrors Theme.Palette.accent(for:) in the app)

struct RGB {
    let r, g, b: CGFloat
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

let accents: [RGB] = [
    RGB(r: 0.12, g: 0.84, b: 0.38), // Now Playing - green
    RGB(r: 0.35, g: 0.78, b: 1.00), // System - blue
    RGB(r: 0.85, g: 0.47, b: 0.34), // Claude - orange
    RGB(r: 0.66, g: 0.55, b: 1.00), // Today - violet
]

// MARK: - Geometry

/// Apple's macOS icon grid: an 824 pt body centred on a 1024 pt canvas, leaving
/// room for the drop shadow.
let canvas: CGFloat = 1024
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)

/// A continuous-corner ("squircle") rounded square like the macOS icon shape:
/// straight edges that blend into superellipse corners, with no curvature jump
/// where a circular-arc rounded rect would have one.
func squircle(in rect: CGRect, corner c: CGFloat = 0.30, exponent n: CGFloat = 2.8) -> CGPath {
    let r = rect.width * c
    let path = CGMutablePath()
    // Corner centres, walked clockwise in y-down space starting at the top-right.
    let corners: [(CGPoint, CGFloat)] = [
        (CGPoint(x: rect.maxX - r, y: rect.minY + r), -.pi / 2),
        (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0),
        (CGPoint(x: rect.minX + r, y: rect.maxY - r), .pi / 2),
        (CGPoint(x: rect.minX + r, y: rect.minY + r), .pi),
    ]
    let steps = 90
    for (k, (center, start)) in corners.enumerated() {
        for i in 0...steps {
            let t = start + CGFloat(i) / CGFloat(steps) * .pi / 2
            let c = cos(t), s = sin(t)
            let pt = CGPoint(x: center.x + r * copysign(pow(abs(c), 2 / n), c),
                             y: center.y + r * copysign(pow(abs(s), 2 / n), s))
            k == 0 && i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
    }
    path.closeSubpath()
    return path
}

/// The notch silhouette in a y-down coordinate space: flared top shoulders that
/// melt into the top edge, straight sides, and generously rounded bottom corners -
/// the same shape the app draws in NotchShape.
func notchPath(width w: CGFloat, height h: CGFloat, topY: CGFloat, centerX: CGFloat,
               shoulder: CGFloat, bottomRadius: CGFloat) -> CGPath {
    let left = centerX - w / 2, right = centerX + w / 2
    let p = CGMutablePath()
    p.move(to: CGPoint(x: left - shoulder, y: topY))
    p.addQuadCurve(to: CGPoint(x: left, y: topY + shoulder), control: CGPoint(x: left, y: topY))
    p.addLine(to: CGPoint(x: left, y: topY + h - bottomRadius))
    p.addQuadCurve(to: CGPoint(x: left + bottomRadius, y: topY + h), control: CGPoint(x: left, y: topY + h))
    p.addLine(to: CGPoint(x: right - bottomRadius, y: topY + h))
    p.addQuadCurve(to: CGPoint(x: right, y: topY + h - bottomRadius), control: CGPoint(x: right, y: topY + h))
    p.addLine(to: CGPoint(x: right, y: topY + shoulder))
    p.addQuadCurve(to: CGPoint(x: right + shoulder, y: topY), control: CGPoint(x: right, y: topY))
    p.closeSubpath()
    return p
}

// MARK: - Drawing

func linearGradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

/// Draws the icon into a context whose user space is 1024×1024, y-down.
func drawIcon(in ctx: CGContext) {
    let body = squircle(in: bodyRect)

    // Drop shadow under the body, as on every Big Sur-style icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // Body: charcoal at the top fading into deep black, so the hardware-black
    // notch still reads against it.
    ctx.drawLinearGradient(
        linearGradient([
            (0, RGB(r: 0.19, g: 0.20, b: 0.23).cg()),
            (0.55, RGB(r: 0.08, g: 0.08, b: 0.10).cg()),
            (1, RGB(r: 0.02, g: 0.02, b: 0.03).cg()),
        ]),
        start: CGPoint(x: 0, y: bodyRect.minY), end: CGPoint(x: 0, y: bodyRect.maxY), options: [])

    // The notch, hanging from the top edge.
    let notchW: CGFloat = 456, notchH: CGFloat = 196
    let notch = notchPath(width: notchW, height: notchH, topY: bodyRect.minY, centerX: canvas / 2,
                          shoulder: 30, bottomRadius: 84)

    // A soft, cool light falling from the notch onto the body.
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    let spill = CGPoint(x: canvas / 2, y: bodyRect.minY + notchH)
    ctx.drawRadialGradient(linearGradient([(0, CGColor(gray: 1, alpha: 0.10)), (1, CGColor(gray: 1, alpha: 0))]),
                           startCenter: spill, startRadius: 0, endCenter: spill, endRadius: 420, options: [])
    ctx.restoreGState()

    ctx.addPath(notch)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()

    // A hairline rim along the notch edge sells the bezel depth.
    ctx.addPath(notch)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // Live-activity dots inside the notch, one per module.
    let dotY = bodyRect.minY + notchH - 80
    let dotR: CGFloat = 16
    for (i, accent) in accents.enumerated() {
        let center = CGPoint(x: canvas / 2 + (CGFloat(i) - 1.5) * 70, y: dotY)
        glow(ctx, accent, at: center, radius: dotR * 2.8, alpha: 0.55)
        ctx.addEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))
        ctx.setFillColor(accent.cg())
        ctx.fillPath()
    }

    // The deck: one glowing meter per module, like the panel the notch opens into.
    let barX: CGFloat = 252, barW: CGFloat = 520, barH: CGFloat = 30, barGap: CGFloat = 62
    let firstBarY: CGFloat = 500
    let fills: [CGFloat] = [0.78, 0.52, 0.90, 0.36]
    for (i, accent) in accents.enumerated() {
        let y = firstBarY + CGFloat(i) * barGap
        let track = CGRect(x: barX, y: y, width: barW, height: barH)
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.06))
        ctx.fillPath()

        let fill = CGRect(x: barX, y: y, width: barW * fills[i], height: barH)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26, color: accent.cg(0.7))
        ctx.addPath(CGPath(roundedRect: fill, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.setFillColor(accent.cg())
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Inner top highlight: a faint sheen on the upper body edge.
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08))
    ctx.setLineWidth(4)
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    ctx.strokePath()
    ctx.restoreGState()
}

/// A soft additive halo, used to make the accent marks feel lit from within.
func glow(_ ctx: CGContext, _ accent: RGB, at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    ctx.drawRadialGradient(linearGradient([(0, accent.cg(alpha)), (1, accent.cg(0))]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    ctx.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(pixels) / canvas
    // Flip to y-down so the drawing code reads top-to-bottom like the notch does.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(in: ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

// MARK: - Main

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments

if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    writePNG(render(pixels: 1024), to: URL(fileURLWithPath: args[i + 1]))
    print(args[i + 1])
    exit(0)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print(output.path)
