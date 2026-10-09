import AppKit
import SwiftUI
import TabbiKitCore

/// The one place real events ask for a celebration, so every module shares
/// the same frequency limits and the burst plays where the user can see it.
///
/// A module calls `celebrate(_:style:accent:)` when something worth it
/// happens (a focus session finished, a level up). The center plays nothing
/// while no stage is on screen (the notch is closed), so an unseen event
/// never uses up the `CelebrationPacer`'s allowance; otherwise it asks the
/// pacer for a tier, publishes the `Celebration` for the open panel's
/// `.celebrationStage(_:)` to draw, taps a light haptic and, when Settings
/// allow it, plays a soft `CelebrationSound`. When the pacer
/// says no while a panel is open, the event still gets the smallest tier: a
/// `CelebrationNod` that bounces its module's tab.
///
/// With the notch closed, a finished focus session can still `cheer(_:)`:
/// the pet beside the closed notch dances for a moment (`PetCheer`), which
/// the ticker shows in place of whatever it was showing. A goal reached
/// while a panel is open waits for the notch to close, so its crown is
/// still seen.
@MainActor
public final class CelebrationCenter: ObservableObject {
    /// The latest admitted celebration; stages play it once when it changes.
    @Published public private(set) var current: Celebration?
    /// The latest symbol-bounce fallback; the tab bar bounces a tab when it changes.
    @Published public private(set) var nod: CelebrationNod?
    /// The latest pet cheer for the closed notch; the ticker shows it while
    /// `PetCheer.isShowing(at:)`.
    @Published public private(set) var cheer: PetCheer?

    private var pacer = CelebrationPacer()
    private var stages = 0
    /// A cheer asked for while a panel was open, played once it closes.
    private var waiting: (kind: PetCheer.Kind, since: Date)?
    /// How long a waiting cheer stays worth playing: a goal reached an
    /// hour before the panel closed is old news.
    static let waitLimit: TimeInterval = 10 * 60
    private let isEnabled: Bool
    private let hapticsEnabled: () -> Bool
    private let soundEnabled: () -> Bool
    private let playSound: @MainActor (CelebrationSound) -> Void
    private let now: () -> Date

    /// - Parameters:
    ///   - isEnabled: false for snapshot runs, which play and tap nothing.
    ///   - hapticsEnabled: read at each celebration, so it follows Settings.
    ///   - soundEnabled: read at each celebration, so it follows Settings.
    ///   - playSound: plays a cue; tests pass their own to hear nothing.
    ///   - now: the clock the pacer measures against; tests pass their own.
    public init(isEnabled: Bool = true, hapticsEnabled: @escaping () -> Bool = { true },
                soundEnabled: @escaping () -> Bool = { false },
                playSound: @escaping @MainActor (CelebrationSound) -> Void = CelebrationCenter.play,
                now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.hapticsEnabled = hapticsEnabled
        self.soundEnabled = soundEnabled
        self.playSound = playSound
        self.now = now
    }

    /// True while an open panel can show a celebration.
    public var isShowing: Bool { stages > 0 }

    /// Plays a celebration for a real event if one fits: returns the tier
    /// that plays, or nil when the notch is closed or the pacer says it is
    /// too soon. When it is too soon and `source` is given, the event nods
    /// instead: that module's tab bounces once, with no particles, haptic or
    /// sound. Pass `hasOwnSound` when the event already played a sound (the
    /// Pomodoro's chime), so the two never stack.
    @discardableResult
    public func celebrate(_ tier: CelebrationTier, style: CelebrationStyle, accent: Color,
                          from source: ModuleID? = nil, hasOwnSound: Bool = false) -> CelebrationTier? {
        guard isEnabled, isShowing else { return nil }
        guard let admitted = pacer.admit(tier, at: now()) else {
            if let source { nod = CelebrationNod(id: (nod?.id ?? 0) + 1, source: source) }
            return nil
        }
        current = Celebration(tier: admitted, style: style, accent: accent, date: now())
        tapHaptic()
        if let sound = CelebrationSound.cue(for: admitted, isEnabled: soundEnabled(), eventHasSound: hasOwnSound) {
            playSound(sound)
        }
        return admitted
    }

    /// Has the pet beside the closed notch cheer for a real event, with a
    /// light haptic and, when Settings allow it and the event played no
    /// sound of its own, a soft sound. Returns the cheer, or nil in a
    /// snapshot run and while an open panel is showing (that panel gets
    /// `celebrate` instead). With `waitsForClose`, a cheer asked for while
    /// a panel is open plays when the notch closes, within `waitLimit`.
    /// Not paced: the events that cheer (a finished focus session, a goal
    /// reached) are already minutes apart.
    @discardableResult
    public func cheer(_ kind: PetCheer.Kind, hasOwnSound: Bool = false, waitsForClose: Bool = false) -> PetCheer? {
        guard isEnabled else { return nil }
        guard !isShowing else {
            if waitsForClose { waiting = (kind, now()) }
            return nil
        }
        waiting = nil
        let cheer = PetCheer(kind: kind, id: (self.cheer?.id ?? 0) + 1, startedAt: now())
        self.cheer = cheer
        tapHaptic()
        if let sound = CelebrationSound.cue(for: .burst, isEnabled: soundEnabled(), eventHasSound: hasOwnSound) {
            playSound(sound)
        }
        return cheer
    }

    private func tapHaptic() {
        guard hapticsEnabled() else { return }
        // Only felt on a Force Touch trackpad with a finger on it.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Plays `sound` as a quiet macOS system sound.
    public static func play(_ sound: CelebrationSound) {
        // A fresh copy, so a second celebration never cuts the first one off.
        guard let player = NSSound(named: sound.name)?.copy() as? NSSound else { return }
        player.volume = sound.volume
        player.play()
    }

    func stageAppeared() { stages += 1 }
    func stageDisappeared() {
        stages = max(0, stages - 1)
        guard stages == 0, waiting != nil else { return }
        // On the next turn, so switching tabs (one stage leaving as the
        // next arrives) never counts as the notch closing.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.playWaitingCheer() }
        }
    }

    private func playWaitingCheer() {
        guard !isShowing, let waiting else { return }
        self.waiting = nil
        guard now().timeIntervalSince(waiting.since) < Self.waitLimit else { return }
        cheer(waiting.kind)
    }
}

/// The smallest celebration tier: one bounce of the tab of the module whose
/// event it was, for when a burst would come too soon after the last one.
public struct CelebrationNod: Equatable, Sendable {
    /// Grows with each nod, so two nods from one module are still two changes.
    public let id: Int
    public let source: ModuleID

    public init(id: Int, source: ModuleID) {
        self.id = id
        self.source = source
    }

    /// The tab that bounces: the source module's, or the open one when the
    /// source has no tab (Today showing the Focus timer with Focus off).
    public func tab(enabled: [ModuleID], selected: ModuleID) -> ModuleID {
        enabled.contains(source) ? source : selected
    }
}

public extension View {
    /// Makes this view (an open notch panel) the place `center`'s
    /// celebrations play, and tells the center it can be seen while it is
    /// on screen.
    func celebrationStage(_ center: CelebrationCenter) -> some View {
        modifier(CelebrationStage(center: center))
    }
}

private struct CelebrationStage: ViewModifier {
    @ObservedObject var center: CelebrationCenter

    func body(content: Content) -> some View {
        content
            .celebration(center.current)
            .onAppear { center.stageAppeared() }
            .onDisappear { center.stageDisappeared() }
    }
}
