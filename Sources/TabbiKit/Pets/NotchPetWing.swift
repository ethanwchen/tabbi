import SwiftUI
import TabbiKitCore

/// The study pet in the closed notch's leading wing: typing on its laptop
/// while the user focuses, sipping coffee on breaks, idling while a session
/// ran recently, and curled up asleep once none has for a while
/// (`PetPresence.sleepAfter`). When a focus session finishes it cheers
/// (`PetCheer`): two happy hops with a few sparkles. When a goal for today
/// is reached it hops once in a tiny crown, which the ticker puts on it.
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
        PetView(player: player, pixelSize: Self.pixelSize)
            .overlay {
                if let cheer = pet.cheer, !reduceMotion, cheer.isShowing(at: .now) {
                    PetCheerSparkles(startedAt: cheer.startedAt)
                        .frame(width: Self.side + 24, height: Self.side + 8)
                        .id(cheer.id)
                }
            }
            // The frame's paws sit on its bottom row and its sides are a few
            // pixels empty, so lift the pet off the notch's bottom edge and
            // line its fur up with the inset the trailing text keeps.
            .offset(x: -3, y: -3)
            .onChange(of: pet.profile) { _, profile in player.update(profile: profile) }
            .onChange(of: pet.mood) { _, mood in
                player.send(.activity(PetAnimator.Activity(mood)))
                player.send(mood == .asleep ? .sleep : .wake)
            }
            .task(id: pet.cheer) { await dance() }
    }

    /// Plays the cheer's hops: two for a dance, one for a crown. The animator lets the celebration finish
    /// before any mood change (the break that just began) takes over.
    private func dance() async {
        guard let cheer = pet.cheer, cheer.isShowing(at: .now) else { return }
        if cheered != cheer.id {
            cheered = cheer.id
            player.send(.celebrate)
        }
        guard cheer.kind == .dance else { return }
        let wait = cheer.startedAt.addingTimeInterval(Self.secondHop).timeIntervalSinceNow
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        player.send(.celebrate)
    }
}
