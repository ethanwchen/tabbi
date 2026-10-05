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
/// `.celebrationStage(_:)` to draw, and taps a light haptic. When the pacer
/// says no while a panel is open, the event still gets the smallest tier: a
/// `CelebrationNod` that bounces its module's tab.
@MainActor
public final class CelebrationCenter: ObservableObject {
    /// The latest admitted celebration; stages play it once when it changes.
    @Published public private(set) var current: Celebration?
    /// The latest symbol-bounce fallback; the tab bar bounces a tab when it changes.
    @Published public private(set) var nod: CelebrationNod?

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
    /// too soon. When it is too soon and `source` is given, the event nods
    /// instead: that module's tab bounces once, with no particles or haptic.
    @discardableResult
    public func celebrate(_ tier: CelebrationTier, style: CelebrationStyle, accent: Color,
                          from source: ModuleID? = nil) -> CelebrationTier? {
        guard isEnabled, isShowing else { return nil }
        guard let admitted = pacer.admit(tier, at: now()) else {
            if let source { nod = CelebrationNod(id: (nod?.id ?? 0) + 1, source: source) }
            return nil
        }
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
