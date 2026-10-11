import SwiftUI
import TabbiKitCore

/// Original cover art for the made-up demo track ("Golden Hour Drive" by
/// Maple Avenue): a road running into a setting sun between dusky hills.
/// Drawn in code, so store screenshots never show a real album's art and
/// demo mode needs no image file or network.
struct DemoAlbumCover: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: [Self.rgb(0x2E1F4F), Self.rgb(0xA8466A), Self.rgb(0xF08A5D), Self.rgb(0xF9C784)],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.62))
                stars(side: side)
                Circle()
                    .fill(RadialGradient(colors: [Self.rgb(0xF9C784).opacity(0.55), .clear],
                                         center: .center, startRadius: side * 0.1, endRadius: side * 0.42))
                    .frame(width: side * 0.84, height: side * 0.84)
                    .position(x: side * 0.5, y: side * 0.6)
                Circle()
                    .fill(LinearGradient(colors: [Self.rgb(0xFFE7A3), Self.rgb(0xF7A74F)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: side * 0.42, height: side * 0.42)
                    .position(x: side * 0.5, y: side * 0.6)
                Hills(peaks: [0.52, 0.6, 0.5, 0.58, 0.54]).fill(Self.rgb(0x8C3D5E))
                Hills(peaks: [0.62, 0.66, 0.6, 0.68, 0.62]).fill(Self.rgb(0x4A2545))
                Road().fill(Self.rgb(0x2A1830))
                RoadLine().stroke(Self.rgb(0xF9C784).opacity(0.9),
                                  style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round,
                                                     dash: [side * 0.05, side * 0.045]))
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// A few fixed stars in the darkest part of the sky.
    private func stars(side: CGFloat) -> some View {
        let points: [(CGFloat, CGFloat, CGFloat)] = [
            (0.14, 0.1, 0.012), (0.3, 0.2, 0.008), (0.46, 0.07, 0.01), (0.68, 0.15, 0.012),
            (0.86, 0.08, 0.009), (0.8, 0.26, 0.007), (0.22, 0.32, 0.007),
        ]
        return ForEach(points.indices, id: \.self) { index in
            let point = points[index]
            Circle().fill(.white.opacity(0.85))
                .frame(width: side * point.2, height: side * point.2)
                .position(x: side * point.0, y: side * point.1)
        }
    }

    /// Whether `track` is the demo track, which has no artwork URL or bytes
    /// and shows this cover in place of a generated one. Drawn in the view
    /// rather than loaded, so snapshot renders show it too.
    static func isCover(of track: SpotifyTrack) -> Bool {
        track.id == SpotifyPlayback.demo.track?.id
    }

    /// The warm sunset tone the panel's glow takes behind this cover.
    static let glowColor = rgb(0xF08A5D)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

/// A rolling ridge across the bottom of the cover. `peaks` are the ridge's
/// heights (as a fraction of the side from the top), evenly spaced.
private struct Hills: Shape {
    let peaks: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / CGFloat(peaks.count - 1)
        let points = peaks.enumerated().map { CGPoint(x: rect.minX + CGFloat($0.offset) * step,
                                                      y: rect.minY + $0.element * rect.height) }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: points[0])
        for (previous, point) in zip(points, points.dropFirst()) {
            let middle = (previous.x + point.x) / 2
            path.addCurve(to: point, control1: CGPoint(x: middle, y: previous.y),
                          control2: CGPoint(x: middle, y: point.y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The road: wide at the bottom edge, narrowing to the horizon under the sun.
private struct Road: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.47, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.53, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The road's dashed center line.
private struct RoadLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.67))
        return path
    }
}
