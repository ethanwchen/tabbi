import SwiftUI
import TabbiKit
import TabbiKitCore

extension SettingsPane {
    /// Settings > Now Playing: whether the panel also follows SoundCloud in
    /// a browser.
    @MainActor static func nowPlaying(_ controller: SpotifyController) -> SettingsPane {
        SettingsPane(id: "nowPlaying", title: "Now Playing", symbol: NowPlayingModule.descriptor.symbol,
                     view: AnyView(NowPlayingSettingsPane(controller: controller)))
    }
}

/// Settings > Now Playing. Edits go straight to `SpotifyController`, which
/// saves them and starts or stops following SoundCloud.
struct NowPlayingSettingsPane: View {
    @ObservedObject var controller: SpotifyController

    var body: some View {
        Form {
            Section {
                Toggle("Show SoundCloud from Safari or Chrome", isOn: $controller.preferences.showsSoundCloud)
                    .help("Show and control SoundCloud playing in a Safari or Chrome tab")
            } header: {
                Text("Players")
            } footer: {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: 160)
    }

    private var footer: String {
        "Spotify and Apple Music always show. For SoundCloud, macOS asks to let \(Edition.current.name) "
            + "control your browser, and the browser needs Allow JavaScript from Apple Events turned on."
    }
}
