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
/// `.celebrationStage(_:)` to draw, and taps a light haptic.
@MainActor
public final class CelebrationCenter: ObservableObject {
    /// The latest admitted celebration; stages play it once when it changes.
    @Published public private(set) var current: Celebration?

    private var pacer = CelebrationPacer()
    private var stages = 0
    private let isEnabled: Bool
    private let hapticsEnabled: () -> Bool
    private let now: () -> Date

    /// - Parameters:
    ///   - isEnabled: false for snapshot runs, which play and tap nothing.
    ///   - hapticsEnabled: read at each celebration, so it follows Settings.
    ///   - now: the clock the pacer measures against; tests pass their own.
    public init(isEnabled: Bool = true, hapticsEnabled: @escaping () -> Bool = { true },
                now: @escaping () -> Date = Date.init) {
        self.isEnabled = isEnabled
        self.hapticsEnabled = hapticsEnabled
        self.now = now
    }

    /// True while an open panel can show a celebration.
    public var isShowing: Bool { stages > 0 }

    /// Plays a celebration for a real event if one fits: returns the tier
    /// that plays, or nil when the notch is closed or the pacer says it is
    /// too soon. A caller with a smaller fallback (a symbol bounce) shows it on nil.
    @discardableResult
    public func celebrate(_ tier: CelebrationTier, style: CelebrationStyle, accent: Color) -> CelebrationTier? {
        guard isEnabled, isShowing, let admitted = pacer.admit(tier, at: now()) else { return nil }
        current = Celebration(tier: admitted, style: style, accent: accent, date: now())
        if hapticsEnabled() {
            // Only felt on a Force Touch trackpad with a finger on it.
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        return admitted
    }

    func stageAppeared() { stages += 1 }
    func stageDisappeared() { stages = max(0, stages - 1) }
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
