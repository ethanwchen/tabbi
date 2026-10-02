import AppKit

// NotchDeck is a menu-bar-less accessory app: no Dock icon, no main window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--snapshot") {
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "snapshots"
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await SnapshotRenderer.run(outputDirectory: URL(fileURLWithPath: path))
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
