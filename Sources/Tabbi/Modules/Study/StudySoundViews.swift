import SwiftUI
import TabbiKitCore
import TabbiKit

/// The focus-sound chips beside the deep focus switch: off, four sounds,
/// Mix and Playlist. They edit the shared focus settings, so the Focus
/// timer plays the same sound; Mix and Playlist open the in-notch mixer.
struct StudySoundRow: View {
    @ObservedObject var focus: FocusController
    /// Whether study blocks play the sound; the chips dim while it's off.
    let isActive: Bool
    let openMixer: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(StudySoundChip.allCases) { chip in
                StudySoundChipButton(chip: chip, isOn: chip.isSelected(in: focus.settings),
                                     isActive: isActive, help: help(for: chip)) {
                    if chip.opensMixer {
                        openMixer()
                    } else {
                        withMotion(Theme.Motion.snappy) { focus.settings = chip.applying(to: focus.settings) }
                    }
                }
            }
        }
    }

    private func help(for chip: StudySoundChip) -> String {
        let settings = focus.settings
        switch chip {
        case .off:
            return "No focus sound"
        case .mix:
            return chip.isSelected(in: settings) ? "Blend: \(settings.mix.summary). Open the mixer"
                                                 : "Blend up to \(FocusMix.maxLayers) sounds and set levels"
        case .playlist:
            guard settings.playlist != nil else { return "Pick a study playlist to start with focus" }
            let name = FocusPlaylistPreset.matching(settings.playlistText)?.name ?? "your playlist"
            return "Plays \(name) with focus. Change it in the mixer"
        default:
            return "Play \(chip.title.lowercased()) during deep focus"
        }
    }
}

/// One round chip in the sound row.
private struct StudySoundChipButton: View {
    let chip: StudySoundChip
    let isOn: Bool
    let isActive: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: chip.symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? studyAccent.opacity(isActive ? 1 : 0.7)
                                      : (hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText))
                .frame(width: 22, height: 22)
                .background(Circle().fill(isOn ? studyAccent.opacity(hovering ? 0.30 : 0.20)
                                               : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
    }
}

/// The in-notch sound mixer: blend up to three sounds with their own
/// levels, set the volume, pick a study playlist, and switch Do Not
/// Disturb. Everything edits the shared focus settings, which crossfade
/// live while focusing.
struct StudySoundMixer: View {
    @ObservedObject var focus: FocusController
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Card(padding: Theme.Spacing.s) {
                    blend.frame(maxHeight: .infinity, alignment: .top)
                }
                Card(padding: Theme.Spacing.s) {
                    StudyPlaylistList(focus: focus).frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 176)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { focus.setPreviewing(false) }
    }

    private var mix: FocusMix { focus.settings.mix }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Focus sound")
                .foregroundStyle(Theme.Palette.tertiaryText)
            Text(mix.summary)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: Theme.Spacing.s)
            StudyCapsuleToggle(title: "Do Not Disturb", symbol: "bell.slash",
                               isOn: focus.settings.doNotDisturb,
                               help: focus.settings.doNotDisturb
                                   ? "Leave notifications on while studying"
                                   : "Turn on Do Not Disturb during deep focus (runs your Focus shortcuts)") {
                focus.settings.doNotDisturb.toggle()
            }
            IconButton(symbol: focus.isPreviewing ? "stop.fill" : "play.fill", help: previewHelp) {
                focus.setPreviewing(!focus.isPreviewing)
            }
            .disabled(mix.isOff || focus.isFocusing)
            .opacity(mix.isOff || focus.isFocusing ? 0.4 : 1)
            IconButton(symbol: "xmark", help: "Back to the timer", action: close)
        }
        .font(Theme.Typography.caption)
    }

    private var previewHelp: String {
        if focus.isFocusing { return "Already playing during focus" }
        if mix.isOff { return "Pick a sound to preview it" }
        return focus.isPreviewing ? "Stop the preview" : "Listen to \(mix.summary)"
    }

    private var blend: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Blend")
                Spacer()
                Text("Up to \(FocusMix.maxLayers) sounds").monospacedDigit()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .padding(.bottom, Theme.Spacing.xxs)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 3),
                      spacing: Theme.Spacing.xs) {
                ForEach(FocusSound.allCases) { sound in
                    StudyMixTile(sound: sound, level: mix.level(of: sound),
                                 canAdd: mix.canAddLayer,
                                 toggle: { withMotion(Theme.Motion.snappy) { _ = focus.settings.mix.toggle(sound) } },
                                 setLevel: { focus.settings.mix.setLevel($0, for: sound) })
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .frame(width: 14)
                StudyLevelSlider(level: focus.settings.volume, help: "Volume") { focus.settings.volume = $0 }
                Text("\(Int((focus.settings.volume * 100).rounded()))%")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 32, alignment: .trailing)
                    .contentTransition(.numericText())
            }
            .disabled(mix.isOff)
            .opacity(mix.isOff ? 0.4 : 1)
        }
    }
}

/// One sound in the blend: tap to add or remove it; while it's in the mix
/// a level slider sits underneath.
private struct StudyMixTile: View {
    let sound: FocusSound
    /// The sound's level, or nil when it isn't in the mix.
    let level: Float?
    let canAdd: Bool
    let toggle: () -> Void
    let setLevel: (Float) -> Void
    @State private var hovering = false

    var body: some View {
        let isOn = level != nil
        let isEnabled = isOn || canAdd
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: toggle) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: sound.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14)
                    Text(sound.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .help(help(isOn: isOn, isEnabled: isEnabled))
            StudyLevelSlider(level: level ?? 0, help: "\(sound.displayName) level", action: setLevel)
                .opacity(isOn ? 1 : 0)
                .allowsHitTesting(isOn)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.s - Theme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(isOn ? studyAccent.opacity(hovering ? 0.22 : 0.15)
                           : (hovering && isEnabled ? Theme.Palette.surfaceHover : Theme.Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(studyAccent.opacity(isOn ? 0.5 : 0), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
    }

    private func help(isOn: Bool, isEnabled: Bool) -> String {
        if isOn { return "Remove \(sound.displayName.lowercased()) from the blend" }
        if !isEnabled { return "Blend up to \(FocusMix.maxLayers) sounds; remove one first" }
        return "Add \(sound.displayName.lowercased())"
    }
}

/// A thin accent slider drawn in SwiftUI, so it renders inside the notch
/// and in snapshots (a system slider would not).
private struct StudyLevelSlider: View {
    let level: Float
    let help: String
    let action: (Float) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(min(max(level, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.surfaceHover)
                Capsule()
                    .fill(studyAccent)
                    .frame(width: width * fraction)
                Circle()
                    .fill(Theme.Palette.primaryText)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: min(max(width * fraction - 4, 0), width - 8))
                    .scaleEffect(hovering ? 1.2 : 1)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    action(StudySoundChip.level(atX: value.location.x, width: width))
                }
            )
        }
        .frame(height: 10)
        .help("\(help) \(Int((level * 100).rounded()))%")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .accessibilityElement()
        .accessibilityLabel(help)
        .accessibilityValue("\(Int((level * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: action(min(level + 0.1, 1))
            case .decrement: action(max(level - 0.1, 0))
            @unknown default: break
            }
        }
    }
}

/// The study playlist presets; tapping the one in use turns it off. A link
/// typed in Settings that isn't a preset shows on top as "Your playlist".
private struct StudyPlaylistList: View {
    @ObservedObject var focus: FocusController

    var body: some View {
        let text = focus.settings.playlistText
        let current = FocusPlaylistPreset.matching(text)
        let hasCustom = current == nil && focus.settings.playlist != nil
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Playlist")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.bottom, Theme.Spacing.xxs)
            if hasCustom {
                StudyPlaylistRow(name: "Your playlist", detail: focus.settings.playlist?.source.displayName ?? "",
                                 isOn: true, help: "The link from Settings › Focus; picking a preset replaces it") {}
            }
            ForEach(FocusPlaylistPreset.all.prefix(hasCustom ? 5 : 6)) { preset in
                let isOn = preset == current
                StudyPlaylistRow(name: preset.name, detail: preset.curator, isOn: isOn,
                                 help: isOn ? "Stop starting \(preset.name) with focus"
                                            : "Start \(preset.name) (\(preset.curator)) with focus") {
                    withMotion(Theme.Motion.snappy) { focus.settings.playlistText = isOn ? "" : preset.link }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StudyPlaylistRow: View {
    let name: String
    let detail: String
    let isOn: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isOn ? studyAccent : Theme.Palette.tertiaryText)
                // The curator only shows when the whole name still fits.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        title.fixedSize()
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(detail)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .fixedSize()
                    }
                    HStack(spacing: 0) {
                        title.lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .font(Theme.Typography.caption)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous)
                    .fill(hovering ? Theme.Palette.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var title: some View {
        Text(name).foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
    }
}

/// A small capsule switch: accent fill when on, quiet surface when off.
struct StudyCapsuleToggle: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            withMotion(Theme.Motion.snappy) { action() }
        } label: {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: isOn ? "\(symbol).fill" : symbol)
                    .font(.system(size: 9, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(Theme.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(isOn ? Theme.Palette.background : Theme.Palette.secondaryText)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(Capsule().fill(isOn ? studyAccent.opacity(hovering ? 1 : 0.88)
                                            : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke.opacity(isOn ? 0 : 1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
