#!/usr/bin/env swift
// Renders the Tabbi app icon with CoreGraphics and builds Resources/AppIcon.icns.
//
//   usage: swift scripts/make-icon.swift                     build Resources/AppIcon.icns
//          swift scripts/make-icon.swift --sheet <file.png>  render a 1024/128/32/16 review sheet
//                [--reference <photo> [--crop x,y,size]]      beside a reference photo
//          swift scripts/make-icon.swift --dock <file.png>   compare it with Apple's icons in a Dock row
//          swift scripts/make-icon.swift --variants <file.png>  every appearance and the glyph
//          swift scripts/make-icon.swift --preview <file.png>
//          swift scripts/make-icon.swift --glyph                  only the glyph in docs/brand/assets
//
// Add --ground <navy|blush> to a review mode to try a candidate background. The
// default build always uses the shipped palette.
// The default run also writes docs/brand/assets: the icon at 1024 px in its default,
// light, dark and tinted appearances, and the colour glyph as PDF and PNG.
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

/// The colours of one icon appearance. macOS 26 shows an icon in Default, Dark and
/// Tinted looks; `.icns` can only carry one, so the others are exported as PNGs.
/// The cat colours come from the maintainer's British Shorthair: a shaded silver coat,
/// pale silver-beige on the face, taupe on the crown and back, white muzzle and chin.
/// They match the pet sprite's British Shorthair (`PetBreed`), lit: its flat base fur
/// sits between `fur` and `furShade` here, so the icon and the notch pet are one cat.
struct Palette {
    var ground: RGB                     // background, top of the squircle
    var groundDeep: RGB                 // background, bottom
    var topLight: RGB                   // glow at the top of the background
    var topLightAlpha: CGFloat
    var fur = RGB(0xE6DFD5)             // pale silver-beige face, lit
    var furShade = RGB(0xCAC1B5)        // cheeks and jowls, shade side
    var back = RGB(0xADA398)            // taupe crown, the darker colour of the back
    var ticking = RGB(0x756D66)         // faint ticked lines on the forehead
    var white = RGB(0xF8F5EF)           // muzzle, chin and chest
    var innerEar = RGB(0xE6B3AC)        // the tab's label: the pink inside of the ear
    var sheen = RGB(0xFFFFFF)           // top light on the crown of the head
    var iris = RGB(0x5FA3EA)            // clear blue eye, lit
    var irisDeep = RGB(0x3F86D6)        // the top of the iris, the pet sprite's eye blue
    var eye = RGB(0x2B2622)             // pupil, eye rim and the checkmark wink
    var nose = RGB(0xD29A8A)            // pink-tan nose
    var monochrome = false              // luminance only (Tinted); applies to the cover art too

    /// Candidate ground: deep navy, so the pale cat glows and the icon echoes the black notch.
    static let navy = Palette(ground: RGB(0x24335F), groundDeep: RGB(0x0D1430),
                              topLight: RGB(0x4660A8), topLightAlpha: 0.55)
    /// Candidate ground: a warm blush like the pink silk pillow in the reference photo.
    static let blush = Palette(ground: RGB(0xF7D5C8), groundDeep: RGB(0xE7A898),
                               topLight: RGB(0xFFFFFF), topLightAlpha: 0.7)
    /// The shipped icon.
    static let standard = navy
    /// For light surfaces such as a website hero.
    static let light = blush
    /// macOS 26 Dark: notch black ground, the cat unchanged so it stays recognizable.
    static let dark = Palette(ground: RGB(0x2A2A2E), groundDeep: RGB(0x0B0B0D),
                              topLight: RGB(0x56565E), topLightAlpha: 0.45)
    /// macOS 26 Tinted: luminance only on black, so the system tint colours the cat.
    static let tinted = Palette(ground: RGB(0x262626), groundDeep: RGB(0x0A0A0A),
                                topLight: RGB(0x4A4A4A), topLightAlpha: 0.45,
                                fur: RGB(0xE6E6E6), furShade: RGB(0xBDBDBD), back: RGB(0x9A9A9A),
                                ticking: RGB(0x6E6E6E), white: RGB(0xFFFFFF), innerEar: RGB(0xD2D2D2),
                                iris: RGB(0xA6A6A6), irisDeep: RGB(0x8C8C8C), eye: RGB(0x161616), nose: RGB(0x8C8C8C),
                                monochrome: true)
}

let candidatePalettes: [String: Palette] = ["navy": .navy, "blush": .blush]

/// The appearance being drawn. Variant renders swap it before calling render().
var brand = Palette.standard

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

/// Pixels per canvas unit for the render in progress. CoreGraphics applies shadow
/// offsets and blurs in device space, ignoring the CTM, so every shadow is scaled
/// by this to look the same at 16 px as at 1024 px.
var deviceScale: CGFloat = 1

/// Pixel size of the render in progress. Renders of 32 px or less (the 16 pt icon
/// at 1x and 2x, and 32 pt at 1x) use an optical small-size drawing, the way a type
/// designer cuts a caption size: fewer, bigger features that survive a 13 px body.
var renderPixels = 1024
var isSmallRender: Bool { renderPixels <= 32 }

func setShadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, alpha: CGFloat) {
    // Device space is y-up while the drawing is y-down, so a downward shadow has a negative offset.
    ctx.setShadow(offset: CGSize(width: 0, height: -y * deviceScale), blur: blur * deviceScale,
                  color: CGColor(gray: 0, alpha: alpha))
}

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
        setShadow(ctx, y: shadow * 0.4, blur: shadow, alpha: 0.30)
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

/// Fills `path` with a vertical gradient through `stops` (y-down, 0 at the top of the path).
func fill(_ ctx: CGContext, _ path: CGPath, stops: [(CGFloat, CGColor)]) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - The cat

/// The head: a broad skull with the full, chubby jowls of a British Shorthair, rising
/// from the bottom edge of the icon.
func headPath() -> CGPath {
    var head: CGPath = ellipse(512, 770, 700, 640)
    for side in [-1.0, 1.0] as [CGFloat] {
        head = head.union(ellipse(512 + side * 200, 830, 370, 330))
    }
    return head
}

/// Folder-tab ears adapted to the breed: small, low and rounded, set wide apart on
/// the corners of the round head. `inset` shrinks the tab for the pink label inside.
/// At 32 px and below the ears are cut taller and more upright, so each one still
/// rises above the crown as a distinct two-pixel bump instead of merging into the head.
func earPath(side: CGFloat, inset: CGFloat = 0, small: Bool = false) -> CGPath {
    let height: CGFloat = small ? 220 : 160
    return tabPath(baseCenter: CGPoint(x: 512 + side * (small ? 236 : 250 - inset * 0.2), y: 572 - inset * 0.6),
                   baseWidth: 236 - inset * 2.2, topWidth: 156 - inset * 1.6, height: height - inset * 1.5,
                   radius: 48 - inset * 0.5, angle: side * (small ? 0.30 : 0.42))
}

/// The open eye: a round, wide-open blue eye with a big dark pupil and a white catch
/// light, friendly rather than grumpy. The same clear blue as the pet sprite's eye.
/// At 32 px and below it is a blue disc around a dark pupil, which still reads as
/// an open eye when it covers only two or three pixels.
func roundEye(_ ctx: CGContext, center c: CGPoint, width w: CGFloat, height h: CGFloat, small: Bool) {
    let eyeShape = ellipse(c.x, c.y, w, h)
    if small {
        fill(ctx, eyeShape, brand.iris.cg())
        fill(ctx, ellipse(c.x + w * 0.04, c.y + h * 0.04, w * 0.56, h * 0.62), brand.eye.cg())
        return
    }
    // Lighter at the bottom, the way light pools in a real iris.
    fill(ctx, eyeShape, top: brand.irisDeep.cg(), bottom: brand.iris.cg())
    ctx.saveGState()
    ctx.addPath(eyeShape)
    ctx.clip()
    fill(ctx, ellipse(c.x + w * 0.02, c.y + h * 0.05, w * 0.56, h * 0.6), brand.eye.cg())
    ctx.restoreGState()
    ctx.addPath(eyeShape)
    ctx.setStrokeColor(brand.eye.cg())
    ctx.setLineWidth(8)
    ctx.strokePath()
    // A big catch light up and to the left, and a small one low on the right: sparkle.
    fill(ctx, ellipse(c.x - w * 0.14, c.y - h * 0.14, w * 0.34, w * 0.34), CGColor(gray: 1, alpha: 0.95))
    fill(ctx, ellipse(c.x + w * 0.18, c.y + h * 0.24, w * 0.13, w * 0.13), CGColor(gray: 1, alpha: 0.85))
}

/// The pink-tan nose: a soft rounded triangle.
func nose(_ ctx: CGContext, at c: CGPoint, scale s: CGFloat) {
    let nose = CGMutablePath()
    nose.move(to: CGPoint(x: c.x - 30 * s, y: c.y - 14 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x + 30 * s, y: c.y - 14 * s), control: CGPoint(x: c.x, y: c.y - 26 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 16 * s), control: CGPoint(x: c.x + 24 * s, y: c.y + 4 * s))
    nose.addQuadCurve(to: CGPoint(x: c.x - 30 * s, y: c.y - 14 * s), control: CGPoint(x: c.x - 24 * s, y: c.y + 4 * s))
    fill(ctx, nose, brand.nose.cg())
}

/// "Tab-by", British Shorthair cut: a round silver-beige face whose small ears are
/// folder tabs, with one round blue eye open and the other winking as a checkmark.
func drawCat(_ ctx: CGContext) {
    fill(ctx, CGPath(rect: bodyRect, transform: nil), top: brand.ground.cg(), bottom: brand.groundDeep.cg())
    // A top light in the ground's own hue, like a glass layer lit from above.
    radialGlow(ctx, at: CGPoint(x: 512, y: 130), radius: 520, color: brand.topLight.cg(brand.topLightAlpha))
    // The cat is laid out on the tabby's grid and lifted so the face sits at the optical centre.
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.translateBy(x: 0, y: -56)

    let small = isSmallRender
    // Ears: taupe tabs with a pink label, tucked behind the head. At small sizes they
    // are a solid darker taupe, the one shape that has to survive as a bump.
    for side in [-1.0, 1.0] as [CGFloat] {
        if small {
            fill(ctx, earPath(side: side, small: true), brand.ticking.cg())
            fill(ctx, earPath(side: side, inset: 56, small: true), brand.innerEar.cg())
        } else {
            fill(ctx, earPath(side: side), top: brand.back.cg(), bottom: brand.furShade.cg(), shadow: 20)
            fill(ctx, earPath(side: side, inset: 40), top: brand.innerEar.cg(), bottom: brand.fur.cg())
        }
    }

    let head = headPath()
    // Taupe on the crown, the silver-beige face, slightly deeper on the lower jowls.
    fill(ctx, head, top: brand.back.cg(), bottom: brand.furShade.cg(), shadow: 30)
    fill(ctx, head, stops: [(0, brand.back.cg()), (0.16, brand.fur.cg()), (0.75, brand.fur.cg()), (1, brand.furShade.cg())])

    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip()
    // The taupe blaze of the reference cat: wide on the crown, narrowing between the
    // eyes and fading out on the bridge of the nose.
    let blaze = CGMutablePath()
    blaze.move(to: CGPoint(x: 512 - 190, y: 420))
    blaze.addCurve(to: CGPoint(x: 512, y: small ? 700 : 716), control1: CGPoint(x: 512 - 150, y: 560),
                   control2: CGPoint(x: 512 - 40, y: 600))
    blaze.addCurve(to: CGPoint(x: 512 + 190, y: 420), control1: CGPoint(x: 512 + 40, y: 600),
                   control2: CGPoint(x: 512 + 150, y: 560))
    blaze.closeSubpath()
    fill(ctx, blaze, stops: [(0, brand.back.cg(0.95)), (0.45, brand.back.cg(0.8)), (1, brand.back.cg(0))])
    if !small {
        // Faint ticking: soft, tapering lines that fade into the streak.
        for (dx, top, bottom) in [(-40.0, 488.0, 560.0), (0.0, 470.0, 590.0), (40.0, 488.0, 560.0)] as [(CGFloat, CGFloat, CGFloat)] {
            let line = CGMutablePath()
            line.move(to: CGPoint(x: 512 + dx, y: top))
            line.addLine(to: CGPoint(x: 512 + dx * 0.85, y: bottom))
            let shape = line.copy(strokingWithWidth: 14, lineCap: .round, lineJoin: .round, miterLimit: 10)
            fill(ctx, shape, stops: [(0, brand.ticking.cg(0.7)), (1, brand.ticking.cg(0))])
        }
    }
    // A soft sheen on the cheeks, lit from the same top light as the rim.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 600)
    ctx.scaleBy(x: 1.9, y: 1)
    radialGlow(ctx, at: .zero, radius: 180, color: brand.sheen.cg(0.35))
    ctx.restoreGState()
    // White chin and chest running off the bottom.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 930)
    ctx.scaleBy(x: 1.5, y: 1)
    radialGlow(ctx, at: .zero, radius: 170, color: brand.white.cg(0.95))
    ctx.restoreGState()
    ctx.restoreGState()

    if small {
        drawFaceSmall(ctx)
        return
    }

    // Puffy white muzzle pads and chin.
    fill(ctx, ellipse(512, 852, 150, 96), brand.white.cg())
    fill(ctx, ellipse(456, 800, 140, 110), brand.white.cg())
    fill(ctx, ellipse(568, 800, 140, 110), brand.white.cg())

    // One eye wide open and blue, the other a checkmark wink: done.
    roundEye(ctx, center: CGPoint(x: 400, y: 654), width: 136, height: 146, small: false)
    stroke(ctx, [CGPoint(x: 572, y: 654), CGPoint(x: 606, y: 690), CGPoint(x: 676, y: 616)], width: 36,
           color: brand.eye.cg())

    // A soft pink blush under each eye.
    for x in [392.0, 632.0] as [CGFloat] {
        ctx.saveGState()
        ctx.translateBy(x: x, y: 752)
        ctx.scaleBy(x: 1.5, y: 1)
        radialGlow(ctx, at: .zero, radius: 40, color: brand.innerEar.cg(0.6))
        ctx.restoreGState()
    }
    nose(ctx, at: CGPoint(x: 512, y: 744), scale: 1.15)
    // A short line under the nose that opens into a gentle "w": a content little smile.
    stroke(ctx, [CGPoint(x: 512, y: 762), CGPoint(x: 512, y: 784)], width: 8, color: brand.eye.cg(0.55))
    for side in [-1.0, 1.0] as [CGFloat] {
        stroke(ctx, [CGPoint(x: 512, y: 784), CGPoint(x: 512 + side * 20, y: 806), CGPoint(x: 512 + side * 42, y: 782)],
               width: 8, color: brand.eye.cg(0.55), curved: true)
    }
}

/// The face for 32 px and smaller. At 16 px one canvas pixel is 64 units, so anything
/// thinner than about 50 units turns to grey noise: the ticking, the mouth and the
/// catch light go, while the eye, the check and the nose grow until each covers at
/// least a pixel and a half.
func drawFaceSmall(_ ctx: CGContext) {
    fill(ctx, ellipse(512, 830, 320, 170), brand.white.cg())
    roundEye(ctx, center: CGPoint(x: 398, y: 652), width: 170, height: 178, small: true)
    stroke(ctx, [CGPoint(x: 560, y: 652), CGPoint(x: 606, y: 702), CGPoint(x: 690, y: 604)], width: 70,
           color: brand.eye.cg())
    fill(ctx, ellipse(512, 752, 84, 56), brand.nose.cg())
}

// MARK: - Cover art

/// The shipped icon art: the British Shorthair cover generated with the ip-as-logo
/// recipe (see docs/brand/icon.md). When it exists it fills the squircle in place of
/// the code-drawn cat; the squircle mask, drop shadow and glass rim stay the same.
let coverArt: CGImage? = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/brand/source/tabbi-cover.png")
    return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}()

/// Draws the cover art over the icon body. The context is y-down, so the image is
/// flipped back locally. Tinted keeps luminance only, like the drawn cat.
func drawCoverArt(_ ctx: CGContext, _ art: CGImage) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: bodyRect.maxY + bodyRect.minY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(art, in: bodyRect)
    if brand.monochrome {
        ctx.setBlendMode(.saturation)
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(bodyRect)
    }
    ctx.restoreGState()
}

// MARK: - Icon

/// Draws the icon into a context whose user space is 1024×1024, y-down.
func drawIcon(in ctx: CGContext) {
    let body = squircle(in: bodyRect)

    // Drop shadow under the body, as on every macOS icon.
    ctx.saveGState()
    setShadow(ctx, y: 12, blur: 28, alpha: 0.35)
    ctx.addPath(body)
    ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    if let art = coverArt {
        drawCoverArt(ctx, art)
    } else {
        drawCat(ctx)
    }
    // A faint rim of light along the edge, like the glass edge on macOS 26 icons. At
    // small sizes it would only lighten the outer pixel ring, so it is left out.
    if isSmallRender {
        ctx.restoreGState()
        return
    }
    // The rim is brightest at the top, where the light falls, and fades toward the bottom.
    ctx.addPath(body)
    ctx.setLineWidth(10)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, CGColor(gray: 1, alpha: 0.55)), (0.45, CGColor(gray: 1, alpha: 0.12)),
                                     (1, CGColor(gray: 1, alpha: 0.22))]),
                           start: CGPoint(x: 0, y: bodyRect.minY), end: CGPoint(x: 0, y: bodyRect.maxY), options: [])
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

func render(pixels: Int) -> CGImage {
    let ctx = makeContext(pixels, pixels)
    let scale = CGFloat(pixels) / canvas
    deviceScale = scale
    renderPixels = pixels
    // Flip to y-down so the drawing code reads top-to-bottom.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawIcon(in: ctx)
    return ctx.makeImage()!
}

/// A review sheet: the icon at 1024 (shown at half size), 128, 32 and 16 px on a
/// light and a dark desktop, plus the 32 and 16 px renders blown up 4x with no
/// smoothing so each pixel can be judged. With `--reference <photo>` the photo's
/// square centre crop (or `--crop x,y,size` in its pixels) is shown on the right.
func reviewSheet(reference: CGImage?) -> CGImage {
    let w = reference == nil ? 1280 : 1840, rowH = 600
    let ctx = makeContext(w, rowH * 2)
    let big = render(pixels: 1024)
    let small = [128, 32, 16].map { ($0, render(pixels: $0)) }
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
    if let reference {
        let side = min(reference.width, reference.height)
        let crop = option("--crop").map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
        let rect = crop.count == 3
            ? CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[2])
            : CGRect(x: (reference.width - side) / 2, y: (reference.height - side) / 2, width: side, height: side)
        ctx.interpolationQuality = .high
        ctx.draw(reference.cropping(to: rect)!, in: CGRect(x: 1290, y: 340, width: 520, height: 520))
    }
    return ctx.makeImage()!
}

/// A Dock check: Tabbi between Apple's own icons (and a few well known Mac apps, when
/// installed) at 128 and 32 px on a light and a dark desktop. Other icons come from
/// NSWorkspace, so on macOS 26 they show with the system's own Liquid Glass rendering.
func dockSheet() -> CGImage {
    let neighbours = ["/System/Applications/Calendar.app", "/System/Applications/Reminders.app",
                      "/System/Applications/Notes.app", "/System/Applications/Clock.app", "TABBI",
                      "/System/Applications/Messages.app", "/System/Applications/Music.app",
                      "/Applications/Things3.app", "/Applications/Linear.app", "/Applications/Anki.app"]
        .filter { $0 == "TABBI" || FileManager.default.fileExists(atPath: $0) }
    let gap: CGFloat = 24, rowH: CGFloat = 260
    let w = Int(CGFloat(neighbours.count) * (128 + gap) + gap)
    let ctx = makeContext(w, Int(rowH) * 2)
    let ours = [128: render(pixels: 128), 32: render(pixels: 32)]
    for (row, gray) in [(1, 0.93), (0, 0.13)] as [(Int, CGFloat)] {
        let y0 = CGFloat(row) * rowH
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(w), height: rowH))
        for (i, path) in neighbours.enumerated() {
            let x = gap + CGFloat(i) * (128 + gap)
            for (px, y) in [(128, y0 + 110), (32, y0 + 40)] as [(Int, CGFloat)] {
                let size = CGFloat(px)
                let rect = CGRect(x: x + (128 - size) / 2, y: y, width: size, height: size)
                if path == "TABBI" {
                    ctx.draw(ours[px]!, in: rect)
                } else {
                    var proposed = CGRect(x: 0, y: 0, width: size, height: size)
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    if let image = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
                        ctx.draw(image, in: rect)
                    }
                }
            }
        }
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

// MARK: - Glyph and variants

/// The colours of the glyph, sampled from the cover art (`tabbi-cover.prompt.txt`):
/// cream fur, taupe stripes and ears, round blue eyes and a pink nose, plus a deeper
/// taupe outline so the pale face holds its shape on white as well as on black.
enum GlyphColor {
    static let fur = RGB(0xE4DED6)
    static let taupe = RGB(0x8E8379)
    static let outline = RGB(0x5E554E)
    static let eye = RGB(0x3D8BFF)
    static let nose = RGB(0xF09EA6)
}

/// The glyph's ears: blunt rounded triangles set wide apart on the corners of the head
/// and leaning out, like the cover's.
func glyphEar(side: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let outer = CGPoint(x: 512 + side * 420, y: 500), tip = CGPoint(x: 512 + side * 360, y: 92)
    let inner = CGPoint(x: 512 + side * 90, y: 250)
    p.move(to: CGPoint(x: (outer.x + inner.x) / 2, y: (outer.y + inner.y) / 2))
    p.addArc(tangent1End: outer, tangent2End: tip, radius: 60)
    p.addArc(tangent1End: tip, tangent2End: inner, radius: 70)
    p.addArc(tangent1End: inner, tangent2End: outer, radius: 60)
    p.closeSubpath()
    return p
}

/// The glyph's head: one big, very round face, a little wider than tall.
func glyphHead() -> CGPath { ellipse(512, 580, 880, 760) }

/// The outline of the whole mark: the head and both ears as one shape.
func glyphSilhouette() -> CGPath {
    glyphHead().union(glyphEar(side: -1)).union(glyphEar(side: 1))
}

/// A round-capped stripe from `a` to `b`, as a filled shape.
func glyphStripe(_ a: CGPoint, _ b: CGPoint, width: CGFloat) -> CGPath {
    let line = CGMutablePath()
    line.move(to: a)
    line.addLine(to: b)
    return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// The Tabbi mark for small UI (menus, onboarding, the website favicon): the cover's
/// British Shorthair reduced to a face that reads at 16 to 32 pt. A round cream head
/// with taupe ears, three taupe stripes on the forehead and two on each cheek, two
/// round blue eyes and a pink nose. Every feature is at least about 1.5 px at 16 px
/// (64 units per pixel), so the eyes and nose stay distinct dots and the stripes stay
/// visible bands; anything finer, like the cover's whiskerless mouth, is left out.
/// Drawn in a 1024 unit, y-down space.
func drawGlyph(_ ctx: CGContext) {
    let head = glyphHead()
    let silhouette = glyphSilhouette()
    for side in [-1.0, 1.0] as [CGFloat] {
        fill(ctx, glyphEar(side: side), GlyphColor.taupe.cg())
    }
    fill(ctx, head, GlyphColor.fur.cg())

    ctx.saveGState()
    ctx.addPath(head)
    ctx.clip()
    // Three forehead stripes, fanning out a little, running in from the crown.
    for (dx, lean) in [(-128.0, -26.0), (0.0, 0.0), (128.0, 26.0)] as [(CGFloat, CGFloat)] {
        fill(ctx, glyphStripe(CGPoint(x: 512 + dx + lean, y: 160), CGPoint(x: 512 + dx, y: 372), width: 78),
             GlyphColor.taupe.cg())
    }
    // Two short stripes on each cheek, running in from the side of the face.
    for side in [-1.0, 1.0] as [CGFloat] {
        for (y, length) in [(590.0, 100.0), (680.0, 76.0)] as [(CGFloat, CGFloat)] {
            fill(ctx, glyphStripe(CGPoint(x: 512 + side * 470, y: y - 14), CGPoint(x: 512 + side * (440 - length), y: y),
                                  width: 60),
                 GlyphColor.taupe.cg())
        }
    }
    ctx.restoreGState()

    // Round blue eyes set wide, and a small pink nose between and below them.
    for side in [-1.0, 1.0] as [CGFloat] {
        fill(ctx, ellipse(512 + side * 168, 600, 124, 124), GlyphColor.eye.cg())
    }
    let nose = CGMutablePath()
    let left = CGPoint(x: 438, y: 664), right = CGPoint(x: 586, y: 664), bottom = CGPoint(x: 512, y: 740)
    nose.move(to: CGPoint(x: 512, y: 664))
    nose.addArc(tangent1End: right, tangent2End: bottom, radius: 26)
    nose.addArc(tangent1End: bottom, tangent2End: left, radius: 30)
    nose.addArc(tangent1End: left, tangent2End: right, radius: 26)
    nose.closeSubpath()
    fill(ctx, nose, GlyphColor.nose.cg())

    ctx.addPath(silhouette)
    ctx.setStrokeColor(GlyphColor.outline.cg())
    ctx.setLineWidth(36)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

/// The glyph on a transparent square of `pixels`.
func renderGlyph(pixels: Int) -> CGImage {
    let ctx = makeContext(pixels, pixels)
    let scale = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    drawGlyph(ctx)
    return ctx.makeImage()!
}

/// Quartz stamps every PDF with its creation time and a random file ID, so the
/// file is only replaced when the drawing itself changed. That keeps a rerun of
/// an unchanged design from showing up as a diff, like the .icns.
func writeGlyphPDF(to url: URL) {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    drawGlyph(ctx)
    ctx.endPDFPage()
    ctx.closePDF()

    func drawing(_ pdf: Data) -> String {
        String(data: pdf, encoding: .isoLatin1)!
            .replacingOccurrences(of: #"/(CreationDate|ModDate) \([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/ID \[[^\]]*\]"#, with: "", options: .regularExpression)
    }
    if let old = try? Data(contentsOf: url), drawing(old) == drawing(data as Data) { return }
    try! (data as Data).write(to: url)
}

/// The exported appearances, in the order the variants sheet shows them.
let appearances: [(name: String, palette: Palette)] = [("default", .standard), ("light", .light),
                                                        ("dark", .dark), ("tinted", .tinted)]

func render(pixels: Int, palette: Palette) -> CGImage {
    let saved = brand
    brand = palette
    defer { brand = saved }
    return render(pixels: pixels)
}

/// A variants sheet: every appearance at 256, 32 and 16 px, then the glyph at
/// 256, 32 and 16 px, on a light and a dark desktop.
func variantsSheet() -> CGImage {
    let colW: CGFloat = 400, rowH: CGFloat = 360
    let columns = appearances.count + 1
    let ctx = makeContext(Int(colW) * columns, Int(rowH) * 2)
    for (row, gray) in [(1, 0.93), (0, 0.13)] as [(Int, CGFloat)] {
        let y0 = CGFloat(row) * rowH
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: y0, width: colW * CGFloat(columns), height: rowH))
        for column in 0..<columns {
            var x = CGFloat(column) * colW + 20
            for px in [256, 32, 16] {
                let image: CGImage
                if column < appearances.count {
                    image = render(pixels: px, palette: appearances[column].palette)
                } else {
                    image = renderGlyph(pixels: px)
                }
                let size = CGFloat(px)
                ctx.draw(image, in: CGRect(x: x, y: y0 + 52, width: size, height: size))
                x += size + 24
            }
        }
    }
    return ctx.makeImage()!
}

/// Writes the brand assets other parts of the project use: the icon in every
/// appearance at 1024 px (the default one is the README image) and the glyph.
func exportBrandAssets(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, palette) in appearances {
        let file = name == "default" ? "tabbi-icon-1024.png" : "tabbi-icon-\(name)-1024.png"
        writePNG(render(pixels: 1024, palette: palette), to: folder.appendingPathComponent(file))
    }
    exportGlyph(to: folder)
}

/// Writes the glyph as PDF and as a 256 px PNG.
func exportGlyph(to folder: URL) {
    writeGlyphPDF(to: folder.appendingPathComponent("tabbi-glyph.pdf"))
    writePNG(renderGlyph(pixels: 256), to: folder.appendingPathComponent("tabbi-glyph-256.png"))
}

// MARK: - Main

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

if let name = option("--ground") {
    guard let palette = candidatePalettes[name] else { fatalError("unknown ground \(name)") }
    brand = palette
}

if let path = option("--sheet") {
    let reference = option("--reference").flatMap { NSImage(contentsOfFile: $0) }
        .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    writePNG(reviewSheet(reference: reference), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}
if let path = option("--dock") {
    writePNG(dockSheet(), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}
if let path = option("--variants") {
    writePNG(variantsSheet(), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}
if args.contains("--glyph") {
    let assets = root.appendingPathComponent("docs/brand/assets")
    exportGlyph(to: assets)
    print(assets.path)
    exit(0)
}
if let path = option("--preview") {
    writePNG(render(pixels: 1024), to: URL(fileURLWithPath: path))
    print(path)
    exit(0)
}
guard option("--ground") == nil else {
    fatalError("--ground only works with --sheet, --dock or --preview; the shipped icon always uses its own palette")
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

let assets = root.appendingPathComponent("docs/brand/assets")
try exportBrandAssets(to: assets)
print(assets.path)
