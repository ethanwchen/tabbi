import AppKit
import CoreImage
import SwiftUI
import NotchDeckCore

/// A decoded album cover plus its average color (for the panel's glow).
struct SpotifyArtworkImage {
    let image: NSImage
    let averageColor: Color?
}

/// Loads album art by URL and caches it, so reopening the panel or the
/// compact wing never refetches the same cover.
@MainActor
final class SpotifyArtworkLoader: ObservableObject {
    @Published private(set) var artwork: SpotifyArtworkImage?
    @Published private(set) var isLoading = false

    private static let cache: NSCache<NSURL, Box> = {
        let cache = NSCache<NSURL, Box>()
        cache.countLimit = 24
        return cache
    }()

    private final class Box {
        let artwork: SpotifyArtworkImage
        init(_ artwork: SpotifyArtworkImage) { self.artwork = artwork }
    }

    private var currentURL: URL?

    /// Shows the cover for `url`. Call from `.task(id: url)` so a track change
    /// cancels the previous download.
    func load(_ url: URL?) async {
        currentURL = url
        guard let url else {
            artwork = nil
            isLoading = false
            return
        }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            artwork = cached.artwork
            isLoading = false
            return
        }
        artwork = nil
        isLoading = true
        let decoded = await Self.fetch(url)
        guard !Task.isCancelled, currentURL == url else { return }
        if let decoded { Self.cache.setObject(Box(decoded), forKey: url as NSURL) }
        artwork = decoded
        isLoading = false
    }

    private nonisolated static func fetch(_ url: URL) async -> SpotifyArtworkImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data)
        else { return nil }
        return SpotifyArtworkImage(image: image, averageColor: averageColor(of: data))
    }

    /// The cover's mean color via `CIAreaAverage`, nudged brighter so a dark
    /// cover still gives a visible (but soft) glow on the black notch.
    private nonisolated static func averageColor(of data: Data) -> Color? {
        guard let input = CIImage(data: data),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [
                  kCIInputImageKey: input,
                  kCIInputExtentKey: CIVector(cgRect: input.extent),
              ]),
              let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil
        )
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.2, 1), brightness: max(brightness, 0.6))
    }
}

/// Album art with continuous corners. Shows a generated gradient cover for
/// tracks without artwork, and a quiet glyph while a cover downloads.
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
            } else if let track, track.artworkURL == nil {
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
        .animation(Theme.Motion.content, value: artwork?.image)
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
