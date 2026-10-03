import SwiftUI
import TabbiKitCore
import TabbiKit

/// What the pet comes out to say: a coach nudge, a celebration of points
/// just earned, or nothing at all (a silent glance from the notch's edge).
enum PetCoachLine {
    case nudge(PetCoachNudge)
    case celebration(PetStudyAward)
    case glance(PetCoachGlance)

    var replies: [PetCoachReply] {
        switch self {
        case .nudge(let nudge): nudge.kind.replies
        case .celebration: [.thanks]
        case .glance: []
        }
    }

    /// The clip the pet plays on arrival before it idles.
    var arrival: PetAnimation {
        switch self {
        case .nudge: .alert
        case .celebration: .celebrate
        case .glance: .peekIn
        }
    }

    var hasBubble: Bool {
        if case .glance = self { return false }
        return true
    }
}

/// What the coach overlay plays: one stroll of one pet with one line.
struct PetCoachScene {
    let profile: PetProfile
    let clips: PetClipSet
    var stroll: PetCoachStroll
    let line: PetCoachLine

    init(profile: PetProfile, stroll: PetCoachStroll, line: PetCoachLine) {
        self.profile = profile
        clips = PetClipSet(profile: profile)
        self.stroll = stroll
        self.line = line
    }

    init(profile: PetProfile, stroll: PetCoachStroll, nudge: PetCoachNudge) {
        self.init(profile: profile, stroll: stroll, line: .nudge(nudge))
    }

    /// A silent glance timed by the pet's own peek clips.
    init(profile: PetProfile, glanceAt start: Date) {
        let clips = PetClipSet(profile: profile)
        let glance = PetCoachGlance(startedAt: start, clips: clips)
        self.profile = profile
        self.clips = clips
        stroll = glance.stroll
        line = .glance(glance)
    }
}

/// The coach's moment on screen, drawn in a transparent overlay that sits
/// just below the menu bar with its leading edge at the notch's right edge.
///
/// The pet starts out of sight left of the overlay (under the notch), trots
/// out, says its line in a bubble with the nudge's buttons, then trots back
/// and the overlay closes. Everything is positioned from `PetCoachStroll`,
/// so `date` fully decides the picture; pass a fixed one for snapshots.
struct PetCoachOverlayView: View {
    let scene: PetCoachScene
    /// Nil follows the clock; a fixed date freezes the scene.
    var date: Date?
    let onReply: (PetCoachReply) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Points per sprite pixel: a 48 pt pet, larger than beside the notch
    /// so it holds its own over busy windows. Whole device pixels on the
    /// 2x displays that have a notch.
    static let pixelSize: CGFloat = 1.5
    static let petSide = CGFloat(PetComposer.frameSize) * pixelSize
    static let bubbleWidth: CGFloat = 244
    /// Negative: the sitting sprite has empty columns on its right, so this
    /// brings the tail close to the pet without touching it.
    static let bubbleGap = -Theme.Spacing.xs
    static let bubbleTop = Theme.Spacing.s
    /// The pet's paws sit this far below the overlay's top edge.
    static let petTop = Theme.Spacing.xs

    /// The bubble's top-left corner in the overlay, beside the pet's stop.
    static func bubbleOrigin(for stroll: PetCoachStroll) -> CGPoint {
        CGPoint(x: CGFloat(stroll.distance) + bubbleGap, y: bubbleTop)
    }

    /// Size of the overlay window for `scene`: room for the walk plus the
    /// bubble beside the pet's stopping spot, or just the pet for a glance.
    static func size(for scene: PetCoachScene) -> CGSize {
        if case .glance = scene.line { return CGSize(width: petSide, height: petSide) }
        return size(for: scene.stroll)
    }

    static func size(for stroll: PetCoachStroll) -> CGSize {
        CGSize(width: CGFloat(stroll.distance) + bubbleGap + bubbleWidth + Theme.Spacing.l, height: 120)
    }

    /// How far left of the notch's right edge the overlay starts. A glance
    /// hangs from the notch's own bottom edge, just inside its rounded
    /// corner, so it reads as peeking out of the notch; walks start at the
    /// edge.
    static func leadingOverhang(for scene: PetCoachScene) -> CGFloat {
        if case .glance = scene.line { return petSide + Theme.Layout.closedBottomRadius + Theme.Spacing.xs }
        return 0
    }

    var body: some View {
        Group {
            if let date {
                content(at: date)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    content(at: context.date)
                }
            }
        }
        .frame(width: Self.size(for: scene).width, height: Self.size(for: scene).height,
               alignment: .topLeading)
        // The window clips in the app; clip here too so the pet is hidden
        // under the notch in snapshots as well.
        .clipped()
    }

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let stroll = scene.stroll
        // Reduce Motion: no trot, the pet simply shows up at its spot.
        let offset = reduceMotion && stroll.phase(at: date) != .finished
            ? stroll.distance : stroll.offset(at: date)
        ZStack(alignment: .topLeading) {
            if case .glance(let glance) = scene.line {
                glancingPet(glance, at: date)
            } else {
                pet(at: date)
                    .offset(x: CGFloat(offset) - Self.petSide, y: Self.petTop)
            }
            if scene.line.hasBubble, stroll.showsBubble(at: date) {
                PetCoachBubble(line: scene.line, onReply: onReply)
                    .frame(width: Self.bubbleWidth, alignment: .leading)
                    .background(GeometryReader { proxy in
                        // Placed by the offset below; only the size is measured.
                        Color.clear.preference(key: PetCoachBubbleFrameKey.self,
                                               value: CGRect(origin: Self.bubbleOrigin(for: stroll), size: proxy.size))
                    })
                    .offset(x: Self.bubbleOrigin(for: stroll).x, y: Self.bubbleOrigin(for: stroll).y)
                    .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.Motion.snappy, value: stroll.showsBubble(at: date))
    }

    /// Hanging from the top edge by its front paws: the head lowers into
    /// view, looks at the user, and pulls back up. Nothing once it's gone.
    @ViewBuilder
    private func glancingPet(_ glance: PetCoachGlance, at date: Date) -> some View {
        // Reduce Motion: no lowering, the pet just hangs there for the look.
        let pose = reduceMotion
            ? glance.pose(at: date).map { _ in (PetAnimation.peekIn, glance.enter) }
            : glance.pose(at: date)
        if let pose {
            PetSpriteView(canvas: scene.clips[pose.animation].frame(at: pose.elapsed).canvas,
                          palette: scene.profile.palette, pixelSize: Self.pixelSize)
                .accessibilityLabel(scene.profile.name)
        }
    }

    /// Walking frames while moving (the clip faces left, so walking away
    /// from the notch, to the right, is mirrored); an alert hop (or a happy
    /// hop with a heart, to celebrate) on arrival, then idle breathing while
    /// the bubble is up.
    private func pet(at date: Date) -> some View {
        let stroll = scene.stroll
        let canvas: PetCanvas
        var mirrored = false
        switch stroll.phase(at: date) {
        case .walkingOut:
            canvas = scene.clips[.walk].frame(at: date.timeIntervalSince(stroll.startedAt)).canvas
            mirrored = true
        case .talking:
            let elapsed = date.timeIntervalSince(stroll.arrivesAt)
            let arrival = scene.clips[scene.line.arrival]
            canvas = elapsed < arrival.duration
                ? arrival.frame(at: elapsed).canvas
                : scene.clips[.idle].frame(at: elapsed - arrival.duration).canvas
        case .walkingBack, .finished:
            canvas = scene.clips[.walk].frame(at: date.timeIntervalSince(stroll.turnsBackAt)).canvas
        }
        return PetSpriteView(canvas: canvas, palette: scene.profile.palette, pixelSize: Self.pixelSize)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityLabel(scene.profile.name)
    }
}

/// Where the speech bubble is, in the overlay's top-left coordinates; nil
/// while it's hidden. The overlay window takes clicks only there.
struct PetCoachBubbleFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

/// The speech bubble: the pet's line and its buttons, on the same black as
/// the notch so it reads as part of it, over any wallpaper.
private struct PetCoachBubble: View {
    let line: PetCoachLine
    let onReply: (PetCoachReply) -> Void

    private static let accent = ClosetModule.descriptor.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch line {
            case .nudge(let nudge):
                Text(nudge.message.text)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            case .celebration(let award):
                PetCelebrationText(award: award, accent: Self.accent)
            case .glance:
                EmptyView()
            }
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(line.replies, id: \.self) { reply in
                    PetCoachReplyButton(reply: reply, isPrimary: reply == line.replies.first,
                                        accent: Self.accent) { onReply(reply) }
                }
            }
        }
        .padding(Theme.Spacing.m)
        .padding(.leading, PetCoachBubbleShape.tailLength)
        .background(PetCoachBubbleShape().fill(Theme.Palette.background))
        .overlay(PetCoachBubbleShape().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }
}

/// A celebration's words: the headline with the points pill beside it,
/// and on a level-up the item that is now within reach.
private struct PetCelebrationText: View {
    let award: PetStudyAward
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(award.headline)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    Text(award.pointsText).monospacedDigit()
                }
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(height: 18)
                .background(Capsule().fill(accent.opacity(0.16)))
                .fixedSize()
                .help("Points earned for this session")
            }
            if let unlock = award.unlockLine {
                Text(unlock)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A rounded bubble with a short tail on its leading edge, pointing at the
/// pet's head. One outline, so the stroke runs around the tail unbroken.
private struct PetCoachBubbleShape: Shape {
    static let tailLength: CGFloat = 7
    /// The tail's tip, from the bubble's top: level with the pet's face.
    static let tailY: CGFloat = 22
    static let tailHalfHeight: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX + Self.tailLength, y: rect.minY,
                          width: rect.width - Self.tailLength, height: rect.height)
        let bubble = Path(roundedRect: body, cornerRadius: Theme.Radius.l, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: body.minX + 1, y: rect.minY + Self.tailY - Self.tailHalfHeight))
        tail.addLine(to: CGPoint(x: rect.minX, y: rect.minY + Self.tailY))
        tail.addLine(to: CGPoint(x: body.minX + 1, y: rect.minY + Self.tailY + Self.tailHalfHeight))
        tail.closeSubpath()
        return bubble.union(tail)
    }
}

/// A bubble button: the first answer is accent-filled, the rest are quiet.
/// Snooze carries a moon so it's findable at a glance.
private struct PetCoachReplyButton: View {
    let reply: PetCoachReply
    let isPrimary: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xxs + 1) {
                if reply == .snooze {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 9, weight: .semibold))
                }
                Text(reply.title).lineLimit(1)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 22)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(reply.help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }

    private var foreground: Color {
        if isPrimary { return .black }
        return hovering ? Theme.Palette.primaryText : Theme.Palette.secondaryText
    }

    private var background: Color {
        if isPrimary { return hovering ? accent.opacity(0.85) : accent }
        return hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface
    }
}
