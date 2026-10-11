import SwiftUI
import TabbiKitCore
import TabbiKit

/// What the pet comes out to say: a coach nudge, a celebration of points
/// just earned (with the bar toward the next unlock, and now and then a Cat
/// wisdom line after it), or nothing at all (a silent glance from the
/// notch's edge).
enum PetCoachLine {
    case nudge(PetCoachNudge)
    case celebration(PetStudyAward, progress: UnlockProgress?, wisdom: CatWisdomLine? = nil, gift: SurpriseGiftDelivery? = nil)
    case glance(PetCoachGlance)

    /// The Cat wisdom line a celebration moves on to, if any.
    var wisdom: CatWisdomLine? {
        if case .celebration(_, _, let wisdom, _) = self { return wisdom }
        return nil
    }

    /// How long the bubble talks: a celebration, plus its wisdom line.
    var talkDuration: TimeInterval {
        PetCoach.celebrationDuration + (wisdom == nil ? 0 : PetCoach.wisdomDuration)
    }

    /// Whether the bubble shows the wisdom line rather than the points
    /// after `elapsed` seconds of talking (holds not counted).
    func showsWisdom(afterTalking elapsed: TimeInterval) -> Bool {
        wisdom != nil && elapsed >= PetCoach.celebrationDuration
    }

    /// The bubble's buttons. A celebration has none: a click anywhere on
    /// the bubble sends the pet home, so the moment never asks for anything.
    var replies: [PetCoachReply] {
        switch self {
        case .nudge(let nudge): nudge.kind.replies
        case .celebration, .glance: []
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
                TimelineView(PetCoachSchedule(scene: scene)) { context in
                    content(at: context.date)
                }
            }
        }
        .frame(width: Self.size(for: scene).width, height: Self.size(for: scene).height,
               alignment: .topLeading)
        // The window clips in the app; clip here too so the pet is hidden
        // under the notch in snapshots as well.
        .clipped()
        // The window hangs to the right of the notch in every language, so
        // the pet walks out the same way; the bubble's words follow the language.
        .fixedLeftToRight()
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
                PetCoachBubble(line: scene.line, showsWisdom: scene.line.showsWisdom(afterTalking: stroll.talkElapsed(at: date)),
                               animated: self.date == nil, onReply: onReply)
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
        .motion(Theme.Motion.snappy, value: stroll.showsBubble(at: date))
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
            PetSpriteView(canvas: drawn(scene.clips[pose.animation].frame(at: pose.elapsed), at: date),
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
        let frame: PetFrame
        var mirrored = false
        switch stroll.phase(at: date) {
        case .walkingOut:
            frame = scene.clips[.walk].frame(at: date.timeIntervalSince(stroll.startedAt))
            mirrored = true
        case .talking:
            let elapsed = date.timeIntervalSince(stroll.arrivesAt)
            let arrival = scene.clips[scene.line.arrival]
            frame = elapsed < arrival.duration
                ? arrival.frame(at: elapsed)
                : scene.clips[.idle].frame(at: elapsed - arrival.duration)
        case .walkingBack, .finished:
            frame = scene.clips[.walk].frame(at: date.timeIntervalSince(stroll.turnsBackAt))
        }
        return PetSpriteView(canvas: drawn(frame, at: date), palette: scene.profile.palette, pixelSize: Self.pixelSize)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .accessibilityLabel(scene.profile.name)
    }

    /// `frame` with its worn items at their loop step for `date` (a cape's
    /// glint, flapping wings). Reduce Motion keeps the items' still frame.
    private func drawn(_ frame: PetFrame, at date: Date) -> PetCanvas {
        reduceMotion ? frame.canvas : frame.atItemTime(date.timeIntervalSinceReferenceDate).canvas
    }
}

/// Redraws the overlay only when its picture changes (see `PetCoachRedraw`):
/// every frame while the pet walks, on clip frame changes while it stands or
/// peeks. A dismissal changes the scene, which brings a fresh schedule.
private struct PetCoachSchedule: TimelineSchedule {
    let scene: PetCoachScene

    func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            guard let date = next else { return nil }
            switch scene.line {
            case .glance(let glance):
                next = glance.nextRedraw(after: date, clips: scene.clips)
            case .nudge, .celebration:
                let marks = scene.line.wisdom == nil ? []
                    : [scene.stroll.date(afterTalking: PetCoach.celebrationDuration)].compactMap { $0 }
                next = scene.stroll.nextRedraw(after: date, clips: scene.clips, arrival: scene.line.arrival, marks: marks)
            }
            return date
        }
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
    /// True once a celebration has moved on to its Cat wisdom line.
    let showsWisdom: Bool
    /// False in snapshots, which show a celebration's count already settled.
    let animated: Bool
    let onReply: (PetCoachReply) -> Void
    @State private var hovering = false

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
            case .celebration(let award, let progress, let wisdom, let gift):
                if showsWisdom, let wisdom {
                    PetWisdomText(line: wisdom, accent: Self.accent)
                        .transition(.opacity)
                } else {
                    PetCelebrationText(award: award, progress: progress, gift: gift, accent: Self.accent,
                                       animated: animated)
                        .transition(.opacity)
                }
            case .glance:
                EmptyView()
            }
            if !line.replies.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(line.replies, id: \.self) { reply in
                        PetCoachReplyButton(reply: reply, isPrimary: reply == line.replies.first,
                                            accent: Self.accent) { onReply(reply) }
                    }
                }
            }
        }
        .tabbiLayoutDirection()
        .padding(Theme.Spacing.m)
        .padding(.leading, PetCoachBubbleShape.tailLength)
        .background(PetCoachBubbleShape().fill(Theme.Palette.background))
        .overlay(PetCoachBubbleShape().stroke(Color.white.opacity(dismissesOnClick && hovering ? 0.28 : 0.14),
                                              lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .contentShape(PetCoachBubbleShape())
        .onTapGesture { if dismissesOnClick { onReply(.thanks) } }
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.content, value: showsWisdom)
        .help(dismissesOnClick ? String(localized: "Click to send the pet home", bundle: .tabbi) : "")
        .accessibilityElement(children: .contain)
        .accessibilityAction { if dismissesOnClick { onReply(.thanks) } }
    }

    /// A bubble without buttons closes on a click anywhere on it.
    private var dismissesOnClick: Bool { line.hasBubble && line.replies.isEmpty }
}

/// A celebration's words: the headline with the points pill beside it,
/// counting up from zero, then a bar filling toward the next unlock with
/// what it still asks ("1 more session to Ninja Headband"). Without a goal
/// left, a level-up names the item now within reach. A surprise gift gets
/// one quiet line at the bottom.
private struct PetCelebrationText: View {
    let award: PetStudyAward
    let progress: UnlockProgress?
    let gift: SurpriseGiftDelivery?
    let accent: Color
    let animated: Bool
    /// False until the bubble is up, then springs to true: the count and
    /// the bar animate from their before values to the earned ones.
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long after the bubble appears the count and the bar start.
    private static let countDelay = 0.25

    private var shown: Bool { settled || !animated }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(award.headline)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                    PetCountingPoints(value: Double(shown ? award.points : 0), total: award.points)
                }
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(height: 18)
                .background(Capsule().fill(accent.opacity(0.16)))
                .fixedSize()
                .help(String(localized: "Points earned for this session", bundle: .tabbi))
            }
            if let progress {
                PetUnlockBar(progress: progress, fraction: shown ? progress.fraction : progress.fractionBefore,
                             accent: accent)
            } else if let unlock = award.unlockLine {
                Text(unlock)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
            }
            if let gift {
                PetGiftLine(delivery: gift, accent: accent)
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            guard animated, !settled else { return }
            withAnimation(TabbiKit.Motion.adapted(TabbiKit.Motion.content, reduceMotion: reduceMotion)
                .delay(Self.countDelay)) {
                settled = true
            }
        }
    }
}

/// The gift the cat brought back, under the bar ("Found: ..." when
/// it carried the gift home from its adventure). Bonus points are already
/// on the balance and a rare fur is waiting in the Closet's Look.
private struct PetGiftLine: View {
    let delivery: SurpriseGiftDelivery
    let accent: Color

    private var gift: SurpriseGift { delivery.gift }

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs + 1) {
            Image(systemName: "gift.fill").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
            Text(delivery.message)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(1)
            if case .rareFur(let fur) = gift {
                Circle()
                    .fill(Color(red: Double(fur.color.red) / 255, green: Double(fur.color.green) / 255,
                                blue: Double(fur.color.blue) / 255))
                    .overlay(Circle().strokeBorder(Theme.Palette.stroke, lineWidth: 0.5))
                    .frame(width: 10, height: 10)
            }
        }
        .font(Theme.Typography.caption.weight(.medium))
        .help(help)
    }

    private var help: String {
        delivery.adventure == nil ? kindHelp : "Your pet found this on its adventure. \(kindHelp)"
    }

    private var kindHelp: String {
        switch gift {
        case .bonusPoints: String(localized: "Bonus points from your pet, added to your balance", bundle: .tabbi)
        case .rareFur: String(localized: "A rare fur color from your pet. Try it in the Closet under Look.", bundle: .tabbi)
        case .seasonMinutes: String(localized: "Bonus minutes toward this event's limited items", bundle: .tabbi)
        }
    }
}

/// A Cat wisdom line: a small label, then the line itself in up to three
/// short lines. The bubble is the same width as the celebration's, so the
/// pet does not jump when the words change.
private struct PetWisdomText: View {
    let line: CatWisdomLine
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: "sparkle").font(.system(size: 8, weight: .bold)).foregroundStyle(accent)
                Text("Cat wisdom", bundle: .tabbi)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)
            Text(line.displayText)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .help(Text("A line from your pet. Hover to keep it, click to send the pet home. Turn it off in Settings › General.",
                    bundle: .tabbi))
    }
}

/// "+35", counting up as `value` animates. Clamped to the points earned,
/// so a spring's overshoot never shows a number that wasn't earned.
private struct PetCountingPoints: View, Animatable {
    var value: Double
    let total: Int

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("+\(min(total, max(0, Int(value.rounded()))))").monospacedDigit()
    }
}

/// A slim bar toward the next unlock, with the item and what it still asks
/// below it.
private struct PetUnlockBar: View {
    let progress: UnlockProgress
    let fraction: Double
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs + 1) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.surface)
                    Capsule().fill(accent)
                        .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 4)
            .fixedLeftToRight()
            Text(progress.line)
                .font(Theme.Typography.caption)
                .foregroundStyle(progress.isReady ? accent : Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(progress.isReady ? String(localized: "\(progress.item.displayName) is ready in the Closet", bundle: .tabbi)
              : String(localized: "\(progress.missing) more points for \(progress.item.displayName)", bundle: .tabbi))
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
        .motion(Theme.Motion.snappy, value: hovering)
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
