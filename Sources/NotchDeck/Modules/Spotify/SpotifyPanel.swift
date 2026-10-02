import SwiftUI
import NotchDeckCore

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
                        action: .init(title: "Show \(sourceName)", help: "Bring \(sourceName) to the front",
                                      perform: { controller.open(controller.source ?? .spotify) })
                    )
                }
            case .notRunning:
                SpotifyEmptyState(
                    symbol: "music.note", title: "Spotify isn't running",
                    message: "Open Spotify to see and control what's playing.",
                    action: .init(title: "Open Spotify", help: "Launch Spotify",
                                  perform: { controller.open(.spotify) })
                )
            case .notInstalled:
                SpotifyEmptyState(
                    symbol: "arrow.down.app", title: "Spotify isn't installed",
                    message: "Install the Spotify app to control music from the notch.",
                    action: nil
                )
            case .connecting:
                SpotifyEmptyState(symbol: nil, title: "Connecting to \(sourceName)…",
                                  message: "Reading what's playing.", action: nil)
            case .permissionDenied:
                SpotifyEmptyState(
                    symbol: "lock.fill", title: "NotchDeck can't control \(sourceName)",
                    message: "Allow access in Privacy & Security › Automation.",
                    action: .init(title: "Open Settings", help: "Open Automation settings",
                                  perform: controller.openAutomationSettings)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.Motion.content, value: controller.status.kind)
        .onAppear { controller.setPanelVisible(true) }
        .onDisappear { controller.setPanelVisible(false) }
    }

    private var sourceName: String { (controller.source ?? .spotify).displayName }
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
        }
    }
}

// MARK: - Now playing

private struct SpotifyNowPlaying: View {
    @ObservedObject var controller: SpotifyController
    let playback: SpotifyPlayback
    @StateObject private var artwork = SpotifyArtworkLoader()

    private static let artworkSize: CGFloat = 112

    var body: some View {
        let track = playback.track
        HStack(spacing: Theme.Spacing.l) {
            SpotifyArtworkView(track: track, artwork: artwork.artwork, isLoading: artwork.isLoading,
                               size: Self.artworkSize, cornerRadius: Theme.Radius.l)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                .background { glow }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(track?.title.isEmpty == false ? track!.title : "Unknown track")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .help(helpText)

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

    private var subtitle: String {
        [playback.track?.artist, playback.track?.album]
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
            .animation(Theme.Motion.content, value: tint)
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
                        .fill(isActive ? Theme.Palette.accent(for: .spotify) : Theme.Palette.primaryText)
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
            .animation(Theme.Motion.snappy, value: isActive)

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
        HStack(spacing: 0) {
            SpotifyModeIndicator(symbol: "shuffle", isOn: playback.isShuffling,
                                 help: playback.isShuffling ? "Shuffle is on" : "Shuffle is off")
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.m) {
                SpotifyTransportButton(symbol: "backward.fill", help: "Previous track",
                                       action: controller.previous)
                SpotifyPlayPauseButton(isPlaying: playback.isPlaying, action: controller.playPause)
                SpotifyTransportButton(symbol: "forward.fill", help: "Next track",
                                       action: controller.next)
            }
            Spacer(minLength: 0)
            SpotifyModeIndicator(symbol: "repeat", isOn: playback.isRepeating,
                                 help: playback.isRepeating ? "Repeat is on" : "Repeat is off")
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
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
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
                .scaleEffect(hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Pause" : "Play")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isPlaying)
    }
}

/// Read-only shuffle / repeat state (Spotify owns those settings).
private struct SpotifyModeIndicator: View {
    let symbol: String
    let isOn: Bool
    let help: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isOn ? Theme.Palette.accent(for: .spotify) : Theme.Palette.tertiaryText)
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottom) {
                Circle()
                    .fill(Theme.Palette.accent(for: .spotify))
                    .frame(width: 3, height: 3)
                    .opacity(isOn ? 1 : 0)
            }
            .contentShape(Rectangle())
            .help(help)
    }
}

// MARK: - Empty states

private struct SpotifyEmptyState: View {
    struct Action {
        let title: String
        let help: String
        let perform: () -> Void
    }

    /// Nil shows a spinner instead of a glyph.
    let symbol: String?
    let title: String
    let message: String
    let action: Action?

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            ZStack {
                Circle().fill(Theme.Palette.accent(for: .spotify).opacity(0.14))
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent(for: .spotify))
                } else {
                    SpotifySpinner()
                }
            }
            .frame(width: 40, height: 40)

            VStack(spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .lineLimit(2)

            if let action {
                SpotifyActionButton(action: action)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: 360)
    }
}

/// An accent arc that turns once a second. Drawn in SwiftUI rather than
/// `ProgressView`, whose AppKit-backed spinner doesn't render in snapshots
/// and ignores the module accent.
private struct SpotifySpinner: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let turns = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Theme.Palette.accent(for: .spotify),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(turns * 360))
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel("Loading")
    }
}

private struct SpotifyActionButton: View {
    let action: SpotifyEmptyState.Action
    @State private var hovering = false

    var body: some View {
        Button(action: action.perform) {
            Text(action.title)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.background)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 24)
                .background(Capsule().fill(Theme.Palette.accent(for: .spotify)
                    .opacity(hovering ? 1 : 0.9)))
                .scaleEffect(hovering ? 1.03 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(action.help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
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
/// The timeline pauses with playback, so a paused track costs no redraws.
struct SpotifyCompactTrailing: View {
    @ObservedObject var controller: SpotifyController

    private static let barWidth: CGFloat = 3
    private static let maxHeight: CGFloat = 14

    var body: some View {
        let isPlaying = controller.status.isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
            let levels = isPlaying
                ? SpotifyEqualizer.levels(at: context.date.timeIntervalSinceReferenceDate)
                : SpotifyEqualizer.restingLevels()
            HStack(alignment: .bottom, spacing: Theme.Spacing.xxs) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Theme.Palette.accent(for: .spotify))
                        .frame(width: Self.barWidth, height: Self.maxHeight * levels[index])
                }
            }
            .frame(height: Self.maxHeight, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.Motion.snappy, value: isPlaying)
        .help(isPlaying ? "Playing in \((controller.source ?? .spotify).displayName)" : "Paused")
    }
}
