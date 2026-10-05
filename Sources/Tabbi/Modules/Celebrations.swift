import TabbiKit
import TabbiKitCore

extension SharedServices {
    /// The one `CelebrationCenter`, so every module shares its frequency
    /// limits. Snapshot runs celebrate nothing; haptics and sound follow Settings.
    func celebrations(settings: SettingsStore, runMode: RunMode) -> CelebrationCenter {
        resolve {
            CelebrationCenter(isEnabled: !runMode.isSnapshot,
                              hapticsEnabled: { [weak settings] in settings?.settings.hapticsEnabled ?? false },
                              soundEnabled: { [weak settings] in settings?.settings.celebrationSoundEnabled ?? false })
        }
    }
}

extension ModuleContext {
    /// Where a module asks for a celebration of a real event (a finished
    /// focus session, a level up). It plays over the open panel, within the
    /// shared limits in docs/design/motion.md.
    var celebrations: CelebrationCenter { shared.celebrations(settings: settings, runMode: runMode) }
}
