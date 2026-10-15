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
/// live while focusing. The Study tab and the Focus tab both open it, each
/// in its own accent (`tint`).
struct StudySoundMixer: View {
    @ObservedObject var focus: FocusController
    /// The accent of the tab showing the mixer.
    var tint: Color = studyAccent
    let close: () -> Void

    var body: some View {
        // A short panel (Compact) gets slimmer sound tiles, so both cards
        // keep their bottom edges instead of being clipped by the notch.
        ViewThatFits(in: .vertical) {
            content(dense: false)
            content(dense: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.mixerTint, tint)
        .onDisappear { focus.setPreviewing(false) }
    }

    private func content(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            header
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Card(padding: Theme.Spacing.s) {
                    blend(dense: dense).frame(maxHeight: .infinity, alignment: .top)
                }
                Card(padding: Theme.Spacing.s) {
                    StudyPlaylistList(focus: focus, snapshotIssue: StudySnapshotState.current?.playlistIssue)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 176)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mix: FocusMix { focus.settings.mix }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("Focus sound", bundle: .tabbi)
                .foregroundStyle(Theme.Palette.tertiaryText)
            Text(mix.summary)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: Theme.Spacing.s)
            if focus.offersDoNotDisturb {
                StudyCapsuleToggle(title: String(localized: "Do Not Disturb", bundle: .tabbi), symbol: "bell.slash",
                                   isOn: focus.settings.doNotDisturb,
                                   help: focus.settings.doNotDisturb
                                       ? String(localized: "Leave notifications on while studying", bundle: .tabbi)
                                       : String(localized: "Turn on Do Not Disturb during deep focus (runs your Focus shortcuts)", bundle: .tabbi)) {
                    focus.settings.doNotDisturb.toggle()
                }
            }
            IconButton(symbol: focus.isPreviewing ? "stop.fill" : "play.fill", help: previewHelp) {
                focus.setPreviewing(!focus.isPreviewing)
            }
            .disabled(mix.isOff || focus.isFocusing)
            .opacity(mix.isOff || focus.isFocusing ? 0.4 : 1)
            IconButton(symbol: "xmark", help: String(localized: "Back to the timer", bundle: .tabbi), action: close)
        }
        .font(Theme.Typography.caption)
    }

    private var previewHelp: String {
        if focus.isFocusing { return String(localized: "Already playing during focus", bundle: .tabbi) }
        if mix.isOff { return String(localized: "Pick a sound to preview it", bundle: .tabbi) }
        return focus.isPreviewing ? String(localized: "Stop the preview", bundle: .tabbi)
                                  : String(localized: "Listen to \(mix.summary)", bundle: .tabbi)
    }

    /// The sounds in rows of three equal columns.
    private func tiles(showsIcons: Bool, dense: Bool) -> some View {
        let sounds = FocusSound.allCases
        return Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Spacing.xs) {
            ForEach(Array(stride(from: 0, to: sounds.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(sounds[start..<min(start + 3, sounds.count)]) { sound in
                        StudyMixTile(sound: sound, level: mix.level(of: sound),
                                     canAdd: mix.canAddLayer, showsIcon: showsIcons, isDense: dense,
                                     toggle: { withMotion(Theme.Motion.snappy) { _ = focus.settings.mix.toggle(sound) } },
                                     setLevel: { focus.settings.mix.setLevel($0, for: sound) })
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func blend(dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Blend", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer(minLength: 0)
                StudyMixPresetRow(focus: focus)
            }
            .padding(.bottom, Theme.Spacing.xxs)
            // In a narrow panel (Compact) the names would truncate beside
            // their icons ("Brown n..."), so every tile drops its icon.
            ViewThatFits(in: .horizontal) {
                tiles(showsIcons: true, dense: dense)
                tiles(showsIcons: false, dense: dense)
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .frame(width: 14)
                StudyLevelSlider(level: focus.settings.volume, name: String(localized: "Volume", bundle: .tabbi),
                                 help: String(localized: "Volume \(StudyLevelSlider.percent(focus.settings.volume))", bundle: .tabbi)) {
                    focus.settings.volume = $0
                }
                Text(verbatim: StudyLevelSlider.percent(focus.settings.volume))
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
    @Environment(\.mixerTint) private var mixerTint
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
                                       help: String(localized: "Play \(preset.mix.summary). Long-press or right-click to rename or delete", bundle: .tabbi),
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
            IconButton(symbol: "trash", help: String(localized: "Delete this preset", bundle: .tabbi)) {
                renaming = nil
                withMotion(Theme.Motion.snappy) { focus.settings.presets.delete(slot) }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, Theme.Spacing.s)
        .frame(height: 18)
        .background(Capsule().fill(Theme.Palette.surfaceHover))
        .overlay(Capsule().strokeBorder(mixerTint.opacity(0.6), lineWidth: 1))
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
    @Environment(\.mixerTint) private var mixerTint
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
            .background(Capsule().fill(isOn ? mixerTint.opacity(hovering ? 1 : 0.88)
                                            : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
            .overlay(Capsule().strokeBorder(Theme.Palette.stroke.opacity(isOn ? 0 : 1), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: apply)
            .onLongPressGesture(minimumDuration: 0.5, perform: rename)
            .contextMenu {
                Button(String(localized: "Rename", bundle: .tabbi), action: rename)
                Button(String(localized: "Delete", bundle: .tabbi), role: .destructive, action: delete)
            }
            .help(help)
            .onHover { hovering = $0 }
            .motion(Theme.Motion.snappy, value: hovering)
            .motion(Theme.Motion.snappy, value: isOn)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Preset \(name)", bundle: .tabbi))
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, apply)
            .accessibilityAction(named: Text("Rename", bundle: .tabbi), rename)
            .accessibilityAction(named: Text("Delete", bundle: .tabbi), delete)
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
        .help(canSave ? String(localized: "Save this blend as a preset", bundle: .tabbi)
                      : String(localized: "Pick a sound, then save the blend here", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// One sound in the blend: tap to add or remove it; while it's in the mix
/// a level slider sits underneath.
private struct StudyMixTile: View {
    @Environment(\.mixerTint) private var mixerTint
    let sound: FocusSound
    /// The sound's level, or nil when it isn't in the mix.
    let level: Float?
    let canAdd: Bool
    let showsIcon: Bool
    /// Slimmer, for a short panel.
    let isDense: Bool
    let toggle: () -> Void
    let setLevel: (Float) -> Void
    @State private var hovering = false

    var body: some View {
        let isOn = level != nil
        let isEnabled = isOn || canAdd
        VStack(spacing: Theme.Spacing.xs) {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    // A name too long for the tile in the user's language
                    // drops the icon, then shrinks a little, before it is cut.
                    ViewThatFits(in: .horizontal) {
                        if showsIcon {
                            HStack(spacing: Theme.Spacing.xs) {
                                icon
                                Text(sound.displayName).fixedSize()
                            }
                        }
                        Text(sound.displayName).fixedSize()
                        Text(sound.displayName).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .help(help(isOn: isOn, isEnabled: isEnabled))
            StudyLevelSlider(level: level ?? 0, name: String(localized: "\(sound.displayName) level", bundle: .tabbi),
                             help: String(localized: "\(sound.displayName) level \(StudyLevelSlider.percent(level ?? 0))", bundle: .tabbi),
                             action: setLevel)
                .opacity(isOn ? 1 : 0)
                .allowsHitTesting(isOn)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, isDense ? Theme.Spacing.xxs : Theme.Spacing.s - Theme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(isOn ? mixerTint.opacity(hovering ? 0.22 : 0.15)
                           : (hovering && isEnabled ? Theme.Palette.surfaceHover : Theme.Palette.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .strokeBorder(mixerTint.opacity(isOn ? 0.5 : 0), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
    }

    private var icon: some View {
        Image(systemName: sound.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 14)
    }

    private func help(isOn: Bool, isEnabled: Bool) -> String {
        if isOn { return String(localized: "Remove \(sound.displayName) from the blend", bundle: .tabbi) }
        if !isEnabled { return String(localized: "Blend up to \(FocusMix.maxLayers) sounds; remove one first", bundle: .tabbi) }
        return String(localized: "Add \(sound.displayName) to the blend", bundle: .tabbi)
    }
}

/// A level in the mixer (the volume, or one sound's level in the blend):
/// the shared `TrackSlider` in the Timer's accent.
private struct StudyLevelSlider: View {
    @Environment(\.mixerTint) private var mixerTint
    let level: Float
    /// What the slider sets, e.g. "Volume" or "Rain level".
    let name: String
    /// The tooltip, which names the level.
    let help: String
    let action: (Float) -> Void

    var body: some View {
        TrackSlider(value: Double(level), tint: mixerTint, help: help,
                    accessibilityLabel: name, accessibilityValue: StudyLevelSlider.percent(level),
                    onChange: { action(Float($0)) })
            .frame(height: 10)
    }

    static func percent(_ level: Float) -> String {
        Double(level).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// The study playlist presets. Picking one plays it right away and starts
/// it with every focus block; tapping the one in use turns it off (and
/// pauses it if focus mode started it). A link typed in Settings that isn't
/// a preset shows on top as "Your playlist", which plays it again. When a
/// playlist can't start (no Automation access, the app isn't installed),
/// a row on top says why and offers the fix.
private struct StudyPlaylistList: View {
    @ObservedObject var focus: FocusController
    /// An issue to show in a snapshot run, where focus mode never scripts an app.
    var snapshotIssue: FocusPlaylistIssue?

    /// Rows that fit under the header in the mixer's playlist column.
    static let rowCount = 6

    var body: some View {
        let text = focus.settings.playlistText
        let current = FocusPlaylistPreset.matching(text)
        let hasCustom = current == nil && focus.settings.playlist != nil
        let issue = focus.playlistIssue ?? snapshotIssue
        let presetCount = Self.rowCount - (hasCustom ? 1 : 0) - (issue == nil ? 0 : 1)
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Playlist", bundle: .tabbi)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(.bottom, Theme.Spacing.xxs)
            if let issue {
                StudyPlaylistIssueRow(issue: issue) { fix(issue) }
                    .transition(.opacity)
            }
            if hasCustom {
                StudyPlaylistRow(name: String(localized: "Your playlist", bundle: .tabbi),
                                 detail: focus.settings.playlist?.source.displayName ?? "",
                                 isOn: true,
                                 help: String(localized: "Play your playlist now. It's the link from the Focus options in Settings > Tabs; picking a preset replaces it", bundle: .tabbi)) {
                    focus.choosePlaylist(text)
                }
            }
            ForEach(FocusPlaylistPreset.all.prefix(presetCount)) { preset in
                let isOn = preset == current
                StudyPlaylistRow(name: preset.name, detail: preset.curator, isOn: isOn,
                                 help: isOn ? String(localized: "Turn off \(preset.name): stop it and don't start it with focus", bundle: .tabbi)
                                            : String(localized: "Play \(preset.name) (\(preset.curator)) now and with every focus block", bundle: .tabbi)) {
                    withMotion(Theme.Motion.snappy) { focus.choosePlaylist(isOn ? "" : preset.link) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(Theme.Motion.snappy, value: issue)
    }

    private func fix(_ issue: FocusPlaylistIssue) {
        switch issue {
        case .permissionDenied:
            NSWorkspace.shared.open(SystemSettingsLink.automationPrivacy.url)
        case .notInstalled:
            withMotion(Theme.Motion.snappy) { focus.dismissPlaylistIssue() }
        case .failed:
            focus.choosePlaylist(focus.settings.playlistText)
        }
    }
}

/// Why the playlist didn't start, as a row in the playlist column: a click
/// opens the fix (Automation settings), retries, or dismisses it.
private struct StudyPlaylistIssueRow: View {
    let issue: FocusPlaylistIssue
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Palette.warning)
                    .frame(width: 10)
                // Wraps rather than cutting the fix it names.
                Text(title)
                    .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.caption)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Spacing.xs, style: .continuous)
                    .fill(Theme.Palette.warning.opacity(hovering ? 0.22 : 0.12))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private var symbol: String {
        switch issue {
        case .permissionDenied: "lock.fill"
        case .notInstalled: "arrow.down.app"
        case .failed: "arrow.clockwise"
        }
    }

    private var title: String {
        switch issue {
        case .permissionDenied(let source):
            String(localized: "Allow \(source.displayName) access", bundle: .tabbi)
        case .notInstalled(let source):
            String(localized: "\(source.displayName) isn't installed", bundle: .tabbi)
        case .failed:
            String(localized: "Couldn't start the playlist", bundle: .tabbi)
        }
    }

    private var help: String {
        switch issue {
        case .permissionDenied(let source):
            String(localized: "\(Edition.current.name) needs permission to control \(source.displayName) to start your playlist. Click to open Privacy & Security › Automation", bundle: .tabbi)
        case .notInstalled(let source):
            String(localized: "Install \(source.displayName) to play this playlist, or pick another one. Click to dismiss", bundle: .tabbi)
        case .failed(let source, _):
            String(localized: "\(source.displayName) didn't respond. Click to try again", bundle: .tabbi)
        }
    }
}

private struct StudyPlaylistRow: View {
    @Environment(\.mixerTint) private var mixerTint
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
                    .foregroundStyle(isOn ? mixerTint : Theme.Palette.tertiaryText)
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
    @Environment(\.mixerTint) private var mixerTint
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
            .background(Capsule().fill(isOn ? mixerTint.opacity(hovering ? 1 : 0.88)
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

extension EnvironmentValues {
    /// The accent the sound mixer and the capsule switches draw in: Study's,
    /// unless the tab showing them sets its own.
    @Entry var mixerTint: Color = studyAccent
}
