import SwiftUI
import TabbiKitCore
import TabbiKit

/// Frame strips of Tabbi's motion for `--snapshot`: each animation drawn at
/// several moments side by side, so its arc, timing and fade can be reviewed
/// like a motion designer would, without watching it play.
@MainActor
enum MotionSnapshots {
    /// The moments each strip shows, in seconds after the start.
    static let celebrationFrames: [TimeInterval] = [0.05, 0.15, 0.3, 0.5, 0.8, 1.1, 1.4]

    /// (file name, view) for every strip worth reviewing.
    static func shots() -> [(String, AnyView)] {
        let accent = FocusModule.descriptor.accentColor
        var shots: [(String, AnyView)] = []
        for style in CelebrationStyle.allCases {
            for tier in CelebrationTier.allCases {
                let celebration = Celebration(tier: tier, style: style, accent: accent,
                                              id: UUID(uuidString: "6A70C66B-0000-4000-8000-000000000001")!)
                shots.append(("motion-celebration-\(style.rawValue)-\(tier.rawValue)", AnyView(strip(celebrationFrames) { elapsed in
                    CelebrationFrame(celebration, elapsed: elapsed)
                })))
            }
        }
        let glow = Celebration(tier: .burst, style: .confetti, accent: accent)
        shots.append(("motion-celebration-reduced", AnyView(strip([0.1, 0.3, 0.5, 0.7, 0.85]) { elapsed in
            CelebrationGlow(glow, elapsed: elapsed)
        })))
        return shots
    }

    /// One frame per moment, each on a notch-black panel the size of the
    /// open notch's content area, labelled with its time.
    private static func strip(_ moments: [TimeInterval], frame: @escaping (TimeInterval) -> some View) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(moments, id: \.self) { moment in
                VStack(spacing: Theme.Spacing.xs) {
                    frame(moment)
                        .frame(width: 260, height: 150)
                        .background(Theme.Palette.background)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
                    Text(String(format: "%.2f s", moment))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Color(white: 0.16))
    }
}
