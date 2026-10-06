import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

extension SettingsPane {
    /// Settings › Focus. Today and the Focus tab both offer it, since either
    /// can run the timer; the Settings window shows it once.
    @MainActor static func focus(_ controller: FocusController) -> SettingsPane {
        SettingsPane(id: "focus", title: "Focus", symbol: "moon",
                     view: AnyView(FocusSettingsPane(controller: controller)))
    }
}

/// Settings › Focus: what plays and whether Do Not Disturb turns on while
/// the focus timer (in Today or the Focus tab) runs. Edits go straight to
/// `FocusController`, which saves them and applies sound changes live.
struct FocusSettingsPane: View {
    @ObservedObject var controller: FocusController
    @State private var testing: ShortcutKind?
    @State private var testResult: (kind: ShortcutKind, result: FocusShortcutResult)?

    var body: some View {
        Form {
            soundSection
            playlistSection
            doNotDisturbSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500, height: height)
        .motion(Motion.content, value: height)
        .onDisappear { controller.setPreviewing(false) }
        .onChange(of: controller.settings.mix.isOff) { _, isOff in
            if isOff { controller.setPreviewing(false) }
        }
    }

    /// The grouped form doesn't report its content height, so add up the
    /// rows that come and go; the window follows the pane's size.
    private var height: CGFloat {
        var height: CGFloat = 586
        if mix.layers.count > 1 { height += CGFloat(mix.layers.count) * 37 }
        if playlistStatus != nil { height += 40 }
        if testResult != nil { height += 40 }
        return height
    }

    // MARK: Sound

    private var soundSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(FocusSound.allCases) { sound in
                    SoundChip(sound: sound, isOn: mix.contains(sound), isEnabled: mix.contains(sound) || mix.canAddLayer) {
                        controller.settings.mix.toggle(sound)
                    }
                }
            }
            .padding(.vertical, 2)

            if mix.layers.count > 1 {
                ForEach(mix.layers, id: \.sound) { layer in
                    LabeledContent(layer.sound.displayName) {
                        HStack(spacing: 8) {
                            Image(systemName: layer.sound.symbolName)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Slider(value: levelBinding(for: layer.sound), in: 0...1)
                                .help("How loud \(layer.sound.displayName.lowercased()) is in the blend")
                        }
                        .font(.callout)
                        .frame(width: sliderWidth)
                    }
                }
            }

            LabeledContent("Volume") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: volumeBinding, in: 0...1)
                        .help("Focus sound volume")
                }
                .font(.callout)
                .frame(width: sliderWidth)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus sound")
                Spacer()
                Button {
                    controller.setPreviewing(!controller.isPreviewing)
                } label: {
                    Label(controller.isPreviewing ? "Stop" : "Preview",
                          systemImage: controller.isPreviewing ? "stop.fill" : "play.fill")
                }
                .controlSize(.small)
                .disabled(mix.isOff || controller.isFocusing)
                .help(previewHelp)
            }
        } footer: {
            Footer("Blend up to three, or pick none for silence. Made on your Mac; fades in with focus and out at your break.")
        }
    }

    private var mix: FocusMix { controller.settings.mix }

    /// Every slider (and the controls sharing its column) uses this width,
    /// so the rows line up.
    private let sliderWidth: CGFloat = 240

    private var previewHelp: String {
        if controller.isFocusing { return "Already playing: focus is running" }
        if mix.isOff { return "Pick a sound to preview it" }
        return controller.isPreviewing ? "Stop the preview" : "Listen to \(mix.summary)"
    }

    private var volumeBinding: Binding<Double> {
        Binding(get: { Double(controller.settings.volume) },
                set: { controller.settings.volume = Float($0) })
    }

    private func levelBinding(for sound: FocusSound) -> Binding<Double> {
        Binding(get: { Double(controller.settings.mix.level(of: sound) ?? 0) },
                set: { controller.settings.mix.setLevel(Float($0), for: sound) })
    }

    // MARK: Playlist

    private var playlistSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    TextField("Playlist", text: $controller.settings.playlistText,
                              prompt: Text("Spotify link or Music playlist name"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .frame(width: sliderWidth)
                        .help("A Spotify link or URI, an Apple Music link, or the name of a playlist in your Music library")
                    Menu {
                        ForEach(MediaSource.allCases, id: \.self) { source in
                            Section(source == .spotify ? "Spotify" : "Apple Music") {
                                ForEach(FocusPlaylistPreset.all.filter { $0.source == source }) { preset in
                                    Button("\(preset.name) · \(preset.curator)") {
                                        controller.settings.playlistText = preset.link
                                    }
                                }
                            }
                        }
                        if !controller.settings.playlistText.isEmpty {
                            Divider()
                            Button("None") { controller.settings.playlistText = "" }
                        }
                    } label: {
                        Text("Presets")
                    }
                    .fixedSize()
                    .help("Pick a cozy focus playlist")
                }
            } label: {
                Text("Playlist")
            }
            if let status = playlistStatus {
                Label {
                    Text(status.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.isWarning ? Color.orange : Color.secondary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(status.text)
            }
        } header: {
            Text("Music")
        } footer: {
            Footer("Starts with focus unless music is already playing, and pauses at your break.")
        }
    }

    private var playlistStatus: (text: String, symbol: String, isWarning: Bool)? {
        let text = controller.settings.playlistText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let playlist = FocusPlaylist(text) else {
            return ("Not a Spotify or Apple Music link.", "exclamationmark.triangle.fill", true)
        }
        let preset = FocusPlaylistPreset.matching(text)
        switch playlist {
        case .spotify:
            return (preset.map { "\($0.name) by \($0.curator), plays in Spotify." } ?? "Plays in Spotify.",
                    "checkmark.circle.fill", false)
        case .appleMusicLink:
            let name = preset.map { "\($0.name) opens" } ?? "Opens"
            return ("\(name) in Music; press play there. Add it to your library and type its name to autoplay.",
                    "info.circle.fill", false)
        case .musicLibrary(let name):
            return ("Plays \u{201C}\(name)\u{201D} from your Music library.", "checkmark.circle.fill", false)
        }
    }

    // MARK: Do Not Disturb

    private var doNotDisturbSection: some View {
        Section {
            Toggle("Turn on Do Not Disturb during focus", isOn: $controller.settings.doNotDisturb)
            .help("Run your Focus shortcuts when the focus timer starts and stops")
            shortcutRow(.on)
            shortcutRow(.off)
            if let testResult {
                Label {
                    Text(testResult.result.message)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: testResult.result.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(testResult.result.succeeded ? Color.green : Color.orange)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Do Not Disturb")
        } footer: {
            Footer(guide)
        }
    }

    private func shortcutRow(_ kind: ShortcutKind) -> some View {
        let binding = kind == .on ? $controller.settings.onShortcut : $controller.settings.offShortcut
        let name = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return LabeledContent(kind == .on ? "When focus starts" : "When focus ends") {
            HStack(spacing: 8) {
                TextField("Shortcut name", text: binding, prompt: Text(kind.suggestedName))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 180)
                    .help("The exact name of the shortcut in the Shortcuts app")
                Button {
                    test(kind, name: name)
                } label: {
                    if testing == kind {
                        Spinner()
                            .frame(minWidth: 36)
                    } else {
                        Text("Test").frame(minWidth: 36)
                    }
                }
                .disabled(name.isEmpty || testing != nil)
                .help(name.isEmpty ? "Type a shortcut name first" : "Run \u{201C}\(name)\u{201D} now")
            }
        }
        .disabled(!controller.settings.doNotDisturb)
    }

    private func shortcutName(_ kind: ShortcutKind) -> String {
        let name = (kind == .on ? controller.settings.onShortcut : controller.settings.offShortcut)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? kind.suggestedName : name
    }

    private func test(_ kind: ShortcutKind, name: String) {
        testing = kind
        testResult = nil
        Task {
            let result = await controller.testShortcut(name)
            testing = nil
            withMotion(Motion.snappy) {
                testResult = (kind, result)
            }
        }
    }

    /// The setup guide. macOS has no public Do Not Disturb API, so the
    /// shortcuts do the switching; the link opens the Shortcuts app.
    private var guide: AttributedString {
        let on = shortcutName(.on), off = shortcutName(.off)
        let markdown = "In [Shortcuts](shortcuts://), make \u{201C}\(on)\u{201D} with the Set Focus action turning Do Not Disturb on, and \u{201C}\(off)\u{201D} turning it off. Then press Test."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private enum ShortcutKind {
        case on, off

        var suggestedName: String {
            self == .on ? FocusSettings.suggestedOnShortcut : FocusSettings.suggestedOffShortcut
        }
    }
}

/// One focus sound as a toggleable tile in the blend grid.
private struct SoundChip: View {
    let sound: FocusSound
    let isOn: Bool
    let isEnabled: Bool
    let toggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: sound.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(sound.displayName)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .transition(.motionPop)
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(isHovered ? 0.22 : 0.15)
                               : Color.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .motion(Motion.snappy, value: isOn)
        .motion(Motion.hover, value: isHovered)
        .help(help)
    }

    private var help: String {
        if isOn { return "Remove \(sound.displayName.lowercased()) from the blend" }
        if !isEnabled { return "Blend up to \(FocusMix.maxLayers) sounds; remove one first" }
        return "Add \(sound.displayName.lowercased())"
    }
}

/// Explanatory text under a section, matching the other panes' footers.
private struct Footer: View {
    let text: AttributedString
    init(_ text: String) { self.text = AttributedString(text) }
    init(_ text: AttributedString) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
