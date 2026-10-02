import SwiftUI
import NotchKitCore
import NotchKit

/// Frozen coach overlay moments for `--snapshot`, each drawn in place below
/// a stand-in menu bar and the notch's right half, so the review shows how
/// the pet sits against the real screen edge.
@MainActor
enum PetCoachSnapshots {
    /// (file name, view) for every overlay state worth reviewing.
    /// Bubbles use the last line of each kind in `lines`, which is the
    /// active kit's own line when it has one.
    static func shots(profile: PetProfile, lines: [PetCoachMessage]) -> [(String, AnyView)] {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stroll = PetCoachStroll(startedAt: start)
        var shots: [(String, AnyView)] = []
        // Mid-trot on the way out, before the bubble.
        // The silent look: halfway down, then hanging and looking.
        let glance = PetCoachScene(profile: profile, glanceAt: start)
        if case .glance(let timing) = glance.line {
            shots.append(("coach-glance-lowering", scene(glance, at: start.addingTimeInterval(timing.enter * 0.12))))
            shots.append(("coach-glance", scene(glance, at: start.addingTimeInterval(timing.enter + 1))))
        }
        let walking = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(.distraction, lines))
        shots.append(("coach-walking", scene(walking, at: start.addingTimeInterval(stroll.walkDuration * 0.6))))
        // One talking shot per bubble kind, after the arrival hop.
        let talking = stroll.arrivesAt.addingTimeInterval(3)
        for kind in PetCoachNudgeKind.allCases {
            let scene = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(kind, lines))
            shots.append(("coach-\(name(kind))", self.scene(scene, at: talking)))
        }
        // Celebrations: mid-hop with the heart up, then a level-up bubble.
        let party = PetCoachStroll(startedAt: start, talkDuration: PetCoach.celebrationDuration)
        let done = PetCoachScene(profile: profile, stroll: party,
                                 line: .celebration(PetStudyAward(completedSessions: 1, minutes: 25, points: 35)))
        shots.append(("coach-celebrate", scene(done, at: party.arrivesAt.addingTimeInterval(0.3))))
        let levelUp = PetCoachScene(profile: profile, stroll: party, line: .celebration(
            PetStudyAward(completedSessions: 1, minutes: 50, points: 60, unlocked: [.outfit(.scrubs)])))
        shots.append(("coach-level-up", scene(levelUp, at: party.arrivesAt.addingTimeInterval(2))))
        return shots
    }

    /// A fixed line of `kind`, so snapshots are stable run to run.
    private static func nudge(_ kind: PetCoachNudgeKind, _ lines: [PetCoachMessage]) -> PetCoachNudge {
        PetCoachNudge(kind: kind, message: PetCoachMessages.messages(for: kind, in: lines).last!)
    }

    private static func name(_ kind: PetCoachNudgeKind) -> String {
        switch kind {
        case .distraction: "distraction"
        case .offerPause: "offer-pause"
        case .idleCheck: "idle-check"
        case .autoPause: "auto-pause"
        }
    }

    private static let menuBarHeight: CGFloat = 32
    /// How much of the notch shows left of the overlay.
    private static let notchShown: CGFloat = 92

    private static func scene(_ scene: PetCoachScene, at date: Date) -> AnyView {
        let overhang = PetCoachOverlayView.leadingOverhang(for: scene)
        // Every shot gets a walk's backdrop, so tiny glances match the rest.
        let backdrop = PetCoachOverlayView.size(for: PetCoachStroll(startedAt: date))
        let width = notchShown + backdrop.width + Theme.Spacing.xl
        return AnyView(
            ZStack(alignment: .topLeading) {
                // A stand-in desktop: a mid-gray wallpaper with a light
                // window, so both dark and light backdrops are judged.
                LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                               startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(Color(white: 0.92))
                    .frame(width: width * 0.55, height: 120)
                    .offset(x: width * 0.5, y: menuBarHeight + 28)
                Rectangle()
                    .fill(Color(white: 0.10).opacity(0.85))
                    .frame(height: menuBarHeight)
                UnevenRoundedRectangle(bottomTrailingRadius: Theme.Layout.closedBottomRadius, style: .continuous)
                    .fill(Theme.Palette.background)
                    .frame(width: notchShown, height: menuBarHeight)
                PetCoachOverlayView(scene: scene, date: date) { _ in }
                    .offset(x: notchShown - overhang, y: menuBarHeight)
            }
            .frame(width: width, height: menuBarHeight + backdrop.height + Theme.Spacing.s, alignment: .topLeading)
            .clipped()
        )
    }
}
