import AppKit
import SwiftUI
import TabbiKitCore
import TabbiKit

/// A decoded album cover plus its average color (for the panel's glow).
struct SpotifyArtworkImage {
    let image: NSImage
    let averageColor: Color?
}

/// Loads album art (Spotify by URL, Music as raw AppleScript bytes) and
/// caches it in memory by track id, so reopening the panel or the compact
/// wing never refetches the same cover.
@MainActor
final class SpotifyArtworkLoader: ObservableObject {
    @Published private(set) var artwork: SpotifyArtworkImage?
    @Published private(set) var isLoading = false

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 24
        return cache
    }()

    private final class Box {
        let artwork: SpotifyArtworkImage
        init(_ artwork: SpotifyArtworkImage) { self.artwork = artwork }
    }

    private var currentID: String?

    /// Shows the cover for `track`. Call from `.task(id: track?.id)` so a
    /// track change cancels the previous load.
    func load(_ track: SpotifyTrack?, from controller: SpotifyController) async {
        currentID = track?.id
        guard let track else {
            artwork = nil
            isLoading = false
            return
        }
        let key = track.id as NSString
        if let cached = Self.cache.object(forKey: key) {
            artwork = cached.artwork
            isLoading = false
            return
        }
        artwork = nil
        isLoading = true
        let data: Data?
        if let url = track.artworkURL {
            data = try? await URLSession.shared.data(from: url).0
        } else {
            data = await controller.artworkData(for: track)
        }
        var decoded: SpotifyArtworkImage?
        if let data { decoded = await Self.decode(data) }
        guard !Task.isCancelled, currentID == track.id else { return }
        if let decoded { Self.cache.setObject(Box(decoded), forKey: key) }
        artwork = decoded
        isLoading = false
    }

    /// Decodes the cover at the size the panel draws it (`ArtworkThumbnail`),
    /// so a 3000 pixel Music cover never sits in memory at full size.
    private nonisolated static func decode(_ data: Data) async -> SpotifyArtworkImage? {
        guard let thumbnail = ArtworkThumbnail(data: data) else { return nil }
        let image = NSImage(cgImage: thumbnail.image,
                            size: NSSize(width: thumbnail.image.width, height: thumbnail.image.height))
        return SpotifyArtworkImage(image: image, averageColor: glowColor(from: thumbnail.averageColor))
    }

    /// The cover's mean color, nudged brighter so a dark cover still gives a
    /// visible (but soft) glow on the black notch.
    private nonisolated static func glowColor(from mean: (red: Double, green: Double, blue: Double)) -> Color {
        let color = NSColor(red: mean.red, green: mean.green, blue: mean.blue, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.2, 1), brightness: max(brightness, 0.6))
    }
}

/// Album art with continuous corners. Shows a generated gradient cover for
/// tracks without (loadable) artwork (the demo track's own drawn cover for
/// that one), and a quiet glyph while a cover loads.
struct SpotifyArtworkView: View {
    let track: SpotifyTrack?
    let artwork: SpotifyArtworkImage?
    let isLoading: Bool
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let artwork {
                Image(nsImage: artwork.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if let track, !isLoading, DemoAlbumCover.isCover(of: track) {
                DemoAlbumCover()
            } else if let track, !isLoading {
                SpotifyGeneratedCoverView(cover: SpotifyGeneratedCover(seed: track.id), size: size)
            } else {
                Theme.Palette.surface
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .opacity(isLoading ? 0.6 : 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
        .motion(Theme.Motion.content, value: artwork?.image)
    }
}

/// A deterministic gradient cover with a soft highlight and a note glyph.
struct SpotifyGeneratedCoverView: View {
    let cover: SpotifyGeneratedCover
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: cover.startHue, saturation: 0.72, brightness: 0.86),
                         Color(hue: cover.endHue, saturation: 0.80, brightness: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(0.32), .clear],
                           center: UnitPoint(x: 0.28, y: 0.24), startRadius: 0, endRadius: size * 0.7)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: size * 0.04, y: size * 0.02)
        }
    }

    /// The color the glow behind the panel uses for this cover.
    static func glowColor(for cover: SpotifyGeneratedCover) -> Color {
        Color(hue: cover.startHue, saturation: 0.7, brightness: 0.85)
    }
}
