import AppKit
import TabbiKitCore

// NotchDeck is a menu-bar-less accessory app: no Dock icon, no main window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: RunMode.snapshotFlag) {
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "snapshots"
        let kitFlag = arguments.firstIndex(of: "--kit")
        let kitID = kitFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await SnapshotRenderer.run(
                outputDirectory: URL(fileURLWithPath: path),
                kitID: kitID ?? Edition.current.defaultKitID
            )
            exit(0)
        }
        app.run()
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
