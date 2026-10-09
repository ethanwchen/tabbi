import Combine
import SwiftUI
import TabbiKit
import TabbiKitCore

/// Now Playing: Spotify and Apple Music controls, and SoundCloud in Safari or
/// Chrome once the user turns it on. `SpotifyController` keeps its own
/// timers in step with the panel.
@MainActor
final class NowPlayingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .spotify, title: "Now Playing", symbol: "music.note",
        summary: "Control Spotify or Apple Music from the notch.", category: .media,
        accent: ModuleAccent(red: 0.12, green: 0.84, blue: 0.38), permissions: [.automation],
        network: [ModuleNetworkAccess(host: "i.scdn.co", purpose: "Spotify album artwork"),
                  ModuleNetworkAccess(host: "i1.sndcdn.com", purpose: "SoundCloud artwork")]
    )
    /// Also drives the closed notch's music wings.
    let controller: SpotifyController

    init(context: ModuleContext) {
        controller = SpotifyController(runMode: context.runMode, allowsBrowsers: !context.edition.isAppStore)
    }

    /// Shows a SoundCloud state in the panel for a snapshot run.
    func showForSnapshot(_ state: SpotifyController.SnapshotState) {
        controller.showForSnapshot(state)
    }

    func makePanel() -> AnyView {
        AnyView(SpotifyPanel(controller: controller))
    }

    /// The SoundCloud switch. The App Store edition can't script browsers,
    /// which leaves nothing to set there.
    func makeSettingsPane() -> SettingsPane? {
        controller.allowsBrowsers ? .nowPlaying(controller) : nil
    }

    /// Whether music is playing, so the closed notch shows the music wings.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        controller.$showsCompactActivity
            .map { ModuleProvision(isPlaying: $0) }
            .eraseToAnyPublisher()
    }
}
