import SwiftUI
import TabbiKitCore

/// The study pet in the closed notch's leading wing: typing on its laptop
/// while the user focuses, sipping coffee on breaks, idling while a session
/// ran recently, and curled up asleep once none has for a while
/// (`PetPresence.sleepAfter`). When a focus session finishes it cheers
/// (`PetCheer`): two happy hops with a few sparkles. When a goal for today
/// is reached it hops once in a tiny crown, which the ticker puts on it.
/// When the Mac starts charging it hops once and sips from its mug (the
/// ticker shows it on a break), without sparkles. Partway through a long
/// focus block it trots off into the notch on a little adventure
/// (`PetAdventure`), leaving a paw print in its spot, and trots back out as
/// the block ends; under Reduce Motion it stays.
///
/// Owns its own `PetPlayer`, kept for as long as the pet stays on screen,
/// so mood changes play the real fall-asleep and stretch-awake clips
/// instead of cutting between them.
struct NotchPetWing: View {
    let pet: TickerPet

    /// Points per sprite pixel: whole device pixels on 2x displays keep the
    /// art crisp, and the sitting pet (about 25 sprite pixels tall) fits the
    /// 32 pt notch.
    static let pixelSize: CGFloat = 1
    static var side: CGFloat { CGFloat(PetComposer.frameSize) * pixelSize }
    /// When a cheer's second hop starts: as the first one lands.
    static let secondHop: TimeInterval = 1.0

    @StateObject private var player: PetPlayer
    /// The cheer whose first hop has played, so a redraw never restarts it.
    @State private var cheered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(pet: TickerPet) {
        self.pet = pet
        // A wing that appears mid-cheer (the ticker switched to the pet for
        // it) starts the hop at the cheer's start, so it never lags.
        let cheer = pet.cheer.flatMap { $0.isShowing(at: .now) ? $0 : nil }
        _cheered = State(initialValue: cheer?.id)
        _player = StateObject(wrappedValue: {
            let player = PetPlayer(
                profile: pet.profile, asleep: pet.mood == .asleep, activity: PetAnimator.Activity(pet.mood),
                activitySince: pet.moodSince, at: cheer?.startedAt ?? .now)
            if let cheer { player.send(.celebrate, at: cheer.startedAt) }
            return player
        }())
    }

    var body: some View {
        Group {
            if let adventure = pet.adventure, !reduceMotion {
                TimelineView(PetAdventureSchedule(adventure: adventure)) { context in
                    switch adventure.phase(at: context.date) {
                    case .home: home
                    case .away: PetAwayMark()
                    case let phase: walker(phase, adventure: adventure, at: context.date)
                    }
                }
            } else {
                home
            }
        }
        .onChange(of: pet.profile) { _, profile in player.update(profile: profile) }
        .onChange(of: pet.mood) { _, mood in
            player.send(.activity(PetAnimator.Activity(mood)))
            player.send(mood == .asleep ? .sleep : .wake)
        }
        .task(id: pet.cheer) { await dance() }
    }

    /// How far the pet trots toward the notch before it is out of sight.
    static let adventureTravel: CGFloat = 24

    /// Trotting toward the notch (the walk clip faces left, so mirrored) on
    /// the way out, and back out of it facing left, fading with distance.
    private func walker(_ phase: PetAdventure.Phase, adventure: PetAdventure, at date: Date) -> some View {
        let leaving = if case .leaving = phase { true } else { false }
        let start = leaving ? adventure.departsAt : adventure.returnsAt
        let frame = player.clips[.walk].frame(at: date.timeIntervalSince(start))
            .atItemTime(date.timeIntervalSinceReferenceDate)
        // Whole points keep the pixel art crisp as it moves.
        let offset = (phase.distance * Self.adventureTravel).rounded()
        return PetSpriteView(canvas: frame.canvas, palette: player.palette, pixelSize: Self.pixelSize)
            .scaleEffect(x: leaving ? -1 : 1, y: 1)
            .opacity(1 - phase.distance)
            .offset(x: offset - 3, y: -NotchPreviewLayout.petLift)
            .accessibilityLabel(pet.profile.name)
    }

    private var home: some View {
        PetView(player: player, pixelSize: Self.pixelSize)
            .overlay {
                if let cheer = pet.cheer, cheer.kind != .sip, !reduceMotion, cheer.isShowing(at: .now) {
                    PetCheerSparkles(startedAt: cheer.startedAt)
                        .frame(width: Self.side + 24, height: Self.side + 8)
                        .id(cheer.id)
                }
            }
            // The frame's paws sit on its bottom row and its sides are a few
            // pixels empty, so lift the pet off the notch's bottom edge and
            // line its fur up with the inset the trailing text keeps.
            .offset(x: -3, y: -NotchPreviewLayout.petLift)
    }

    /// Plays the cheer's hops: two for a dance, one for a crown or a sip, and only
    /// one with Reduce Motion on. The animator lets the celebration finish
    /// before any mood change (the break that just began) takes over.
    private func dance() async {
        guard let cheer = pet.cheer, cheer.isShowing(at: .now) else { return }
        if cheered != cheer.id {
            cheered = cheer.id
            player.send(.celebrate)
        }
        guard cheer.kind == .dance, !reduceMotion else { return }
        let wait = cheer.startedAt.addingTimeInterval(Self.secondHop).timeIntervalSinceNow
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        player.send(.celebrate)
    }
}

/// Where the pet sits while it is off on an adventure: a faint paw print,
/// so the wing reads as "back soon" rather than empty.
private struct PetAwayMark: View {
    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.Palette.tertiaryText)
            // Where the pet's body sits, centered on the trailing text's line.
            .frame(width: NotchPetWing.side, height: NotchPetWing.side)
            .offset(x: -3)
            .transition(.opacity)
    }
}

/// Redraws only when the adventure changes: at each phase change, and
/// smoothly while the pet walks when `followsWalks` is on.
private struct PetAdventureSchedule: TimelineSchedule {
    let adventure: PetAdventure
    var followsWalks = true
    /// A smooth trot for a three second walk without redrawing every frame.
    static let walkStep: TimeInterval = 1.0 / 30

    func entries(from startDate: Date, mode: Mode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            guard let date = next else { return nil }
            let change = adventure.nextChange(after: date)
            let walking = switch adventure.phase(at: date) {
            case .leaving, .returning: true
            case .home, .away: false
            }
            if walking && followsWalks {
                let step = date.addingTimeInterval(Self.walkStep)
                next = change.map { min($0, step) } ?? step
            } else {
                next = change
            }
            return date
        }
    }
}

/// The pet's name beside the closed notch (one the user chose), with "zzz"
/// while it dozes and "exploring" while it is off on an adventure.
struct NotchPetLabel: View {
    let pet: TickerPet
    /// The pet module's accent, for the unlock hint.
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let adventure = pet.adventure, !reduceMotion {
            // Redrawn only as the pet leaves and comes back; the label goes
            // as it starts back, so its return reads as the finish.
            TimelineView(PetAdventureSchedule(adventure: adventure, followsWalks: false)) { context in
                label(exploring: adventure.isExploring(at: context.date))
            }
        } else {
            label(exploring: false)
        }
    }

    /// One slot beside the name, by priority: dozing ("zzz"), then away on
    /// an adventure ("exploring"), then the unlock hint, which
    /// `TickerPet.unlockHint` already keeps to an awake pet between
    /// sessions, so it never competes with the other two.
    private func label(exploring: Bool) -> some View {
        let state: String? = pet.mood == .asleep ? TickerFormat.petSleeping
            : exploring ? TickerFormat.petExploring : nil
        let unlock = state == nil ? pet.unlockHint : nil
        return HStack(spacing: Theme.Spacing.xs) {
            if let name = TickerFormat.petLabel(pet) {
                Text(name)
                    .foregroundStyle(pet.mood == .asleep ? Theme.Palette.secondaryText : Theme.Palette.primaryText)
                    .truncationMode(.tail)
            }
            if let state {
                Text(state)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize()
                    .transition(.opacity)
            } else if let unlock {
                NotchUnlockHint(fraction: unlock.fraction, tint: accent)
                    .transition(.opacity)
            }
        }
        .previewText()
        .motion(Theme.Motion.content, value: unlock)
        .motion(Theme.Motion.content, value: state)
    }
}
