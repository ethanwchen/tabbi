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
    private let controller: SpotifyController

    init(controller: SpotifyController) {
        self.controller = controller
    }

    func makePanel() -> AnyView {
        AnyView(SpotifyPanel(controller: controller))
    }
}
