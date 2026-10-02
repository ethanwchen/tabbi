import SwiftUI
import NotchKitCore

/// Now Playing: Spotify and Apple Music controls. `SpotifyController`
/// keeps its own timers in step with the panel.
@MainActor
final class NowPlayingModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .spotify)
    private let controller: SpotifyController

    init(controller: SpotifyController) {
        self.controller = controller
    }

    func makePanel() -> AnyView {
        AnyView(SpotifyPanel(controller: controller))
    }
}
