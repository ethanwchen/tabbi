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
    /// Also drives the closed notch's music wings and, until Now Playing
    /// provides its highlight like every other module (review B3), the ticker.
    let controller = SpotifyController()

    init(context: ModuleContext) {}

    func makePanel() -> AnyView {
        AnyView(SpotifyPanel(controller: controller))
    }
}
