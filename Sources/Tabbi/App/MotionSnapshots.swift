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
        shots.append(("motion-press", AnyView(pressStates(accent: accent))))
        return shots
    }

    /// The states of `TactileButtonStyle` side by side (rest, hover, pressed,
    /// and pressed under Reduce Motion) for an icon, a play button and a
    /// labeled pill, so the press depth and hover lift can be judged.
    private static func pressStates(accent: Color) -> some View {
        let states: [(String, pressed: Bool, hovering: Bool, reduce: Bool)] = [
            ("rest", false, false, false), ("hover", false, true, false),
            ("pressed", true, true, false), ("reduced", true, true, true),
        ]
        func tactile(_ control: some View, _ feedback: TactileFeedback, lifts: Bool,
                     _ state: (String, pressed: Bool, hovering: Bool, reduce: Bool)) -> some View {
            control
                .scaleEffect(feedback.scale(pressed: state.pressed, hovering: state.hovering,
                                            lifts: lifts, reduceMotion: state.reduce))
                .opacity(feedback.opacity(pressed: state.pressed, reduceMotion: state.reduce))
        }
        return HStack(spacing: Theme.Spacing.s) {
            ForEach(states, id: \.0) { state in
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.m) {
                        tactile(Image(systemName: "gearshape.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Palette.primaryText)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(state.hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)),
                                .control, lifts: false, state)
                        tactile(Image(systemName: "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.Palette.background)
                                    .offset(x: 1)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Theme.Palette.primaryText)),
                                .control, lifts: true, state)
                        tactile(Label("Start focus", systemImage: "play.fill")
                                    .font(Theme.Typography.bodyEmphasis)
                                    .foregroundStyle(Theme.Palette.background)
                                    .padding(.horizontal, Theme.Spacing.m)
                                    .frame(height: 28)
                                    .background(Capsule().fill(accent.opacity(state.hovering ? 1 : 0.88))),
                                .pill, lifts: false, state)
                    }
                    .frame(width: 260, height: 64)
                    .background(Theme.Palette.background)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
                    Text(state.0)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Color(white: 0.16))
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
