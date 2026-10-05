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
        let pawMoments = stride(from: 0.1, to: PawTrail.cycle, by: PawTrail.stepInterval).map { $0 }
        shots.append(("motion-loader-paws", AnyView(strip(pawMoments) { time in
            PawTrailFrame(tint: AskClaudeModule.descriptor.accentColor, size: 40, time: time)
        })))
        shots.append(("motion-loader-paws-in-context", AnyView(strip([1.06]) { time in
            // The Ask Claude bubble while Claude thinks, at full trail.
            Card(padding: 0) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Thinking").foregroundStyle(Theme.Palette.tertiaryText)
                    PawTrailFrame(tint: AskClaudeModule.descriptor.accentColor, size: 16, time: time)
                }
                .font(Theme.Typography.body)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
            }
            .fixedSize()
        })))
        shots.append(("motion-loader-paws-reduced", AnyView(strip([0, 0.4, 0.8]) { time in
            PawTrailFrame(tint: AskClaudeModule.descriptor.accentColor, size: 40, time: time, reduceMotion: true)
        })))
        shots.append(("motion-check", AnyView(checkFrames())))
        shots.append(("motion-transitions", AnyView(transitionFrames())))
        return shots
    }

    /// `CheckGlyph` turning on, sampled along the check spring (the fill
    /// pops, the stroke draws on, the overshoot swells it), then the Reduce
    /// Motion crossfade, each at row size and at 3x for detail.
    private static func checkFrames() -> some View {
        let accent = TodayModule.descriptor.accentColor
        let moments: [TimeInterval] = [0, 0.04, 0.08, 0.12, 0.16, 0.2, 0.3, 0.5]
        func column(_ label: String, _ progress: Double, reduce: Bool) -> some View {
            VStack(spacing: Theme.Spacing.s) {
                CheckGlyphFrame(progress: progress, tint: accent, size: 48, reduceMotion: reduce)
                CheckGlyphFrame(progress: progress, tint: accent, reduceMotion: reduce)
                Text(label)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .frame(width: 64)
        }
        return HStack(spacing: Theme.Spacing.m) {
            ForEach(moments, id: \.self) { moment in
                column(String(format: "%.2f s", moment), MotionTokens.check.value(at: moment), reduce: false)
            }
            Divider().frame(height: 80)
            ForEach([0.0, 0.5, 1], id: \.self) { fade in
                column(String(format: "RM %.0f%%", fade * 100), fade, reduce: true)
            }
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.background)
    }

    /// The shared insert transitions (`.motionPop`, `.motionSwap` and
    /// `.motionRow`) sampled along the snappy spring, then their Reduce
    /// Motion fade at its midpoint, on a sample control, card and row.
    private static func transitionFrames() -> some View {
        let accent = TodayModule.descriptor.accentColor
        let moments: [TimeInterval] = [0, 0.03, 0.06, 0.1, 0.15, 0.25]
        let samples: [(String, TransitionPose, AnyView)] = [
            ("pop", .pop, AnyView(Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.Palette.surfaceHover)))),
            ("swap", .swap, AnyView(Card {
                Text("Plan my day").font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(width: 120, height: 52))),
            ("row", .row(from: .top), AnyView(HStack(spacing: Theme.Spacing.s) {
                Circle().fill(accent).frame(width: 8, height: 8)
                Text("Standup 10:00").font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.primaryText)
            }.frame(width: 120, height: 24, alignment: .leading))),
        ]
        func cell(_ view: AnyView, _ pose: TransitionPose, progress: Double, reduce: Bool) -> some View {
            let outside = pose.resolved(isIdentity: false, reduceMotion: reduce)
            func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * progress }
            return view
                .scaleEffect(mix(outside.scale, 1), anchor: UnitPoint(x: pose.anchorX, y: pose.anchorY))
                .offset(x: mix(outside.offsetX, 0), y: mix(outside.offsetY, 0))
                .opacity(mix(outside.opacity, 1))
                .frame(width: 136, height: 64)
                .background(Theme.Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        }
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(samples, id: \.0) { name, pose, view in
                HStack(spacing: Theme.Spacing.s) {
                    Text(name).font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .frame(width: 40, alignment: .leading)
                    ForEach(moments, id: \.self) { moment in
                        cell(view, pose, progress: MotionTokens.snappy.value(at: moment), reduce: false)
                    }
                    cell(view, pose, progress: 0.5, reduce: true)
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                Color.clear.frame(width: 40, height: 1)
                ForEach(moments, id: \.self) { moment in
                    Text(String(format: "%.2f s", moment)).frame(width: 136)
                }
                Text("RM 50%").frame(width: 136)
            }
            .font(Theme.Typography.caption.monospacedDigit())
            .foregroundStyle(Theme.Palette.secondaryText)
        }
        .padding(Theme.Spacing.m)
        .background(Color(white: 0.16))
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
