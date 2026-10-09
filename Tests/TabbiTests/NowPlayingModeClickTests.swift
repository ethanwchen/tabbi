import AppKit
import SwiftUI
import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// Shuffle, repeat and the heart in the open notch take a click: the real notch view,
/// hosted in the notch's own panel, gets a mouse down and up on each button
/// and the player state changes. Events go straight to the window, so the
/// system pointer never moves.
@MainActor
final class NowPlayingModeClickTests: XCTestCase {
    private var services: AppServices!
    private var panel: NotchPanel!

    override func setUp() async throws {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        for id in settings.catalog.ids where id != .spotify {
            settings.settings.modules.setEnabled(id, false)
        }
        settings.settings.modules.setEnabled(.spotify, true)
        services = AppServices(settings: settings, environment: ["TABBI_DEMO": "1"], arguments: [])

        let geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        let model = NotchViewModel(geometry: geometry, layout: settings.settings.modules)
        model.open(.spotify)
        let root = NotchView(content: ModuleViews.notchContent(services: services))
            .environmentObject(model)
        panel = NotchPanel(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: model.openSize))
        panel.ignoresMouseEvents = false
        panel.contentView = NotchHostingView(rootView: root)
        panel.orderFrontRegardless()
        try await settle()
    }

    override func tearDown() async throws {
        panel?.orderOut(nil)
        panel = nil
        services = nil
    }

    private var controller: SpotifyController {
        get throws { try XCTUnwrap(services.modules.module(NowPlayingModule.self)).controller }
    }

    private var playback: SpotifyPlayback? {
        get throws { try controller.status.playback }
    }

    func testClickingShuffleTogglesIt() async throws {
        let before = try XCTUnwrap(playback).isShuffling
        try await click(control: 0)
        XCTAssertEqual(try playback?.isShuffling, !before)
        try await click(control: 0)
        XCTAssertEqual(try playback?.isShuffling, before)
    }

    func testClickingRepeatStepsThroughThePlayersModes() async throws {
        let source = try XCTUnwrap(try controller.source)
        let start = try XCTUnwrap(playback).repeatMode
        let next = source.repeatMode(after: start)
        try await click(control: 1)
        XCTAssertEqual(try playback?.repeatMode, next)
        try await click(control: 1)
        XCTAssertEqual(try playback?.repeatMode, source.repeatMode(after: next))
    }

    func testClickingTheHeartTogglesTheFavorite() async throws {
        let before = try XCTUnwrap(playback?.track?.isFavorite)
        try await click(try likeButton())
        XCTAssertEqual(try playback?.track?.isFavorite, !before)
        try await click(try likeButton())
        XCTAssertEqual(try playback?.track?.isFavorite, before)
    }

    // MARK: - Helpers

    private func settle() async throws {
        for _ in 0..<10 {
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The transport row's controls, left to right. SwiftUI backs every
    /// focusable control with a key-view proxy subview at its frame; the
    /// accessibility tree is only built for an AX client, which a test
    /// process can't be. A wrong pick fails the state checks above.
    private func transportControls() throws -> [CGRect] {
        let content = try XCTUnwrap(panel.contentView)
        let controls = content.subviews
            .filter { NSStringFromClass(type(of: $0)).contains("KeyViewProxy") }
            .map(\.frame)
        // Play is the largest control short of the artwork.
        let play = try XCTUnwrap(controls.filter { $0.width < 100 }.max { $0.width < $1.width })
        return controls.filter { abs($0.midY - play.midY) < 1 }.sorted { $0.minX < $1.minX }
    }

    /// The heart: the only control right of the artwork and above the
    /// transport row.
    private func likeButton() throws -> CGRect {
        let content = try XCTUnwrap(panel.contentView)
        let controls = content.subviews
            .filter { NSStringFromClass(type(of: $0)).contains("KeyViewProxy") }
            .map(\.frame)
        let artwork = try XCTUnwrap(controls.filter { $0.width >= 100 }.max { $0.width < $1.width })
        let play = try XCTUnwrap(controls.filter { $0.width < 100 }.max { $0.width < $1.width })
        let hearts = controls.filter {
            $0.minX > artwork.maxX && abs($0.midY - play.midY) >= 1
                && $0.midY > artwork.minY && $0.midY < artwork.maxY
        }
        XCTAssertEqual(hearts.count, 1, "one heart beside the title")
        return try XCTUnwrap(hearts.first)
    }

    /// Clicks the transport control at `index` (shuffle is 0, repeat is 1).
    private func click(control index: Int) async throws {
        let controls = try transportControls()
        XCTAssertEqual(controls.count, 6, "shuffle, repeat, previous, play, next and volume")
        try await click(try XCTUnwrap(controls.indices.contains(index) ? controls[index] : nil))
    }

    private func click(_ frame: CGRect) async throws {
        let content = try XCTUnwrap(panel.contentView)
        let center = content.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: center, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            panel.sendEvent(event)
        }
        try await settle()
    }
}
