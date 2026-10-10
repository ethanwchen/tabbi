import Foundation
import IOKit.ps
import TabbiKit
import TabbiKitCore

/// Has the pet beside the closed notch sip from its mug when the Mac starts
/// charging (`PetCheer.Kind.sip`), at most once per plug-in
/// (`ChargingWatch`) and never while Do Not Disturb is on.
///
/// Follows the public IOKit power source notifications, which need no
/// entitlement and work in the sandbox. macOS plays its own charging chime,
/// so the cheer adds no sound. Snapshot runs watch nothing.
@MainActor
final class ChargingCheer {
    private var watch = ChargingWatch()
    private weak var celebrations: CelebrationCenter?
    private var source: CFRunLoopSource?

    init(celebrations: CelebrationCenter, runMode: RunMode) {
        self.celebrations = celebrations
        guard !runMode.isSnapshot else { return }
        _ = watch.update(onCharger: Self.isOnCharger(), at: Date())
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            // Delivered on the main run loop, where the source was added.
            MainActor.assumeIsolated {
                Unmanaged<ChargingCheer>.fromOpaque(context).takeUnretainedValue().powerChanged()
            }
        }, context)?.takeRetainedValue() else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    isolated deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func powerChanged() {
        guard watch.update(onCharger: Self.isOnCharger(), at: Date()),
              let celebrations, !celebrations.isDoNotDisturbOn else { return }
        celebrations.cheer(.sip, hasOwnSound: true)
    }

    /// Whether a charger powers the Mac now; nil when IOKit can't tell.
    private static func isOnCharger() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return nil }
        return (type as String) == kIOPMACPowerKey
    }
}
