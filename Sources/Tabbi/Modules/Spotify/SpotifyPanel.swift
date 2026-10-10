import SwiftUI
import TabbiKitCore
import TabbiKit

/// Now Playing: album art on the left; title, scrubber, and transport on the
/// right. Every non-playing `SpotifyStatus` gets its own designed state.
struct SpotifyPanel: View {
    @ObservedObject var controller: SpotifyController

    var body: some View {
        ZStack {
            switch controller.status {
            case .connected(let playback):
                if playback.track != nil {
                    SpotifyNowPlaying(controller: controller, playback: playback)
                } else {
                    SpotifyEmptyState(
                        symbol: "music.note.list", title: "Nothing playing",
                        message: "Start something in \(sourceName) and it shows up here.",
                        actions: [.init(title: "Show \(sourceName)", help: "Bring \(sourceName) to the front",
                                        icon: controller.appIcon(for: activeSource),
                                        perform: { controller.open(activeSource) })]
                    )
                }
            case .notRunning:
                SpotifyEmptyState(
                    symbol: "music.note", title: "No music app is open",
                    message: "Open \(MediaSource.names(controller.installedSources)) to see and control what's playing.",
                    actions: controller.installedSources.map { source in
                        .init(title: "Open \(source.displayName)", help: "Launch \(source.displayName)",
                              icon: controller.appIcon(for: .app(source)),
                              perform: { controller.open(.app(source)) })
                    }
                )
            case .notInstalled:
                SpotifyEmptyState(
                    symbol: "arrow.down.app", title: "No music app found",
                    message: "Install Spotify or Music to control playback from the notch.",
                    actions: []
                )
            case .connecting:
                SpotifyEmptyState(symbol: nil, title: "Connecting to \(sourceName)…",
                                  message: "Reading what's playing.", actions: [])
            case .permissionDenied:
                SpotifyEmptyState(
                    symbol: "lock.fill", title: "\(Edition.current.name) can't control \(sourceName)",
                    message: "Allow access in Privacy & Security › Automation.",
                    actions: [.init(title: "Open Settings", help: "Open Automation settings",
                                    perform: controller.openAutomationSettings)]
                )
            case .scriptingDisabled:
                SpotifyEmptyState(
                    symbol: "curlybraces", title: "Turn on JavaScript for SoundCloud",
                    message: "In \(browser.displayName), choose \(browser.javaScriptSettingPath).",
                    actions: [.init(title: "Show \(browser.displayName)",
                                    help: "Bring \(browser.displayName) to the front",
                                    icon: controller.appIcon(for: activeSource),
                                    perform: { controller.open(activeSource) })]
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(Theme.Motion.content, value: controller.status.kind)
        .onAppear { controller.setPanelVisible(true) }
        .onDisappear { controller.setPanelVisible(false) }
    }

    private var activeSource: NowPlayingSource { controller.source ?? .spotify }
    private var sourceName: String { activeSource.displayName }
    /// The browser SoundCloud plays in; Safari when the panel follows an app.
    private var browser: SoundCloudBrowser {
        if case .soundCloud(let browser) = activeSource { return browser }
        return .safari
    }
}

private extension SpotifyStatus {
    /// Which view the panel shows; animates swaps between them without
    /// animating every position tick.
    var kind: Int {
        switch self {
        case .notInstalled: 0
        case .notRunning: 1
        case .connecting: 2
        case .permissionDenied: 3
        case .connected(let playback): playback.track == nil ? 4 : 5
        case .scriptingDisabled: 6
        }
    }
}

// MARK: - Now playing

private struct SpotifyNowPlaying: View {
    @ObservedObject var controller: SpotifyController
    let playback: SpotifyPlayback
    @StateObject private var artwork = SpotifyArtworkLoader()
    @State private var hoveringTitle = false

    private static let artworkSize: CGFloat = 112

    var body: some View {
        let track = playback.track
        HStack(spacing: Theme.Spacing.l) {
            SpotifyArtworkButton(controller: controller, track: track, artwork: artwork,
                                 size: Self.artworkSize)
                .background { glow }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: Theme.Spacing.s) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        SpotifyMarqueeText(text: track?.title.isEmpty == false ? track!.title : "Unknown track",
                                           isActive: hoveringTitle)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.primaryText)
                        SpotifyMarqueeText(text: subtitle, isActive: hoveringTitle)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .onHover { hoveringTitle = $0 }
                    .help(helpText)

                    if let isFavorite = track?.isFavorite {
                        SpotifyLikeButton(isLiked: isFavorite, source: controller.source ?? .spotify,
                                          action: controller.toggleFavorite)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                SpotifyScrubberBar(playback: playback, onSeek: controller.seek(to:))

                Spacer(minLength: Theme.Spacing.s)

                SpotifyTransport(controller: controller, playback: playback)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.artworkSize)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .task(id: track?.id) { await artwork.load(track, from: controller) }
    }

    /// Artist and album. SoundCloud tracks have no album, and the badge on
    /// the cover is the browser's, so they name SoundCloud there instead.
    private var subtitle: String {
        let album = controller.source?.app == nil ? controller.source?.displayName : playback.track?.album
        return [playback.track?.artist, album]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var helpText: String {
        [playback.track?.title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A soft halo tinted by the cover, so the panel picks up the album's mood.
    private var glow: some View {
        let tint = artwork.artwork?.averageColor
            ?? playback.track.flatMap { artwork.isLoading
                ? nil : SpotifyGeneratedCoverView.glowColor(for: SpotifyGeneratedCover(seed: $0.id)) }
        // A radial fade (not a blur) reaches zero before the panel's clip
        // edge, so the halo never shows a hard cut-off.
        return RadialGradient(colors: [(tint ?? .clear).opacity(0.5), .clear],
                              center: .center, startRadius: Self.artworkSize * 0.25,
                              endRadius: Self.artworkSize * 0.6)
            .frame(width: Self.artworkSize * 1.2, height: Self.artworkSize * 1.2)
            .allowsHitTesting(false)
            .motion(Theme.Motion.content, value: tint)
    }
}

// MARK: - Marquee

/// One line of text that truncates at rest and, while `isActive` (hovered),
/// scrolls as a gentle loop if it doesn't fit. Text that fits never moves,
/// and under Reduce Motion nothing scrolls: the line stays truncated.
/// Font and color come from the environment like a plain `Text`.
private struct SpotifyMarqueeText: View {
    let text: String
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var startDate = Date()

    private static let edgeFade: CGFloat = 12

    private var scrolls: Bool {
        isActive && !reduceMotion && SpotifyMarquee.needsScrolling(textWidth: textWidth, containerWidth: containerWidth)
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { containerWidth = $0 }
            .background(alignment: .leading) {
                // Measures the untruncated width without affecting layout.
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls { scrollingText }
            }
            .onChange(of: scrolls) { _, scrolls in
                if scrolls { startDate = .now }
            }
    }

    private var scrollingText: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let offset = SpotifyMarquee.offset(elapsed: context.date.timeIntervalSince(startDate),
                                               textWidth: textWidth, containerWidth: containerWidth)
            // The leading fade grows in as the text moves, so the first
            // letter is crisp while the line rests.
            let leadingFade = min(-offset, Self.edgeFade) / max(containerWidth, 1)
            let trailingFade = Self.edgeFade / max(containerWidth, 1)
            HStack(spacing: SpotifyMarquee.gap) {
                Text(text)
                Text(text)
            }
            .lineLimit(1)
            .fixedSize()
            .offset(x: offset)
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: leadingFade),
                    .init(color: .black, location: 1 - trailingFade),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Artwork button

/// The cover with a small badge of the app it plays in. Clicking it brings
/// that app forward; hovering lifts the cover and hints at the action.
private struct SpotifyArtworkButton: View {
    @ObservedObject var controller: SpotifyController
    let track: SpotifyTrack?
    @ObservedObject var artwork: SpotifyArtworkLoader
    let size: CGFloat
    @State private var hovering = false

    private static let badgeSize: CGFloat = 24

    var body: some View {
        let source = controller.source ?? .spotify
        Button { controller.open(source) } label: {
            SpotifyArtworkView(track: track, artwork: artwork.artwork, isLoading: artwork.isLoading,
                               size: size, cornerRadius: Theme.Radius.l)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                        .fill(.black.opacity(hovering ? 0.35 : 0))
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primaryText)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .opacity(hovering ? 1 : 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    badge(for: source)
                        .padding(Theme.Spacing.xs + Theme.Spacing.xxs)
                }
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(.tactile(.pill, lifts: true))
        .help("Show \(source.displayName)")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    /// The player's own icon; a glyph on a dark disc if the icon is missing.
    @ViewBuilder private func badge(for source: NowPlayingSource) -> some View {
        Group {
            if let icon = controller.appIcon(for: source) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: Self.badgeSize * 0.45, weight: .semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .frame(width: Self.badgeSize, height: Self.badgeSize)
                    .background(Circle().fill(.black.opacity(0.6)))
            }
        }
        .frame(width: Self.badgeSize, height: Self.badgeSize)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .accessibilityLabel("Playing in \(source.displayName)")
    }
}

// MARK: - Scrubber

private struct SpotifyScrubberBar: View {
    let playback: SpotifyPlayback
    let onSeek: (TimeInterval) -> Void

    /// Position under the pointer while dragging; nil otherwise.
    @State private var dragPosition: TimeInterval?
    @State private var hovering = false

    private var duration: TimeInterval { playback.track?.duration ?? 0 }
    private var shownPosition: TimeInterval { dragPosition ?? playback.position }
    private var isActive: Bool { hovering || dragPosition != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = duration > 0 ? min(max(shownPosition / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.surfaceHover)
                    Capsule()
                        .fill(isActive ? NowPlayingModule.descriptor.accentColor : Theme.Palette.primaryText)
                        .frame(width: max(width * fraction, isActive ? 0 : 4))
                    Circle()
                        .fill(Theme.Palette.primaryText)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: width * fraction - 5)
                        .opacity(isActive ? 1 : 0)
                }
                .frame(height: isActive ? 6 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragPosition = SpotifyScrubber.position(
                                atX: value.location.x, width: width, duration: duration)
                        }
                        .onEnded { value in
                            onSeek(SpotifyScrubber.position(
                                atX: value.location.x, width: width, duration: duration))
                            dragPosition = nil
                        }
                )
            }
            .frame(height: 12)
            .onHover { hovering = $0 }
            .help("Drag to seek")
            .disabled(duration <= 0)
            .motion(Theme.Motion.snappy, value: isActive)

            HStack {
                Text(PlaybackTimeFormatter.string(shownPosition))
                Spacer()
                Text(PlaybackTimeFormatter.remaining(position: shownPosition, duration: duration))
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.tertiaryText)
        }
    }
}

// MARK: - Transport

private struct SpotifyTransport: View {
    @ObservedObject var controller: SpotifyController
    let playback: SpotifyPlayback

    var body: some View {
        // The buttons stay centered in the column; modes sit on the left and
        // the volume control on the right, so the slider can grow on hover
        // without shifting anything.
        ZStack {
            HStack(spacing: Theme.Spacing.xs) {
                SpotifyModeButton(symbol: "shuffle", isOn: playback.isShuffling,
                                  label: "Shuffle", value: playback.isShuffling ? "On" : "Off",
                                  help: playback.isShuffling ? "Turn shuffle off" : "Turn shuffle on",
                                  action: controller.toggleShuffle)
                SpotifyModeButton(symbol: playback.repeatMode == .one ? "repeat.1" : "repeat",
                                  isOn: playback.isRepeating,
                                  label: "Repeat", value: Self.repeatValue(playback.repeatMode),
                                  help: repeatHelp, action: controller.cycleRepeat)
                Spacer(minLength: 0)
                if let volume = playback.volume {
                    SpotifyVolumeControl(volume: volume, onChange: controller.setVolume,
                                         onToggleMute: controller.toggleMute)
                }
            }
            HStack(spacing: Theme.Spacing.m) {
                SpotifyTransportButton(symbol: "backward.fill", help: "Previous track",
                                       action: controller.previous)
                SpotifyPlayPauseButton(isPlaying: playback.isPlaying, action: controller.playPause)
                SpotifyTransportButton(symbol: "forward.fill", help: "Next track",
                                       action: controller.next)
            }
        }
    }

    /// What the next click does, since repeat steps through several modes.
    private var repeatHelp: String {
        let source = controller.source ?? .spotify
        switch source.repeatMode(after: playback.repeatMode) {
        case .off: return "Turn repeat off"
        case .all: return source == .music ? "Repeat all songs" : "Turn repeat on"
        case .one: return "Repeat this song"
        }
    }

    private static func repeatValue(_ mode: MediaRepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .all: "All"
        case .one: "One song"
        }
    }
}

/// A speaker button that mutes and unmutes; hovering it slides out a
/// volume slider to its left.
private struct SpotifyVolumeControl: View {
    let volume: Int
    let onChange: (Int) -> Void
    let onToggleMute: () -> Void

    /// Volume under the pointer while dragging; nil otherwise.
    @State private var dragVolume: Int?
    @State private var hovering = false
    @State private var hoveringSpeaker = false

    private static let sliderWidth: CGFloat = 56
    private static let height: CGFloat = 24

    private var shownVolume: Int { dragVolume ?? volume }
    /// Stays open mid-drag even if the pointer leaves the control.
    private var isExpanded: Bool { hovering || dragVolume != nil }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if isExpanded {
                slider
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
            }
            speaker
        }
        .padding(.leading, isExpanded ? Theme.Spacing.s : 0)
        .background(Capsule().fill(isExpanded ? Theme.Palette.surface : .clear))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: isExpanded)
    }

    private var speaker: some View {
        Button(action: onToggleMute) {
            Image(systemName: Self.symbol(for: shownVolume))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hoveringSpeaker ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.height, height: Self.height)
                .background(Circle().fill(hoveringSpeaker ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.tactile)
        .help(shownVolume == 0 ? "Unmute" : "Mute")
        .onHover { hoveringSpeaker = $0 }
        .motion(Theme.Motion.snappy, value: hoveringSpeaker)
        .accessibilityLabel(shownVolume == 0 ? "Unmute" : "Mute")
    }

    private var slider: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(shownVolume) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.surfaceHover)
                Capsule()
                    .fill(NowPlayingModule.descriptor.accentColor)
                    .frame(width: width * fraction)
                Circle()
                    .fill(Theme.Palette.primaryText)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: width * fraction - 5)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let volume = MediaVolume.volume(atX: value.location.x, width: width)
                        dragVolume = volume
                        onChange(volume)
                    }
                    .onEnded { value in
                        onChange(MediaVolume.volume(atX: value.location.x, width: width))
                        dragVolume = nil
                    }
            )
        }
        .frame(width: Self.sliderWidth, height: Self.height)
        .help("Volume \(shownVolume)%")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(shownVolume)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(volume + 10)
            case .decrement: onChange(volume - 10)
            @unknown default: break
            }
        }
    }

    private static func symbol(for volume: Int) -> String {
        switch MediaVolume.level(volume) {
        case 0: "speaker.slash.fill"
        case 1: "speaker.wave.1.fill"
        case 2: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct SpotifyTransportButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.tactile)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

private struct SpotifyPlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Palette.background)
                .contentTransition(.symbolEffect(.replace))
                // play.fill looks off-center without a nudge.
                .offset(x: isPlaying ? 0 : 1)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.Palette.primaryText))
                .contentShape(Circle())
        }
        .buttonStyle(.tactile(.control, lifts: true))
        .help(isPlaying ? "Pause" : "Play")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isPlaying)
    }
}

/// The heart beside the title: likes the current track (Music calls it
/// Favorite, SoundCloud Like). Only shown when the player reports whether the track is liked,
/// so it never appears where a click couldn't work.
private struct SpotifyLikeButton: View {
    let isLiked: Bool
    let source: NowPlayingSource
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.tactile)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isLiked)
        .accessibilityLabel(source == .music ? "Favorite" : "Like")
        .accessibilityValue(isLiked ? "On" : "Off")
        .accessibilityHint(help)
    }

    private var help: String {
        switch (source, isLiked) {
        case (.music, true): "Remove from Favorites"
        case (.music, false): "Add to Favorites"
        case (_, true): "Unlike"
        case (_, false): "Like"
        }
    }

    private var foreground: Color {
        if isLiked { return Theme.Palette.favorite }
        return hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText
    }
}

/// A shuffle or repeat toggle. On shows the module accent with a dot
/// underneath; the player's own state decides it, read back after each click.
private struct SpotifyModeButton: View {
    let symbol: String
    let isOn: Bool
    let label: String
    let value: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Theme.Palette.surfaceHover : .clear))
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(NowPlayingModule.descriptor.accentColor)
                        .frame(width: 3, height: 3)
                        .offset(y: 1)
                        .opacity(isOn ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.tactile)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityHint(help)
    }

    private var foreground: Color {
        if isOn { return NowPlayingModule.descriptor.accentColor }
        return hovering ? Theme.Palette.primaryText : Theme.Palette.tertiaryText
    }
}

// MARK: - Empty states

private struct SpotifyEmptyState: View {
    struct Action {
        let title: String
        let help: String
        /// The app's own icon, shown on buttons that open or show an app.
        var icon: NSImage? = nil
        let perform: () -> Void
    }

    /// Nil shows a spinner instead of a glyph.
    let symbol: String?
    let title: String
    let message: String
    let actions: [Action]

    var body: some View {
        StatusMessage(symbol: symbol, tint: NowPlayingModule.descriptor.accentColor,
                      title: title, message: message) {
            if !actions.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(actions.indices, id: \.self) { index in
                        SpotifyActionButton(action: actions[index])
                    }
                }
            }
        }
    }
}

private struct SpotifyActionButton: View {
    let action: SpotifyEmptyState.Action
    @State private var hovering = false

    var body: some View {
        Button(action: action.perform) {
            HStack(spacing: Theme.Spacing.xs + Theme.Spacing.xxs) {
                if let icon = action.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                }
                Text(action.title)
                    .font(Theme.Typography.bodyEmphasis)
            }
            .foregroundStyle(isAppLauncher ? Theme.Palette.primaryText : Theme.Palette.background)
            .padding(.leading, isAppLauncher ? Theme.Spacing.xs + Theme.Spacing.xxs : Theme.Spacing.m)
            .padding(.trailing, Theme.Spacing.m)
            .frame(height: 28)
            .background(Capsule().fill(fill))
            .overlay {
                if isAppLauncher { Capsule().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill, lifts: true))
        .help(action.help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }

    /// App launch buttons sit on a neutral surface so each app's own icon
    /// carries the color; other actions use the module accent.
    private var isAppLauncher: Bool { action.icon != nil }

    private var fill: Color {
        isAppLauncher
            ? (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)
            : NowPlayingModule.descriptor.accentColor.opacity(hovering ? 1 : 0.9)
    }
}

// MARK: - Compact live activity

/// Left wing of the closed notch: the current cover at 20pt, centered.
struct SpotifyCompactLeading: View {
    @ObservedObject var controller: SpotifyController
    @StateObject private var artwork = SpotifyArtworkLoader()

    var body: some View {
        let track = controller.status.playback?.track
        SpotifyArtworkView(track: track, artwork: artwork.artwork, isLoading: artwork.isLoading,
                           size: 20, cornerRadius: 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: track?.id) { await artwork.load(track, from: controller) }
            .help(track.map { "\($0.title) · \($0.artist)" } ?? (controller.source ?? .spotify).displayName)
    }
}

/// Right wing of the closed notch: four equalizer bars in the module accent.
/// On screen the bars are layers that Core Animation moves by itself
/// (`SpotifyEqualizerView`), so a playing track costs the app nothing per
/// frame. Drawn into an image (`rendersToImage`), they are plain SwiftUI.
struct SpotifyCompactTrailing: View {
    @ObservedObject var controller: SpotifyController
    @Environment(\.rendersToImage) private var rendersToImage

    var body: some View {
        let isPlaying = controller.status.isPlaying
        Group {
            if rendersToImage {
                let levels = isPlaying
                    ? SpotifyEqualizer.levels(at: Date().timeIntervalSinceReferenceDate)
                    : SpotifyEqualizer.restingLevels()
                HStack(alignment: .bottom, spacing: SpotifyEqualizerView.spacing) {
                    ForEach(levels.indices, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(NowPlayingModule.descriptor.accentColor)
                            .frame(width: SpotifyEqualizerView.barWidth,
                                   height: SpotifyEqualizerView.maxHeight * levels[index])
                    }
                }
                .frame(height: SpotifyEqualizerView.maxHeight, alignment: .bottom)
            } else {
                SpotifyEqualizerBars(isPlaying: isPlaying, tint: NowPlayingModule.descriptor.accentColor)
                    .frame(width: SpotifyEqualizerView.width, height: SpotifyEqualizerView.maxHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(isPlaying ? "Playing in \((controller.source ?? .spotify).displayName)" : "Paused")
    }
}
