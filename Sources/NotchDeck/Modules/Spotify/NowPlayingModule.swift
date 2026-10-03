import Combine
import SwiftUI
import NotchKitCore

/// Now Playing: Spotify and Apple Music controls. `SpotifyController`
/// keeps its own timers in step with the panel.
@MainActor
final class NowPlayingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .spotify, title: "Now Playing", symbol: "music.note", category: .media,
        accent: ModuleAccent(red: 0.12, green: 0.84, blue: 0.38), permissions: [.automation]
    )
    /// Also drives the closed notch's music wings.
    let controller = SpotifyController()

    init(context: ModuleContext) {}

    func makePanel() -> AnyView {
        AnyView(SpotifyPanel(controller: controller))
    }

    /// Whether music is playing, so the closed notch shows the music wings.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        controller.$showsCompactActivity
            .map { ModuleProvision(isPlaying: $0) }
            .eraseToAnyPublisher()
    }
}
