import SwiftUI
import TabbiKitCore
import TabbiKit

/// The one focus-sound button beside the deep focus switch: it names what
/// plays (a sound, a blend, a playlist) and opens the in-notch mixer, so the
/// Timer panel keeps a single control for sound. It reads the shared focus
/// settings, which the Focus timer plays too.
struct StudySoundButton: View {
    @ObservedObject var focus: FocusController
    /// Whether study blocks play the sound; the button dims while it's off.
    let isActive: Bool
    let openMixer: () -> Void
    @State private var hovering = false

    var body: some View {
        let settings = focus.settings
        let label = StudySoundLabel(settings)
        Button(action: openMixer) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: label.symbolName)
                    .font(.system(size: 9, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(label.title)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if label.addsPlaylist {
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(foreground(isOn: label.isOn))
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 20)
            .background(Capsule().fill(label.isOn ? studyAccent.opacity(hovering ? 0.30 : 0.20)
                                                  : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke.opacity(label.isOn ? 0 : 1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(StudySoundLabel.help(for: settings,
                                   playlistName: FocusPlaylistPreset.matching(settings.playlistText)?.name))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: label)
    }

    private func foreground(isOn: Bool) -> Color {
        if isOn { return studyAccent.opacity(isActive || hovering ? 1 : 0.7) }
        return hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText
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
            if focus.offersDoNotDisturb {
                StudyCapsuleToggle(title: "Do Not Disturb", symbol: "bell.slash",
                                   isOn: focus.settings.doNotDisturb,
                                   help: focus.settings.doNotDisturb
                                       ? "Leave notifications on while studying"
                                       : "Turn on Do Not Disturb during deep focus (runs your Focus shortcuts)") {
                    focus.settings.doNotDisturb.toggle()
                }
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

    /// The sounds in rows of three equal columns.
    private func tiles(showsIcons: Bool) -> some View {
        let sounds = FocusSound.allCases
        return Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
            ForEach(Array(stride(from: 0, to: sounds.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(sounds[start..<min(start + 3, sounds.count)]) { sound in
                        StudyMixTile(sound: sound, level: mix.level(of: sound),
                                     canAdd: mix.canAddLayer, showsIcon: showsIcons,
                                     toggle: { withMotion(Theme.Motion.snappy) { _ = focus.settings.mix.toggle(sound) } },
                                     setLevel: { focus.settings.mix.setLevel($0, for: sound) })
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var blend: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Blend")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer(minLength: 0)
                StudyMixPresetRow(focus: focus)
            }
            .padding(.bottom, Theme.Spacing.xxs)
            // In a narrow panel (Compact) the names would truncate beside
            // their icons ("Brown n..."), so every tile drops its icon.
            ViewThatFits(in: .horizontal) {
                tiles(showsIcons: true)
                tiles(showsIcons: false)
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

/// The saved blends: three tiny chips beside "Blend". An empty slot (+)
/// saves the current blend with one tap; a preset applies with a tap, and a
/// long press or right-click renames or deletes it. The chip of the preset
/// playing now is lit.
private struct StudyMixPresetRow: View {
    @ObservedObject var focus: FocusController
    @State private var renaming: Int?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let presets = focus.settings.presets
        let active = presets.slot(matching: focus.settings.mix)
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(presets.slots.indices, id: \.self) { slot in
                if renaming == slot {
                    renameField(slot)
                } else if let preset = presets.slots[slot] {
                    StudyMixPresetChip(name: preset.name, isOn: slot == active,
                                       help: "Play \(preset.mix.summary). Long-press or right-click to rename or delete",
                                       apply: { withMotion(Theme.Motion.snappy) { focus.settings.apply(preset: slot) } },
                                       rename: { beginRename(slot, name: preset.name) },
                                       delete: { withMotion(Theme.Motion.snappy) { focus.settings.presets.delete(slot) } })
                } else {
                    StudyMixPresetSaveButton(canSave: !focus.settings.mix.isOff) {
                        withMotion(Theme.Motion.snappy) { _ = focus.settings.presets.save(focus.settings.mix, into: slot) }
                    }
                }
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            if !focused { commitRename() }
        }
    }

    private func renameField(_ slot: Int) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.primaryText)
                .focused($fieldFocused)
                .frame(width: 64)
                .onAppear { fieldFocused = true }
                .onSubmit { fieldFocused = false }
                // Esc keeps the old name.
                .onExitCommand { renaming = nil }
                .onChange(of: draft) { _, text in
                    if text.count > FocusMixPreset.maxNameLength { draft = String(text.prefix(FocusMixPreset.maxNameLength)) }
                }
            IconButton(symbol: "trash", help: "Delete this preset") {
                renaming = nil
                withMotion(Theme.Motion.snappy) { focus.settings.presets.delete(slot) }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, Theme.Spacing.s)
        .frame(height: 18)
        .background(Capsule().fill(Theme.Palette.surfaceHover))
        .overlay(Capsule().strokeBorder(studyAccent.opacity(0.6), lineWidth: 1))
    }

    private func beginRename(_ slot: Int, name: String) {
        draft = name
        renaming = slot
    }

    private func commitRename() {
        guard let slot = renaming else { return }
        renaming = nil
        focus.settings.presets.rename(slot, to: draft)
    }
}

/// A saved blend: its name in a capsule, lit while it is the blend playing.
private struct StudyMixPresetChip: View {
    let name: String
    let isOn: Bool
    let help: String
    let apply: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(name)
            .font(Theme.Typography.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            // Hugs the name, cut short past 64 pt so three chips always fit.
            .frame(maxWidth: 64)
            .fixedSize()
            .foregroundStyle(isOn ? Theme.Palette.background
                                  : (hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText))
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 18)
            .background(Capsule().fill(isOn ? studyAccent.opacity(hovering ? 1 : 0.88)
                                            : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke.opacity(isOn ? 0 : 1), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: apply)
            .onLongPressGesture(minimumDuration: 0.5, perform: rename)
            .contextMenu {
                Button("Rename", action: rename)
                Button("Delete", role: .destructive, action: delete)
            }
            .help(help)
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
            .motion(Theme.Motion.snappy, value: isOn)
            .accessibilityElement()
            .accessibilityLabel("Preset \(name)")
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, apply)
            .accessibilityAction(named: "Rename", rename)
            .accessibilityAction(named: "Delete", delete)
    }
}

/// An empty preset slot: a dashed + that saves the current blend there.
private struct StudyMixPresetSaveButton: View {
    let canSave: Bool
    let save: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: save) {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering && canSave ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .frame(width: 24, height: 18)
                .background(Capsule().fill(hovering && canSave ? Theme.Palette.surfaceHover : .clear))
                .overlay(Capsule().strokeBorder(Theme.Palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
        .help(canSave ? "Save this blend as a preset" : "Pick a sound, then save the blend here")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One sound in the blend: tap to add or remove it; while it's in the mix
/// a level slider sits underneath.
private struct StudyMixTile: View {
    let sound: FocusSound
    /// The sound's level, or nil when it isn't in the mix.
    let level: Float?
    let canAdd: Bool
    let showsIcon: Bool
    let toggle: () -> Void
    let setLevel: (Float) -> Void
    @State private var hovering = false

    var body: some View {
        let isOn = level != nil
        let isEnabled = isOn || canAdd
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: toggle) {
                HStack(spacing: Theme.Spacing.xs) {
                    if showsIcon {
                        Image(systemName: sound.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                    }
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
                    action(StudySoundLabel.level(atX: value.location.x, width: width))
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
                                 isOn: true, help: "The link from the Focus options in Settings > Tabs; picking a preset replaces it") {}
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
