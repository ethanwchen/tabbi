import SwiftUI

/// The security-monitor look the Pet Cam borrows: a near-black screen,
/// pale green-white burn-in text in a monospaced face, a red REC dot,
/// scanlines and a little grain. Shared by the app and the Live Activity,
/// so the Lock Screen looks like the same camera.
enum CCTV {
    /// The monitor's glass: near-black with a hint of green, never #000.
    static let screen = Color(red: 0.035, green: 0.043, blue: 0.040)
    /// A raised surface on the monitor (sheets, cards).
    static let panel = Color(red: 0.075, green: 0.085, blue: 0.082)
    /// Burn-in text: the faintly green white of a camera's overlay.
    static let burnIn = Color(red: 0.90, green: 0.96, blue: 0.91)
    /// The REC dot.
    static let rec = Color(red: 1.0, green: 0.27, blue: 0.24)
    /// The dot when the camera is not filming (a break, a short block).
    static let standby = Color(red: 0.55, green: 0.60, blue: 0.57)

    /// Burn-in type at a text style, so it follows Dynamic Type.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    /// "2026-11-08  21:04:33", the way a camera stamps its frames.
    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02d  %02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0,
                      c.minute ?? 0, c.second ?? 0)
    }
}

/// Faint horizontal lines across the picture, one every few device
/// pixels, the mark of a CCTV monitor. Purely decorative.
struct Scanlines: View {
    var opacity: Double = 0.16
    /// Points between lines.
    var spacing: CGFloat = 3

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let line = 1 / max(displayScale, 1)
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: line)), with: .color(.black))
                y += spacing
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The red recording dot and its word, as cameras burn it in.
struct RecLabel: View {
    var text: String = "REC"
    var isRecording = true
    /// The dot grows with the word at larger text sizes.
    @ScaledMetric(relativeTo: .caption) var dot: CGFloat = 9

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRecording ? CCTV.rec : CCTV.standby)
                .frame(width: dot, height: dot)
                .shadow(color: (isRecording ? CCTV.rec : .clear).opacity(0.7), radius: 3)
            Text(verbatim: text)
                .font(CCTV.font(.caption, weight: .bold))
                .foregroundStyle(CCTV.burnIn)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: isRecording ? "Recording" : text))
    }
}
