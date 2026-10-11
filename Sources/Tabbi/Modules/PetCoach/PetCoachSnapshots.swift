import SwiftUI
import TabbiKitCore
import TabbiKit

/// Frozen coach overlay moments for `--snapshot`, each drawn in place below
/// a stand-in menu bar and the notch's right half, so the review shows how
/// the pet sits against the real screen edge.
@MainActor
enum PetCoachSnapshots {
    /// (file name, view) for every overlay state worth reviewing.
    /// Bubbles use the last line of each kind in `lines`, which is the
    /// active kit's own line when it has one. `transparent` leaves out the
    /// stand-in desktop and menu bar (the notch stays), for marketing images
    /// that draw their own.
    static func shots(profile: PetProfile, lines: [PetCoachMessage], transparent: Bool = false) -> [(String, AnyView)] {
        let frozen = { (scene: PetCoachScene, date: Date) in self.scene(scene, at: date, transparent: transparent) }
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stroll = PetCoachStroll(startedAt: start)
        var shots: [(String, AnyView)] = []
        // Mid-trot on the way out, before the bubble.
        // The silent look: halfway down, then hanging and looking.
        let glance = PetCoachScene(profile: profile, glanceAt: start)
        if case .glance(let timing) = glance.line {
            shots.append(("coach-glance-lowering", frozen(glance, start.addingTimeInterval(timing.enter * 0.12))))
            shots.append(("coach-glance", frozen(glance, start.addingTimeInterval(timing.enter + 1))))
        }
        let walking = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(.distraction, lines))
        shots.append(("coach-walking", frozen(walking, start.addingTimeInterval(stroll.walkDuration * 0.6))))
        // One talking shot per bubble kind, after the arrival hop.
        let talking = stroll.arrivesAt.addingTimeInterval(3)
        for kind in PetCoachNudgeKind.allCases {
            let kindScene = PetCoachScene(profile: profile, stroll: stroll, nudge: nudge(kind, lines))
            shots.append(("coach-\(name(kind))", frozen(kindScene, talking)))
        }
        // The end-of-session moment: mid-hop with the heart up, then the
        // settled bubble with the bar toward the next unlock, one where the
        // session made an item affordable, and one with nothing left to unlock.
        let party = PetCoachStroll(startedAt: start, talkDuration: PetCoach.celebrationDuration)
        let session = PetStudyAward(completedSessions: 1, minutes: 25, points: 35)
        // The demo pet wears the glasses, so they are owned and the bar aims at the next item.
        let toNext = UnlockProgress(balance: 40, earned: 35,
                                    ledger: PetPointsLedger(purchased: [.accessory(.beanie), .accessory(.roundGlasses)]))
        let done = PetCoachScene(profile: profile, stroll: party, line: .celebration(session, progress: toNext))
        shots.append(("coach-celebrate", frozen(done, party.arrivesAt.addingTimeInterval(0.3))))
        shots.append(("coach-session-end", frozen(done, party.arrivesAt.addingTimeInterval(2))))
        let levelUp = PetCoachScene(profile: profile, stroll: party, line: .celebration(
            session, progress: UnlockProgress(balance: 40, earned: 35, ledger: PetPointsLedger())))
        shots.append(("coach-level-up", frozen(levelUp, party.arrivesAt.addingTimeInterval(2))))
        let allOwned = PetStudyAward(completedSessions: 1, minutes: 50, points: 60)
        let complete = PetCoachScene(profile: profile, stroll: party, line: .celebration(allOwned, progress: nil))
        shots.append(("coach-session-end-all-owned", frozen(complete, party.arrivesAt.addingTimeInterval(2))))
        // A surprise gift under the bar: bonus points, a rare fur, and the
        // longest gift the pet carries home from an adventure.
        let returned = PetJournal.Entry(line: "leaf", date: party.arrivesAt, gift: .rareFur(RareFur.all[3]))
        let gifts: [(String, SurpriseGiftDelivery)] = [
            ("coach-gift", SurpriseGiftDelivery(gift: .bonusPoints(15), date: party.arrivesAt)),
            ("coach-gift-fur", SurpriseGiftDelivery(gift: .rareFur(RareFur.all[0]), date: party.arrivesAt)),
            ("coach-gift-adventure", SurpriseGiftDelivery(gift: .rareFur(RareFur.all[3]), date: party.arrivesAt,
                                                          adventure: returned)),
        ]
        for (name, gift) in gifts {
            let line = PetCoachScene(profile: profile, stroll: party,
                                     line: .celebration(session, progress: toNext, gift: gift))
            shots.append((name, frozen(line, party.arrivesAt.addingTimeInterval(2))))
        }
        // Cat wisdom after the celebration: an ordinary day's line, and the
        // longest comeback and milestone lines, to check three lines fit.
        let wisdoms: [(String, CatWisdomLine)] = [
            ("coach-wisdom", CatWisdomLine(kind: .firstOfDay, text: CatWisdom.daily[1])),
            ("coach-wisdom-comeback", CatWisdomLine(kind: .comeback, text: CatWisdom.comeback[1])),
            ("coach-wisdom-milestone", CatWisdomLine(kind: .milestone(.lastSquare), text: CatWisdomMilestone.lastSquare.line)),
        ]
        for (name, wisdom) in wisdoms + (ProcessInfo.processInfo.environment["TABBI_WISDOM_ALL"] == nil ? [] : allWisdom) {
            let line = PetCoachLine.celebration(session, progress: toNext, wisdom: wisdom)
            let talk = PetCoachStroll(startedAt: start, talkDuration: line.talkDuration)
            let shown = PetCoachScene(profile: profile, stroll: talk, line: line)
            shots.append((name, frozen(shown, talk.arrivesAt.addingTimeInterval(PetCoach.celebrationDuration + 1))))
        }
        return shots
    }

    /// Every Cat wisdom line, rendered only with `TABBI_WISDOM_ALL=1` to
    /// check that each fits the bubble in three lines.
    private static var allWisdom: [(String, CatWisdomLine)] {
        let pools = CatWisdom.daily + CatWisdom.comeback + [CatWisdom.earlyStop, CatWisdom.lateNight]
            + CatWisdomMilestone.allCases.map(\.line)
        return pools.enumerated().map { ("coach-wisdom-all-\($0.offset)", CatWisdomLine(kind: .firstOfDay, text: $0.element)) }
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

    private static func scene(_ scene: PetCoachScene, at date: Date, transparent: Bool) -> AnyView {
        let overhang = PetCoachOverlayView.leadingOverhang(for: scene)
        // Every shot gets a walk's backdrop, so tiny glances match the rest.
        let backdrop = PetCoachOverlayView.size(for: PetCoachStroll(startedAt: date))
        let width = notchShown + backdrop.width + Theme.Spacing.xl
        return AnyView(
            ZStack(alignment: .topLeading) {
                if !transparent {
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
                }
                UnevenRoundedRectangle(bottomTrailingRadius: Theme.Layout.closedBottomRadius, style: .continuous)
                    .fill(Theme.Palette.background)
                    .frame(width: notchShown, height: menuBarHeight)
                PetCoachOverlayView(scene: scene, date: date) { _ in }
                    .offset(x: notchShown - overhang, y: menuBarHeight)
            }
            .frame(width: width, height: menuBarHeight + backdrop.height + Theme.Spacing.s, alignment: .topLeading)
            .clipped()
            // The screen itself doesn't mirror: the notch stays where the camera is.
            .fixedLeftToRight()
        )
    }
}
