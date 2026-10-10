import AppKit
import XCTest
import TabbiKitCore
@testable import TabbiKit

/// On screen a pet plays in a layer of its own (`PetAnimationView`), so a
/// frame change never updates SwiftUI or lays out the notch (with a
/// `TimelineView`, six Party pets kept the notch near 4% CPU). These tests
/// prove the layer animates by itself, stops off screen, and draws the
/// speech bubble where the SwiftUI drawing puts it.
@MainActor
final class PetAnimationViewTests: XCTestCase {
    func testThePetAnimatesOnItsOwnTimer() throws {
        let player = PetPlayer(profile: .starter(.cat), seed: 1)
        let (view, window) = showInWindow()
        view.play(player, revision: player.revision, pixelSize: 1, still: false)
        let first = try XCTUnwrap(spriteImage(of: view))
        // The idle loop changes frame every second or so; no SwiftUI runs here.
        let changed = waitUntil(seconds: 3) { spriteImage(of: view).map { $0 !== first } ?? false }
        XCTAssertTrue(changed, "the pet's picture never changed")
        withExtendedLifetime(window) {}
    }

    func testThePetStopsWhenItLeavesTheWindow() throws {
        let player = PetPlayer(profile: .starter(.cat), seed: 1)
        let (view, window) = showInWindow()
        view.play(player, revision: player.revision, pixelSize: 1, still: false)
        XCTAssertTrue(view.isAnimating)
        view.removeFromSuperview()
        XCTAssertFalse(view.isAnimating)
        withExtendedLifetime(window) {}
    }

    func testTheBubbleSitsAboveTheHeadAsInTheSwiftUIDrawing() throws {
        let pixelSize: CGFloat = 2
        let player = PetPlayer(profile: .starter(.cat), seed: 1)
        player.send(.nudge)
        let (view, window) = showInWindow(side: CGFloat(PetComposer.frameSize) * pixelSize)
        // Still, as under Reduce Motion: the alert holds its frame with the bubble.
        view.play(player, revision: player.revision, pixelSize: pixelSize, still: true)
        let anchor = try XCTUnwrap(player.stillFrame(at: Date())?.bubbleAnchor)

        let bitmap = try render(view)
        // The bubble's "!" is ink in column 4, rows 1 to 3, of its 9x9 grid;
        // its bottom row sits one sprite pixel above the anchor, as in
        // `PetFrameView`. Bitmap rows count down from the top here.
        let inkX = (CGFloat(anchor.x + 1) + 4.5) * pixelSize
        let inkY = (CGFloat(anchor.y - 9) + 2.5) * pixelSize
        let ink = bitmap.pixel(x: Int(inkX), y: Int(inkY))
        XCTAssertGreaterThan(ink.alpha, 200, "no bubble where PetFrameView draws it")
        XCTAssertLessThan(ink.red, 100, "the bubble's ink is dark")
        let cream = bitmap.pixel(x: Int(inkX - 2 * pixelSize), y: Int(inkY))
        XCTAssertGreaterThan(cream.red, 230, "the bubble's body is cream")
        withExtendedLifetime(window) {}
    }

    // MARK: Helpers

    /// The view in a window it counts as visible; keep the window alive.
    private func showInWindow(side: CGFloat = 32) -> (PetAnimationView, NSWindow) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: side, height: side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = PetAnimationView()
        view.isVisible = { _ in true }
        view.frame = CGRect(x: 0, y: 0, width: side, height: side)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    private func spriteImage(of view: PetAnimationView) -> CGImage? {
        guard let contents = view.layer?.sublayers?.first?.contents else { return nil }
        return (contents as! CGImage)
    }

    private func waitUntil(seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private func render(_ view: PetAnimationView) throws -> Bitmap {
        let layer = try XCTUnwrap(view.layer)
        let width = Int(view.bounds.width), height = Int(view.bounds.height)
        var bitmap = Bitmap(width: width, height: height)
        try bitmap.pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            layer.render(in: context)
        }
        return bitmap
    }
}

/// RGBA pixels with row 0 at the top, as `CGContext` stores them.
private struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    func pixel(x: Int, y: Int) -> (red: UInt8, alpha: UInt8) {
        let index = (y * width + x) * 4
        return (pixels[index], pixels[index + 3])
    }
}
