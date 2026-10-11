import AppKit
import SwiftUI
import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// The shared notch slider under a real drag: a hosted `TrackSlider` gets
/// mouse down, dragged and up events, and both the values it reports and
/// the knob it draws mid-drag are checked. The knob must stay on the track
/// at both ends and sit under the pointer, with the drag highlight on.
@MainActor
final class TrackSliderDragTests: XCTestCase {
    private final class Values {
        var changes: [Double] = []
        var commits: [Double] = []
    }

    /// The slider's frame in the hosting view, which is flipped (y down).
    private let track = CGRect(x: 50, y: 50, width: 200, height: 20)
    private var window: NSWindow!
    private var values: Values!

    override func setUp() async throws {
        values = Values()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
    }

    private func host(value: Double, direction: LayoutDirection = .leftToRight) async throws {
        let values = values!
        let root = TrackSlider(value: value, tint: .red, knobDiameter: 8, help: "Volume",
                               accessibilityLabel: "Volume", accessibilityValue: "",
                               onChange: { values.changes.append($0) },
                               onCommit: { values.commits.append($0) })
            .frame(width: track.width, height: track.height)
            .padding(50)
            .background(Color.black)
            .environment(\.layoutDirection, direction)
        window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: 300, height: 120),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        try await settle()
    }

    func testDraggingReportsTheValueUnderThePointerAndPinsAtTheEnds() async throws {
        try await host(value: 0.5)
        let geometry = TrackSliderGeometry(width: track.width, knobDiameter: 8 * 1.25)
        // Pointer positions along the track: pressed near its start, dragged
        // off its left end, then across it and past its right end.
        let xs: [Double] = [5, -30, 50, 51, 100, 199, 250]
        try await drag(through: xs.map { CGPoint(x: track.minX + $0, y: track.midY) })
        let expected = xs.dropLast().map { geometry.fraction(atX: $0) }
        XCTAssertEqual(values.changes.count, expected.count)
        for (got, want) in zip(values.changes, expected) {
            XCTAssertEqual(got, want, accuracy: 1e-6)
        }
        XCTAssertEqual(values.changes[1], 0, "left of the track pins at 0")
        XCTAssertEqual(values.commits, [1], "released past the end, it commits 1")
    }

    func testTheDragKeepsTrackingWhenThePointerLeavesTheThinTrack() async throws {
        try await host(value: 0)
        try await drag(through: [CGPoint(x: 100, y: track.midY), CGPoint(x: 150, y: track.midY + 45),
                                 CGPoint(x: 200, y: track.midY - 45), CGPoint(x: 200, y: track.midY - 45)])
        XCTAssertEqual(values.changes.count, 3)
        XCTAssertLessThan(values.changes[0], values.changes[1])
        XCTAssertLessThan(values.changes[1], values.changes[2])
    }

    func testValuesRunLeftToRightInARightToLeftLanguage() async throws {
        try await host(value: 0.5, direction: .rightToLeft)
        try await drag(through: [CGPoint(x: 60, y: track.midY), CGPoint(x: 240, y: track.midY),
                                 CGPoint(x: 240, y: track.midY)])
        XCTAssertLessThan(values.changes[0], 0.1, "the left end is low")
        XCTAssertGreaterThan(values.changes[1], 0.9, "the right end is high")
    }

    /// The knob drawn mid-drag (grown by the drag highlight) for values at
    /// both ends and in between: always inside the track, centered on the
    /// value's position. The old slider scaled its offset along with the
    /// knob, which threw it past the track's end.
    func testTheKnobStaysOnTheTrackAndUnderThePointerWhileDragging() async throws {
        let geometry = TrackSliderGeometry(width: track.width, knobDiameter: 8 * 1.25)
        for value in [0.0, 0.45, 1.0] {
            try await host(value: value)
            let x = track.minX + geometry.knobCenter(at: value)
            try await press(at: CGPoint(x: x, y: track.midY))
            let knob = try XCTUnwrap(knobBounds(), "value \(value)")
            XCTAssertGreaterThanOrEqual(knob.minX, track.minX - 0.5, "value \(value): \(knob)")
            XCTAssertLessThanOrEqual(knob.maxX, track.maxX + 0.5, "value \(value): \(knob)")
            XCTAssertEqual(knob.midX, x, accuracy: 1, "value \(value): centered under the pointer")
            XCTAssertGreaterThan(knob.width, 8.5, "value \(value): grown while dragged")
            try await release(at: CGPoint(x: x, y: track.midY))
            window.orderOut(nil)
        }
    }

    // MARK: - Helpers

    private func settle() async throws {
        for _ in 0..<8 {
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Mouse down at the first point, dragged through the middle ones, up at the last.
    private func drag(through points: [CGPoint]) async throws {
        for (index, point) in points.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown
                : (index == points.count - 1 ? .leftMouseUp : .leftMouseDragged)
            try send(type, at: point)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await settle()
    }

    private func press(at point: CGPoint) async throws {
        try send(.leftMouseDown, at: point)
        try send(.leftMouseDragged, at: point)
        try await settle()
    }

    private func release(at point: CGPoint) async throws {
        try send(.leftMouseUp, at: point)
        try await settle()
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
        let content = try XCTUnwrap(window.contentView)
        let location = content.convert(point, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        window.sendEvent(event)
    }

    /// The bounds of the light knob pixels, in the hosting view's points.
    private func knobBounds() throws -> CGRect? {
        let content = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / content.bounds.width
        var minX = Int.max, maxX = Int.min
        for py in 0..<rep.pixelsHigh {
            for px in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                // The knob is near white; the fill is red and the track a dim gray.
                if color.redComponent > 0.8, color.greenComponent > 0.8, color.blueComponent > 0.8 {
                    minX = min(minX, px)
                    maxX = max(maxX, px)
                }
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: 0, width: CGFloat(maxX - minX + 1) / scale, height: 1)
    }
}
