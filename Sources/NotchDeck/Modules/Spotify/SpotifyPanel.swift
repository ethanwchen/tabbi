import SwiftUI
import NotchDeckCore

struct SpotifyPanel: View {
    @ObservedObject var controller: SpotifyController

    var body: some View {
        ModulePlaceholder(module: .spotify, detail: "Spotify controls are coming soon")
    }
}

struct SpotifyCompactLeading: View {
    @ObservedObject var controller: SpotifyController
    var body: some View { Color.clear }
}

struct SpotifyCompactTrailing: View {
    @ObservedObject var controller: SpotifyController
    var body: some View { Color.clear }
}
