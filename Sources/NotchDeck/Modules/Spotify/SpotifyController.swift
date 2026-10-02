import SwiftUI

/// Spotify playback state and controls.
@MainActor
final class SpotifyController: ObservableObject {
    /// When true, album art + equalizer show beside the closed notch.
    @Published var showsCompactActivity = false
}
