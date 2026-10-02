import SwiftUI
import NotchKitCore
import NotchKit

/// Frozen coach overlay moments for `--snapshot`, each drawn in place below
/// a stand-in menu bar and the notch's right half, so the review shows how
/// the pet sits against the real screen edge.
@MainActor
enum PetCoachSnapshots {
    /// (file name, view) for every overlay state worth reviewing.
    static func shots(profile: PetProfile) -> [(String, AnyView)] {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stroll = PetCoachStroll(startedAt: start)
        var shots: [(String, AnyView)] = []
        // Mid-trot on the way out, before the bubble.
        let walking = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(.distraction))
        shots.append(("coach-walking", scene(walking, at: start.addingTimeInterval(stroll.walkDuration * 0.6))))
        // One talking shot per bubble kind, after the arrival hop.
        let talking = stroll.arrivesAt.addingTimeInterval(3)
        for kind in PetCoachNudgeKind.allCases {
            let scene = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(kind))
            shots.append(("coach-\(name(kind))", self.scene(scene, at: talking)))
        }
        return shots
    }

    /// The first line of `kind`, so snapshots are stable run to run.
    private static func nudge(_ kind: PetCoachNudgeKind) -> PetCoachNudge {
        let message = PetCoachMessages.all.first { $0.kind == kind }
            ?? PetCoachMessage(id: "snapshot", kind: kind, text: "Back to it?")
        return PetCoachNudge(kind: kind, message: message)
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
        let overlay = PetCoachOverlayView.size(for: scene.stroll)
        let width = notchShown + overlay.width + Theme.Spacing.xl
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
                    .offset(x: notchShown, y: menuBarHeight)
            }
            .frame(width: width, height: menuBarHeight + overlay.height + Theme.Spacing.s, alignment: .topLeading)
            .clipped()
        )
    }
}
