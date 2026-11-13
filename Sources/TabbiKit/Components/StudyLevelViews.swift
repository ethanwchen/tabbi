import SwiftUI
import TabbiKitCore

/// A rank's pixel emblem (`RankArt`), drawn the way the pet and the Goals
/// badges are: a whole number of device pixels per sprite pixel, never
/// interpolated. `pixelSize` is points per sprite pixel before the panel's
/// content scale (1 beside the pet's name, 0.5 in Party's tight rows,
/// where a Retina display still draws one device pixel per sprite pixel).
public struct StudyRankEmblem: View {
    let rank: StudyRank
    let pixelSize: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(\.panelScale) private var panelScale

    public init(_ rank: StudyRank, pixelSize: CGFloat = 1) {
        self.rank = rank
        self.pixelSize = pixelSize
    }

    /// The emblem's side in points at `pixelSize`.
    public static func side(pixelSize: CGFloat) -> CGFloat { CGFloat(RankArt.size) * pixelSize }

    public var body: some View {
        let side = Self.side(pixelSize: pixelSize)
        // Whole device pixels per sprite pixel once the panel's content
        // scale is applied; the image fills the frame, so a 1x display
        // that cannot show half points keeps the layout and drops pixels
        // evenly rather than blurring them.
        let scale = max(1, Int((pixelSize * panelScale * displayScale).rounded()))
        return Group {
            if let image = RankArt.image(rank, scale: scale) {
                Image(decorative: image, scale: displayScale)
                    .interpolation(.none)
                    .resizable()
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The Study Level beside a name: the rank's emblem, then "Lv 12" and the
/// rank's name, shortened only as far as the room demands ("Lv 12", then
/// "12") so nothing is ever cut off. The tooltip always says it in full.
public struct StudyLevelLabel: View {
    public enum Length: CaseIterable, Sendable {
        /// "Lv 12 Ember".
        case full
        /// "Lv 12".
        case level
        /// "12".
        case number
    }

    let standing: StudyStanding
    let length: Length
    let pixelSize: CGFloat

    public init(_ standing: StudyStanding, length: Length = .full, pixelSize: CGFloat = 1) {
        self.standing = standing
        self.length = length
        self.pixelSize = pixelSize
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            StudyRankEmblem(standing.rank, pixelSize: pixelSize)
            Group {
                switch length {
                case .full:
                    Text(standing.level.shortLabel).foregroundStyle(Theme.Palette.secondaryText)
                        + Text(verbatim: " \(standing.rank.displayName)").foregroundStyle(Theme.Palette.tertiaryText)
                case .level:
                    Text(standing.level.shortLabel).foregroundStyle(Theme.Palette.secondaryText)
                case .number:
                    Text(verbatim: "\(standing.level.value)").foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .lineLimit(1)
        }
        .fixedSize()
        .help(Self.help(standing))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.help(standing))
    }

    /// "Level 12, Ember".
    public static func help(_ standing: StudyStanding) -> String {
        String(localized: "\(standing.level.label), \(standing.rank.displayName)", bundle: .tabbi)
    }
}

public extension View {
    /// Tints a name with its nameplate color: plain is the theme's primary
    /// text, the others their own color, and the rarer ones (from Level 40)
    /// glow softly around the letters.
    func nameplate(_ nameplate: Nameplate) -> some View {
        modifier(NameplateTint(nameplate: nameplate))
    }
}

public extension Nameplate {
    /// The tint as a SwiftUI color; plain follows the theme's primary text.
    var tint: Color {
        guard self != .plain else { return Theme.Palette.primaryText }
        return Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255,
                     blue: Double(color.blue) / 255)
    }
}

private struct NameplateTint: ViewModifier {
    let nameplate: Nameplate

    func body(content: Content) -> some View {
        content
            .foregroundStyle(nameplate.tint)
            .shadow(color: nameplate.glows ? nameplate.tint.opacity(0.55) : .clear, radius: 3)
    }
}
