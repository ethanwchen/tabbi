import AppKit
import SwiftUI
import TabbiKitCore
@testable import TabbiWidgetUI
import XCTest

/// Snapshot-style tests: each widget state renders at the real widget sizes
/// in light and dark mode. Set TABBI_WIDGET_SNAPSHOTS to a folder to also
/// write the PNGs there and look at them.
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
        ]
    }

    func testEveryStateRendersAtWidgetSizeInBothAppearances() throws {
        for (name, state) in states {
            for size in [PetWidgetSize.small, .medium] {
                for scheme in [ColorScheme.light, .dark] {
                    let image = try render(state, size: size, scheme: scheme)
                    let points = Self.points(for: size)
                    XCTAssertEqual(image.width, Int(points.width) * 2, "\(name) \(size) \(scheme)")
                    XCTAssertEqual(image.height, Int(points.height) * 2, "\(name) \(size) \(scheme)")
                    try save(image, name: "\(name)-\(size)-\(scheme)")
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
            let finished = try png(render(running, at: later, size: size, scheme: .light))
            XCTAssertEqual(finished, try png(render(stopped, at: later, size: size, scheme: .light)))
            XCTAssertNotEqual(finished, try png(render(running, at: now, size: size, scheme: .light)))
        }
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
    /// content margins and the container background, with rounded corners.
    private func render(_ state: WidgetState, at date: Date? = nil, size: PetWidgetSize,
                        scheme: ColorScheme) throws -> CGImage {
        let points = Self.points(for: size)
        let content = PetWidgetView(state: state, date: date ?? now, size: size)
            .padding(16)
            .frame(width: points.width, height: points.height)
            .background(WidgetPalette.background)
            .environment(\.colorScheme, scheme)
            .environment(\.calendar, calendar)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
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
