import AppKit
import SwiftUI
import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// The Timer's focus sound mixer, the way a user reaches it: the real notch
/// view in the notch's own panel opens on the Timer, a click on the sound
/// button opens the mixer, and clicks and drags there change the shared
/// focus settings. Events go straight to the window, so the system pointer
/// never moves. Demo mode keeps focus mode inert (no sound, no scripts);
/// `FocusControllerTests` covers what a pick then plays.
@MainActor
final class StudySoundMixerClickTests: XCTestCase {
    private var services: AppServices!
    private var panel: NotchPanel!

    /// Where the mixer draws its controls in the regular panel, in the
    /// hosting view's points (y down), measured from its snapshot.
    private enum Layout {
        /// The sound button beside the deep focus switch, on the timer.
        static let soundButton = CGPoint(x: 473, y: 132)
        /// The first playlist row; the next ones follow every `rowPitch`.
        static let firstPlaylistRow = CGPoint(x: 440, y: 105)
        static let rowPitch: CGFloat = 18
        /// The volume slider's track, left to right, and its row.
        static let volumeTrack: ClosedRange<CGFloat> = 62...296
        static let volumeY: CGFloat = 205
    }

    private func open(direction: LayoutDirection = .leftToRight) async throws {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        for id in settings.catalog.ids where id != .study {
            settings.settings.modules.setEnabled(id, false)
        }
        settings.settings.modules.setEnabled(.study, true)
        services = AppServices(settings: settings, environment: ["TABBI_DEMO": "1"], arguments: [])

        let geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        let model = NotchViewModel(geometry: geometry, layout: settings.settings.modules)
        model.open(.study)
        let root = NotchView(content: ModuleViews.notchContent(services: services))
            .environmentObject(model)
            .environment(\.layoutDirection, direction)
        panel = NotchPanel(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: model.openSize))
        panel.ignoresMouseEvents = false
        panel.contentView = NotchHostingView(rootView: root)
        panel.orderFrontRegardless()
        try await settle()
        let soundButton = direction == .leftToRight ? Layout.soundButton : mirrored(Layout.soundButton)
        try await click(soundButton)
    }

    override func tearDown() async throws {
        panel?.orderOut(nil)
        panel = nil
        services = nil
    }

    private var focus: FocusController {
        get throws { try XCTUnwrap(services.modules.module(FocusModule.self)).focusMode }
    }

    // MARK: - Playlist

    func testClickingAPlaylistPicksItAndClickingItAgainTurnsItOff() async throws {
        try await open()
        let presets = FocusPlaylistPreset.all
        XCTAssertEqual(try focus.settings.playlistText, presets[0].link, "the demo starts on the first preset")

        try await click(playlistRow(1))
        XCTAssertEqual(try focus.settings.playlistText, presets[1].link, "the click picks the row")
        try await click(playlistRow(1))
        XCTAssertEqual(try focus.settings.playlistText, "", "a second click turns it off")
        try await click(playlistRow(5))
        XCTAssertEqual(try focus.settings.playlistText, presets[5].link, "an Apple Music row works too")
    }

    func testYourPlaylistRowKeepsTheLinkUntilAPresetReplacesIt() async throws {
        try await open()
        let link = "https://open.spotify.com/playlist/7mnUheJnHPdAyq5ZW5bWyZ"
        try focus.settings.playlistText = link
        try await settle()
        // The row on top is "Your playlist": its click plays the link again
        // (a live run scripts it; demo mode stays quiet) and never drops it.
        try await click(playlistRow(0))
        XCTAssertEqual(try focus.settings.playlistText, link)
        try await click(playlistRow(1))
        XCTAssertEqual(try focus.settings.playlistText, FocusPlaylistPreset.all[0].link, "a preset replaces it")
    }

    // MARK: - Volume

    func testTheVolumeFollowsTheDragAcrossTheWholeTrack() async throws {
        try await open()
        let track = Layout.volumeTrack
        let xs = stride(from: track.lowerBound + 20, through: track.upperBound - 20, by: 10).map { $0 }
        let volumes = try await drag(xs: [track.lowerBound + 2, track.lowerBound - 30] + xs
                                         + [track.upperBound + 40, track.upperBound + 40])
        XCTAssertEqual(volumes[1], 0, "dragged past the left end pins at 0")
        XCTAssertEqual(volumes.last, 1, "dragged past the right end pins at 1")
        let inside = Array(volumes.dropFirst(2).dropLast(2))
        let steps = zip(inside.dropFirst(), inside).map { $0 - $1 }
        XCTAssertFalse(steps.isEmpty)
        for step in steps {
            // Equal pointer steps make equal volume steps: the level glides
            // with the pointer, never jumping or lagging.
            XCTAssertEqual(step, steps[0], accuracy: 0.002)
            XCTAssertGreaterThan(step, 0)
        }
    }

    func testTheVolumeRunsLeftToRightInArabic() async throws {
        try await open(direction: .rightToLeft)
        // The mixer mirrors, so the track sits on the other side, but it
        // still fills from the left as Tabbi's bars do.
        let track = mirrored(Layout.volumeTrack)
        let volumes = try await drag(xs: [track.lowerBound + 10, track.upperBound - 10, track.upperBound - 10])
        XCTAssertLessThan(volumes[0], 0.1)
        XCTAssertGreaterThan(volumes[1], 0.9)
    }

    // MARK: - Helpers

    private var width: CGFloat { panel.contentView?.bounds.width ?? 0 }

    private func mirrored(_ point: CGPoint) -> CGPoint { CGPoint(x: width - point.x, y: point.y) }

    private func mirrored(_ range: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> {
        (width - range.upperBound)...(width - range.lowerBound)
    }

    private func playlistRow(_ index: Int) -> CGPoint {
        CGPoint(x: Layout.firstPlaylistRow.x, y: Layout.firstPlaylistRow.y + CGFloat(index) * Layout.rowPitch)
    }

    private func settle() async throws {
        for _ in 0..<10 {
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func click(_ point: CGPoint) async throws {
        try send(.leftMouseDown, at: point)
        try send(.leftMouseUp, at: point)
        try await settle()
    }

    /// Presses at the first x, drags through the rest and releases at the
    /// last, on the volume row; returns the volume after each event.
    private func drag(xs: [CGFloat]) async throws -> [Float] {
        var volumes: [Float] = []
        for (index, x) in xs.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown
                : (index == xs.count - 1 ? .leftMouseUp : .leftMouseDragged)
            try send(type, at: CGPoint(x: x, y: Layout.volumeY))
            try await Task.sleep(for: .milliseconds(20))
            volumes.append(try focus.settings.volume)
        }
        try await settle()
        return volumes
    }

    private func send(_ type: NSEvent.EventType, at point: CGPoint) throws {
        let content = try XCTUnwrap(panel.contentView)
        let location = content.convert(point, to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        panel.sendEvent(event)
    }
}
