import Combine
import TabbiKit
import TabbiKitCore

extension SharedServices {
    /// The one `CelebrationCenter`, so every module shares its frequency
    /// limits. Snapshot runs celebrate nothing; haptics and sound follow
    /// Settings, and sounds hush while focus mode holds Do Not Disturb.
    func celebrations(settings: SettingsStore, runMode: RunMode) -> CelebrationCenter {
        let focusMode = resolve { FocusController(runMode: runMode) }
        return resolve {
            CelebrationCenter(isEnabled: !runMode.isSnapshot,
                              hapticsEnabled: { [weak settings] in settings?.settings.hapticsEnabled ?? false },
                              soundEnabled: { [weak settings] in settings?.settings.celebrationSoundEnabled ?? false },
                              isHushed: { [weak focusMode] in focusMode?.holdsDoNotDisturb ?? false })
        }
    }
}

extension ModuleContext {
    /// Where a module asks for a celebration of a real event (a finished
    /// focus session, a level up). It plays over the open panel, within the
    /// shared limits in docs/design/motion.md.
    var celebrations: CelebrationCenter { shared.celebrations(settings: settings, runMode: runMode) }
}

/// Puts a tiny crown on the pet beside the closed notch when a goal for
/// today is reached (Anki reviews done, the daily focus time goal met), from
/// the progress every module shares, so no module needs code for it.
@MainActor
final class GoalCrowns {
    private var watch = GoalCompletionWatch()
    private var subscription: AnyCancellable?

    init(providers: ProviderHub, celebrations: CelebrationCenter) {
        subscription = providers.$snapshot
            .map(\.progress)
            .removeDuplicates()
            .sinkOnMainActor { [weak self, weak celebrations] progress in
                guard let self, !watch.reached(in: progress).isEmpty else { return }
                // Reached with a panel open, the crown waits for it to close.
                celebrations?.cheer(.crown, waitsForClose: true)
            }
    }
}
