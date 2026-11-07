import SwiftUI
import TabbiKitCore

/// The study pet, animated by TabbiKitCore's `PetAnimator` as on the Mac:
/// it types on its laptop through a focus block, sips coffee on a break,
/// idles with blinks between sessions and hops with a heart when a block is
/// done. Every frame is drawn by the shared `PetRenderer` at whole device
/// pixels (`PixelPet`). Under Reduce Motion it holds still poses and only
/// changes with the session.
struct PetStage: View {
    let profile: PetProfile
    let activity: PetAnimator.Activity
    /// Bumped to play the celebration.
    let celebrations: Int
    var pixelSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: Player?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let frame = frame(at: context.date)
            PixelPet(canvas: frame?.canvas ?? profile.sittingCanvas(), palette: profile.palette, pixelSize: pixelSize)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: profile.name))
        .onAppear { reset() }
        .onChange(of: profile) { reset() }
        .onChange(of: activity) { send(.activity(activity)) }
        .onChange(of: celebrations) { send(.celebrate) }
    }

    /// One animator and its clips; a reference so the timeline can advance
    /// it while drawing without a state change per frame.
    private final class Player {
        let clips: PetClipSet
        var animator: PetAnimator

        init(profile: PetProfile, activity: PetAnimator.Activity, at time: TimeInterval) {
            clips = PetClipSet.cached(profile: profile)
            animator = PetAnimator(durations: clips.durations, activity: activity, at: time,
                                   seed: UInt64(truncatingIfNeeded: profile.name.hashValue))
        }
    }

    private func reset() {
        player = Player(profile: profile, activity: activity, at: Self.clock(Date()))
    }

    private func send(_ event: PetAnimator.Event) {
        player?.animator.send(event, at: Self.clock(Date()))
    }

    private func frame(at date: Date) -> PetFrame? {
        guard let player else { return nil }
        let time = Self.clock(date)
        player.animator.advance(to: time)
        return reduceMotion ? player.clips.stillFrame(for: player.animator)
            : player.clips.frame(for: player.animator.playback, at: time)
    }

    /// Seconds on the animator's clock.
    private static func clock(_ date: Date) -> TimeInterval { date.timeIntervalSinceReferenceDate }
}

extension PetAnimator.Activity {
    /// What the pet does for `session`: study along with focus (and
    /// review), rest on a break, and idle when nothing runs.
    init(_ session: StudySession) {
        switch (session.runState, session.phase.isBreak) {
        case (.running, false): self = .studying
        case (.running, true): self = .onBreak
        default: self = .free
        }
    }
}
