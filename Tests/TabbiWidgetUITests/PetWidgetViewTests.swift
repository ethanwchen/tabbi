import AppKit
import SwiftUI
import TabbiKitCore
@testable import TabbiWidgetUI
import XCTest

/// Snapshot-style tests: each widget state renders at the real widget sizes
/// in light and dark mode and in the tinted and vibrant rendering modes. Set
/// TABBI_WIDGET_SNAPSHOTS to a folder to also write the PNGs there and look
/// at them.
@MainActor
final class PetWidgetViewTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    /// The real time, in whole seconds: live timer text counts against the
    /// wall clock, so a fixed past date would render every countdown as 0:00.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    private var today: PlannerDayKey { PlannerDayKey(date: now, calendar: calendar) }

    private var states: [(name: String, state: WidgetState)] {
        var dressed = PetProfile.starter(.cat)
        dressed.outfit = PetOutfit.allCases.last ?? .none
        // The longest name the Closet keeps.
        let longName = PetProfile(name: "Sir Biscuit Wellington", breed: .goldenRetriever)
        return [
            ("focus", .sample(at: now, calendar: calendar)),
            ("idle", WidgetState(pet: .starter(.cat), day: today, focusMinutes: 135, streakDays: 12,
                                 lastFocusDay: today)),
            ("empty", .empty(at: now, calendar: calendar)),
            ("break", WidgetState(pet: dressed, day: today, focusMinutes: 50, streakDays: 1, lastFocusDay: today,
                                  timer: .init(phase: .rest, label: "Long break",
                                               clock: .countdown(endsAt: now.addingTimeInterval(9 * 60))))),
            ("paused", WidgetState(pet: dressed, day: today, focusMinutes: 20, streakDays: 3, lastFocusDay: today,
                                   timer: .init(phase: .focus, label: "Focus", clock: .paused(shown: 754)))),
            ("countup", WidgetState(pet: longName, day: today, focusMinutes: 999, streakDays: 365, lastFocusDay: today,
                                    timer: .init(phase: .focus, label: "Focus",
                                                 clock: .countUp(since: now.addingTimeInterval(-3725))))),
            ("long-name", WidgetState(pet: longName, day: today, focusMinutes: 1439, streakDays: 1000,
                                      lastFocusDay: today)),
        ]
    }

    func testEveryStateRendersAtWidgetSizeInEveryAppearanceAndMode() throws {
        let waiting = WidgetState.empty(at: now, calendar: calendar)
        for (name, state, isWaiting) in states.map({ ($0.name, $0.state, false) }) + [("waiting", waiting, true)] {
            for size in [PetWidgetSize.small, .medium] {
                for scheme in [ColorScheme.light, .dark] {
                    for rendering in PetWidgetRendering.allCases {
                        let image = try render(state, size: size, scheme: scheme, rendering: rendering,
                                               isWaitingForApp: isWaiting)
                        let points = Self.points(for: size)
                        let label = "\(name)-\(size)-\(scheme)-\(rendering)"
                        XCTAssertEqual(image.width, Int(points.width) * 2, label)
                        XCTAssertEqual(image.height, Int(points.height) * 2, label)
                        try save(image, name: rendering == .fullColor ? "\(name)-\(size)-\(scheme)" : label)
                        // Never blank: the content draws well beyond the
                        // background in every state and mode.
                        XCTAssertGreaterThan(try changedPixels(image, try backdrop(size: size, scheme: scheme,
                                                                                    rendering: rendering)),
                                             2000, label)
                    }
                }
            }
        }
    }

    func testBackgroundFollowsTheDesktopAppearance() throws {
        let state = WidgetState.sample(at: now, calendar: calendar)
        let light = try render(state, size: .small, scheme: .light)
        let dark = try render(state, size: .small, scheme: .dark)
        // A corner pixel is the card's background: cream in light mode,
        // cocoa in dark mode.
        XCTAssertGreaterThan(luminance(light, x: 2, y: 2), 0.9)
        XCTAssertLessThan(luminance(dark, x: 2, y: 2), 0.2)
    }

    func testWaitingStateAsksToOpenTabbiInsteadOfShowingZeros() throws {
        let empty = WidgetState.empty(at: now, calendar: calendar)
        for size in [PetWidgetSize.small, .medium] {
            let waiting = try render(empty, size: size, scheme: .light, isWaitingForApp: true)
            let zeros = try render(empty, size: size, scheme: .light)
            XCTAssertGreaterThan(try changedPixels(waiting, zeros), 500, "\(size)")
        }
    }

    /// Outside full color WidgetKit draws everything that is not an image in
    /// one color, by coverage, on the wallpaper. Drawn that way, the old
    /// opaque cream tile became a solid block over the pet and its name
    /// (the "blank white widget"); the tinted and vibrant styles keep the
    /// tile a faint fill, so what sits on it still shows.
    func testTintedAndVibrantModesNeverFlattenIntoSolidBlocks() throws {
        let state = WidgetState(pet: .starter(.cat), day: today, focusMinutes: 135, streakDays: 12, lastFocusDay: today)
        // The medium pet tile, in pixels at 2x: x 16...128, y 16...154 points.
        let tile = CGRect(x: 40, y: 40, width: 180, height: 220)
        for scheme in [ColorScheme.light, .dark] {
            let fullColor = try flattened(state, size: .medium, scheme: scheme, rendering: .fullColor)
            XCTAssertGreaterThan(try opaqueShare(fullColor, in: tile), 0.95, "the old look floods the tile \(scheme)")
            for rendering in [PetWidgetRendering.accented, .vibrant] {
                let image = try flattened(state, size: .medium, scheme: scheme, rendering: rendering)
                try save(image, name: "flattened-medium-\(scheme)-\(rendering)")
                XCTAssertLessThan(try opaqueShare(image, in: tile), 0.5, "\(scheme) \(rendering)")
            }
            try save(fullColor, name: "flattened-medium-\(scheme)-fullColor-before")
        }
    }

    func testPetIsDrawnWithWholeDevicePixelsPerSpritePixel() throws {
        let pet = PetProfile.starter(.cat)
        let canvas = pet.sittingCanvas()
        let renderer = ImageRenderer(content: PetSprite(pet: pet, pointsPerPixel: 3))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, canvas.width * 6)
        XCTAssertEqual(image.height, canvas.height * 6)
        // Every sprite pixel is a solid 6x6 block: no smoothing at the edges.
        let pixels = try XCTUnwrap(RGBA(image))
        for y in stride(from: 0, to: image.height, by: 6) {
            for x in stride(from: 0, to: image.width, by: 6) {
                let corner = pixels[x, y]
                XCTAssertEqual(pixels[x + 5, y + 5], corner, "block at \(x / 6), \(y / 6)")
            }
        }
    }

    func testFinishedCountdownShowsTodaysMinutesInstead() throws {
        let running = WidgetState.sample(at: now, calendar: calendar)
        var stopped = running
        stopped.timer = nil
        let later = now.addingTimeInterval(30 * 60)
        for size in [PetWidgetSize.small, .medium] {
            let finished = try render(running, at: later, size: size, scheme: .light)
            // The same picture, compared by pixel: a busy parallel run can
            // composite text a level of color apart, so bytes may differ.
            XCTAssertEqual(try changedPixels(finished, try render(stopped, at: later, size: size, scheme: .light)), 0,
                           "\(size) finished countdown")
            XCTAssertGreaterThan(try changedPixels(finished, try render(running, at: now, size: size, scheme: .light)), 100,
                                 "\(size) running countdown")
        }
    }

    /// Pixels whose color differs by more than `tolerance` levels in any
    /// channel; antialiasing noise from the compositor stays under it.
    private func changedPixels(_ a: CGImage, _ b: CGImage, tolerance: Int = 4) throws -> Int {
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        let lhs = try XCTUnwrap(RGBA(a)), rhs = try XCTUnwrap(RGBA(b))
        var changed = 0
        for y in 0..<min(a.height, b.height) {
            for x in 0..<min(a.width, b.width) {
                let p = lhs[x, y], q = rhs[x, y]
                let delta = max(abs(Int(p.r) - Int(q.r)), abs(Int(p.g) - Int(q.g)),
                                abs(Int(p.b) - Int(q.b)), abs(Int(p.a) - Int(q.a)))
                if delta > tolerance { changed += 1 }
            }
        }
        return changed
    }

    // MARK: Helpers

    /// The macOS widget sizes in points.
    private static func points(for size: PetWidgetSize) -> CGSize {
        switch size {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        }
    }

    /// The view as WidgetKit lays it out: its family's size, the default
    /// content margins and the container background. Outside full color the
    /// system removes that background, so those modes draw on a stand-in
    /// for the wallpaper instead.
    private func render(_ state: WidgetState, at date: Date? = nil, size: PetWidgetSize, scheme: ColorScheme,
                        rendering: PetWidgetRendering = .fullColor, isWaitingForApp: Bool = false,
                        background: Color? = nil) throws -> CGImage {
        let points = Self.points(for: size)
        let content = PetWidgetView(state: state, date: date ?? now, size: size, rendering: rendering,
                                    isWaitingForApp: isWaitingForApp)
            .padding(16)
            .frame(width: points.width, height: points.height)
            .background(background ?? Self.backdropColor(scheme: scheme, rendering: rendering))
            .environment(\.colorScheme, scheme)
            .environment(\.calendar, calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    private static func backdropColor(scheme: ColorScheme, rendering: PetWidgetRendering) -> Color {
        rendering == .fullColor ? WidgetPalette(scheme: scheme, rendering: .fullColor).background
            : WidgetPalette.color(scheme == .dark ? 0x1F2833 : 0xC9D3DE)
    }

    private func backdrop(size: PetWidgetSize, scheme: ColorScheme, rendering: PetWidgetRendering) throws -> CGImage {
        let points = Self.points(for: size)
        let renderer = ImageRenderer(content: Self.backdropColor(scheme: scheme, rendering: rendering)
            .frame(width: points.width, height: points.height))
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    /// The widget as one color by coverage on a dark wallpaper, the way the
    /// tinted and vibrant modes draw non-image content: white where the
    /// view draws anything opaque, the wallpaper where it draws nothing.
    private func flattened(_ state: WidgetState, size: PetWidgetSize, scheme: ColorScheme,
                           rendering: PetWidgetRendering) throws -> CGImage {
        let image = try render(state, size: size, scheme: scheme, rendering: rendering, background: .clear)
        let pixels = try XCTUnwrap(RGBA(image))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let alpha = Double(pixels[x, y].a) / 255
                let i = (y * image.width + x) * 4
                for (channel, wallpaper) in [0x1F, 0x28, 0x33].enumerated() {
                    bytes[i + channel] = UInt8(Double(wallpaper) + (255 - Double(wallpaper)) * alpha)
                }
                bytes[i + 3] = 255
            }
        }
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    /// The share of pixels in `rect` that the flattening turned (nearly) white.
    private func opaqueShare(_ image: CGImage, in rect: CGRect) throws -> Double {
        let pixels = try XCTUnwrap(RGBA(image))
        var opaque = 0, total = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                total += 1
                if pixels[x, y].r > 235 { opaque += 1 }
            }
        }
        return Double(opaque) / Double(max(total, 1))
    }

    private func save(_ image: CGImage, name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["TABBI_WIDGET_SNAPSHOTS"] else { return }
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png(image).write(to: url)
    }

    private func png(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func luminance(_ image: CGImage, x: Int, y: Int) -> Double {
        guard let pixels = RGBA(image) else { return .nan }
        let p = pixels[x, y]
        return (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
    }
}

/// An image's pixels as 8-bit RGBA, for reading single pixels.
private struct RGBA {
    struct Pixel: Equatable { var r, g, b, a: UInt8 }

    let width: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.bytes = bytes
    }

    /// The pixel `x` across and `y` down from the top left.
    subscript(x: Int, y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3])
    }
}
