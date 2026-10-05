#!/usr/bin/env swift
// Renders the Tabbi app icon with CoreGraphics and builds Resources/AppIcon.icns.
//
//   usage: swift scripts/make-icon.swift                     build Resources/AppIcon.icns
//          swift scripts/make-icon.swift --concept <a|b|c>   pick an exploration concept
//          swift scripts/make-icon.swift --sheet <file.png>  render a 1024/128/32/16 review sheet
//          swift scripts/make-icon.swift --preview <file.png>
//
// The icon is drawn from code (no binary source art) so it stays reproducible and
// reviewable. Every size in the .iconset is rendered natively rather than downscaled
// from 1024 px, which keeps the small sizes crisp. See docs/brand/icon.md.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

struct RGB {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

enum Brand {
    static let ginger = RGB(0xFFA94D)      // tabby orange, lit side
    static let gingerDeep = RGB(0xEE7A2B)  // tabby orange, shade side
    static let stripe = RGB(0xB8501C)      // tabby stripes
    static let cream = RGB(0xFFF1DE)       // muzzle, inner ear, light background
    static let creamShade = RGB(0xF6DCC0)
    static let ink = RGB(0x1D2140)         // deep background
    static let inkDeep = RGB(0x0F1126)
    static let eye = RGB(0x231A2E)
    static let nose = RGB(0xF2827F)
}

// MARK: - Geometry

/// Apple's macOS icon grid: an 824 px body centred on a 1024 px canvas, leaving
/// room for the drop shadow. macOS 26 masks legacy icons to this squircle, so art
/// that fills it exactly is shown as is instead of being boxed in a grey tile.
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

/// A folder tab in y-down space: a flat base, sides that lean inward, and rounded
/// top corners, the shape Tabbi's ears and tab bar share.
func tabPath(baseCenter: CGPoint, baseWidth: CGFloat, topWidth: CGFloat, height: CGFloat,
             radius: CGFloat, angle: CGFloat = 0) -> CGPath {
    let bl = CGPoint(x: -baseWidth / 2, y: 0), br = CGPoint(x: baseWidth / 2, y: 0)
    let tl = CGPoint(x: -topWidth / 2, y: -height), tr = CGPoint(x: topWidth / 2, y: -height)
    let p = CGMutablePath()
    p.move(to: bl)
    p.addArc(tangent1End: tl, tangent2End: tr, radius: radius)
    p.addArc(tangent1End: tr, tangent2End: br, radius: radius)
    p.addLine(to: br)
    p.closeSubpath()
    var t = CGAffineTransform(translationX: baseCenter.x, y: baseCenter.y).rotated(by: angle)
    return p.copy(using: &t)!
}

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), transform: nil)
}

// MARK: - Drawing helpers

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: stops.map(\.1) as CFArray,
               locations: stops.map(\.0))!
}

/// Fills `path` with a vertical gradient between `top` and `bottom` (y-down).
func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, shadow: CGFloat = 0) {
    let box = path.boundingBoxOfPath
    if shadow > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: shadow * 0.4), blur: shadow, color: CGColor(gray: 0, alpha: 0.30))
        ctx.addPath(path)
        ctx.setFillColor(bottom)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, top), (1, bottom)]),
                           start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func stroke(_ ctx: CGContext, _ points: [CGPoint], width: CGFloat, color: CGColor, curved: Bool = false) {
    let p = CGMutablePath()
    p.move(to: points[0])
    if curved, points.count == 3 {
        p.addQuadCurve(to: points[2], control: points[1])
    } else {
        for pt in points.dropFirst() { p.addLine(to: pt) }
    }
    ctx.addPath(p)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func radialGlow(_ ctx: CGContext, at c: CGPoint, radius: CGFloat, color: CGColor) {
    ctx.drawRadialGradient(gradient([(0, color), (1, color.copy(alpha: 0)!)]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

/// A cat eye: a dark oval with a catch light, so it reads alive even at 32 px.
func eye(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    fill(ctx, ellipse(cx, cy, w, h), Brand.eye.cg())
    fill(ctx, ellipse(cx + w * 0.16, cy - h * 0.2, w * 0.36, w * 0.36), CGColor(gray: 1, alpha: 0.95))
}

/// The little pink nose and the "w" mouth under it.
func noseAndMouth(_ ctx: CGContext, at c: CGPoint, scale s: CGFloat) {
    let nose = CGMutablePath()
    nose.move(to: CGPoint(x: c.x - 26 * s, y: c.y - 12 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x + 26 * s, y: c.y - 12 * s), control: CGPoint(x: c.x, y: c.y - 22 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 14 * s), control: CGPoint(x: c.x + 22 * s, y: c.y + 4 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x - 26 * s, y: c.y - 12 * s), control: CGPoint(x: c.x - 22 * s, y: c.y + 4 * s))
    fill(ctx, nose, Brand.nose.cg())
    let mouthY = c.y + 14 * s
    stroke(ctx, [CGPoint(x: c.x, y: mouthY), CGPoint(x: c.x, y: mouthY + 22 * s), CGPoint(x: c.x - 26 * s, y: mouthY + 22 * s)],
           width: 9 * s, color: Brand.eye.cg(0.85), curved: true)
    stroke(ctx, [CGPoint(x: c.x, y: mouthY), CGPoint(x: c.x, y: mouthY + 22 * s), CGPoint(x: c.x + 26 * s, y: mouthY + 22 * s)],
           width: 9 * s, color: Brand.eye.cg(0.85), curved: true)
}

// MARK: - Concepts

/// A: "Tab-by". A tabby face rising from the bottom edge whose ears are folder
/// tabs, with the classic "M" on its forehead and one eye winking as a checkmark.
func drawConceptA(_ ctx: CGContext) {
    fill(ctx, CGPath(rect: bodyRect, transform: nil), top: RGB(0x2A2F5E).cg(), bottom: Brand.inkDeep.cg())
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    radialGlow(ctx, at: CGPoint(x: 512, y: 520), radius: 440, color: RGB(0xFFB25B).cg(0.22))
    ctx.restoreGState()

    // Folder-tab ears, leaning outward, tucked behind the head.
    for side in [-1.0, 1.0] as [CGFloat] {
        let base = CGPoint(x: 512 + side * 190, y: 520)
        let ear = tabPath(baseCenter: base, baseWidth: 250, topWidth: 150, height: 260, radius: 42, angle: side * 0.20)
        fill(ctx, ear, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 20)
        let inner = tabPath(baseCenter: CGPoint(x: base.x, y: base.y - 30), baseWidth: 150, topWidth: 84, height: 170,
                            radius: 26, angle: side * 0.20)
        fill(ctx, inner, top: Brand.cream.cg(), bottom: Brand.creamShade.cg())
    }

    // Head: a broad oval that runs off the bottom of the icon.
    let head = ellipse(512, 760, 700, 640)
    fill(ctx, head, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 30)

    // Tabby "M" and cheek stripes.
    let stripe = Brand.stripe.cg()
    stroke(ctx, [CGPoint(x: 446, y: 560), CGPoint(x: 472, y: 486), CGPoint(x: 512, y: 540),
                 CGPoint(x: 552, y: 486), CGPoint(x: 578, y: 560)], width: 26, color: stripe)
    for side in [-1.0, 1.0] as [CGFloat] {
        for (i, y) in [650.0, 700.0].enumerated() as EnumeratedSequence<[CGFloat]> {
            let inner = 512 + side * (276 - CGFloat(i) * 6)
            stroke(ctx, [CGPoint(x: 512 + side * 340, y: y - 6), CGPoint(x: inner, y: y + 4)], width: 22, color: stripe)
        }
    }

    // Muzzle.
    fill(ctx, ellipse(462, 772, 150, 116), Brand.cream.cg())
    fill(ctx, ellipse(562, 772, 150, 116), Brand.cream.cg())

    // Eyes: one open, one a checkmark wink (the task is done).
    eye(ctx, 404, 646, 74, 92)
    stroke(ctx, [CGPoint(x: 584, y: 646), CGPoint(x: 612, y: 676), CGPoint(x: 666, y: 612)], width: 26, color: Brand.eye.cg())

    noseAndMouth(ctx, at: CGPoint(x: 512, y: 728), scale: 1.2)
}

/// B: "Peek". A tabby peeking over a strip of folder tabs, paws on the edge,
/// with tab-shaped stripes on its forehead.
func drawConceptB(_ ctx: CGContext) {
    fill(ctx, CGPath(rect: bodyRect, transform: nil), top: RGB(0xFFF6EA).cg(), bottom: RGB(0xFBDDBE).cg())

    // Head behind the ledge.
    for side in [-1.0, 1.0] as [CGFloat] {
        let ear = tabPath(baseCenter: CGPoint(x: 512 + side * 170, y: 400), baseWidth: 200, topWidth: 60, height: 190,
                          radius: 24, angle: side * 0.25)
        fill(ctx, ear, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg())
        let inner = tabPath(baseCenter: CGPoint(x: 512 + side * 170, y: 390), baseWidth: 110, topWidth: 26, height: 120,
                            radius: 12, angle: side * 0.25)
        fill(ctx, inner, Brand.nose.cg(0.55))
    }
    let head = ellipse(512, 560, 600, 480)
    fill(ctx, head, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 18)

    // Forehead stripes drawn as three little tabs.
    for (i, dx) in [-70.0, 0.0, 70.0].enumerated() as EnumeratedSequence<[CGFloat]> {
        let h: CGFloat = i == 1 ? 96 : 70
        fill(ctx, tabPath(baseCenter: CGPoint(x: 512 + dx, y: 430), baseWidth: 50, topWidth: 30, height: h, radius: 10,
                          angle: .pi), Brand.stripe.cg())
    }

    eye(ctx, 418, 540, 70, 84)
    eye(ctx, 606, 540, 70, 84)
    fill(ctx, ellipse(470, 625, 120, 86), Brand.cream.cg())
    fill(ctx, ellipse(554, 625, 120, 86), Brand.cream.cg())
    noseAndMouth(ctx, at: CGPoint(x: 512, y: 596), scale: 1.0)

    // The tab strip: three folder tabs on a dark bar, the middle one active.
    let barTop: CGFloat = 690
    fill(ctx, CGPath(rect: CGRect(x: 100, y: barTop, width: 824, height: 300), transform: nil),
         top: RGB(0x2A2F5E).cg(), bottom: Brand.inkDeep.cg())
    for (i, x) in [252.0, 512.0, 772.0].enumerated() as EnumeratedSequence<[CGFloat]> {
        let active = i == 1
        let tab = tabPath(baseCenter: CGPoint(x: x, y: barTop + 1), baseWidth: 250, topWidth: 200, height: 70, radius: 24)
        fill(ctx, tab, active ? RGB(0x2A2F5E).cg() : RGB(0x1A1E3E).cg())
    }

    // Paws over the edge.
    for side in [-1.0, 1.0] as [CGFloat] {
        let cx = 512 + side * 150
        fill(ctx, ellipse(cx, barTop - 14, 130, 84), top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 10)
        for dx in [-24.0, 24.0] as [CGFloat] {
            stroke(ctx, [CGPoint(x: cx + dx, y: barTop + 2), CGPoint(x: cx + dx, y: barTop + 20)], width: 8,
                   color: Brand.stripe.cg())
        }
    }
}

/// C: "Pomodoro". A tabby curled into a timer ring, stripes as the ticks and
/// the tail as the clock hand.
func drawConceptC(_ ctx: CGContext) {
    fill(ctx, CGPath(rect: bodyRect, transform: nil), top: RGB(0xFFF6EA).cg(), bottom: RGB(0xF9D9B6).cg())

    let center = CGPoint(x: 512, y: 548)
    let radius: CGFloat = 258, thickness: CGFloat = 132

    // Body ring with a soft shadow.
    let ring = CGMutablePath()
    ring.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    let ringShape = ring.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 10)
    fill(ctx, ringShape, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 26)

    // Stripes as timer ticks.
    ctx.saveGState()
    ctx.addPath(ringShape)
    ctx.clip()
    for i in 0..<12 where i != 0 {
        let a = CGFloat(i) / 12 * .pi * 2 - .pi / 2
        let inner = CGPoint(x: center.x + cos(a) * (radius - 80), y: center.y + sin(a) * (radius - 80))
        let outer = CGPoint(x: center.x + cos(a) * (radius + 30), y: center.y + sin(a) * (radius + 30))
        stroke(ctx, [inner, outer], width: 26, color: Brand.stripe.cg())
    }
    ctx.restoreGState()

    // Tail as the clock hand, sweeping from the centre.
    let tip = CGPoint(x: center.x + 130, y: center.y - 110)
    stroke(ctx, [center, CGPoint(x: center.x + 40, y: center.y - 10), tip], width: 44, color: Brand.gingerDeep.cg(), curved: true)
    stroke(ctx, [CGPoint(x: tip.x - 18, y: tip.y + 16), tip], width: 44, color: Brand.stripe.cg())
    fill(ctx, ellipse(center.x, center.y, 64, 64), Brand.gingerDeep.cg())

    // Head on top of the ring, at twelve o'clock.
    let hc = CGPoint(x: center.x, y: center.y - radius + 6)
    for side in [-1.0, 1.0] as [CGFloat] {
        let ear = tabPath(baseCenter: CGPoint(x: hc.x + side * 92, y: hc.y - 30), baseWidth: 120, topWidth: 40,
                          height: 120, radius: 16, angle: side * 0.3)
        fill(ctx, ear, top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg())
    }
    fill(ctx, ellipse(hc.x, hc.y, 270, 220), top: Brand.ginger.cg(), bottom: Brand.gingerDeep.cg(), shadow: 16)
    stroke(ctx, [CGPoint(x: hc.x - 44, y: hc.y - 50), CGPoint(x: hc.x - 26, y: hc.y - 88), CGPoint(x: hc.x, y: hc.y - 60),
                 CGPoint(x: hc.x + 26, y: hc.y - 88), CGPoint(x: hc.x + 44, y: hc.y - 50)], width: 14, color: Brand.stripe.cg())
    // Content, eyes closed as it naps through the focus block.
    for side in [-1.0, 1.0] as [CGFloat] {
        stroke(ctx, [CGPoint(x: hc.x + side * 50 - 22, y: hc.y), CGPoint(x: hc.x + side * 50, y: hc.y + 18),
                     CGPoint(x: hc.x + side * 50 + 22, y: hc.y)], width: 12, color: Brand.eye.cg(), curved: true)
    }
    fill(ctx, ellipse(hc.x - 26, hc.y + 54, 64, 46), Brand.cream.cg())
    fill(ctx, ellipse(hc.x + 26, hc.y + 54, 64, 46), Brand.cream.cg())
    noseAndMouth(ctx, at: CGPoint(x: hc.x, y: hc.y + 38), scale: 0.55)
}

let concepts: [String: (CGContext) -> Void] = ["a": drawConceptA, "b": drawConceptB, "c": drawConceptC]

// MARK: - Icon

/// Draws the icon into a context whose user space is 1024×1024, y-down.
func drawIcon(in ctx: CGContext, concept: (CGContext) -> Void) {
    let body = squircle(in: bodyRect)

    // Drop shadow under the body, as on every macOS icon.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    concept(ctx)
    // A faint rim of light along the edge, like the glass edge on macOS 26 icons.
    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func render(pixels: Int, concept: @escaping (CGContext) -> Void) -> CGImage {
    let ctx = makeContext(pixels, pixels)
    let scale = CGFloat(pixels) / canvas
    // Flip to y-down so the drawing code reads top-to-bottom.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(in: ctx, concept: concept)
    return ctx.makeImage()!
}

/// A review sheet: the icon at 1024 (shown at half size), 128, 32 and 16 px on a
/// light and a dark desktop, plus the 32 and 16 px renders blown up 4x with no
/// smoothing so each pixel can be judged.
func reviewSheet(concept: @escaping (CGContext) -> Void) -> CGImage {
    let w = 1280, rowH = 600
    let ctx = makeContext(w, rowH * 2)
    let big = render(pixels: 1024, concept: concept)
    let small = [128, 32, 16].map { ($0, render(pixels: $0, concept: concept)) }
    for (row, gray) in [(1, 0.93), (0, 0.13)] as [(Int, CGFloat)] {
        let y0 = CGFloat(row * rowH)
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(w), height: CGFloat(rowH)))
        ctx.interpolationQuality = .high
        ctx.draw(big, in: CGRect(x: 40, y: y0 + 44, width: 512, height: 512))
        var x: CGFloat = 600
        for (px, image) in small {
            ctx.draw(image, in: CGRect(x: x, y: y0 + 300 - CGFloat(px) / 2, width: CGFloat(px), height: CGFloat(px)))
            x += CGFloat(px) + 40
        }
        ctx.interpolationQuality = .none
        for (px, image) in small where px <= 32 {
            ctx.draw(image, in: CGRect(x: x, y: y0 + 300 - CGFloat(px) * 2, width: CGFloat(px) * 4, height: CGFloat(px) * 4))
            x += CGFloat(px) * 4 + 30
        }
    }
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
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let conceptKey = option("--concept") ?? "a"
guard let concept = concepts[conceptKey] else { fatalError("unknown concept \(conceptKey)") }

if let path = option("--sheet") {
    writePNG(reviewSheet(concept: concept), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}
if let path = option("--preview") {
    writePNG(render(pixels: 1024, concept: concept), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    writePNG(render(pixels: points, concept: concept), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(render(pixels: points * 2, concept: concept), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
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
