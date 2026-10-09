import AppKit
import TabbiKitCore

// Tabbi is a menu-bar-less accessory app: no Dock icon, no main window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: RunMode.snapshotFlag) {
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "snapshots"
        let kitFlag = arguments.firstIndex(of: "--kit")
        let kitID = kitFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let themeFlag = arguments.firstIndex(of: "--theme")
        let theme = themeFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let scaleFlag = arguments.firstIndex(of: "--scale")
        let scale = scaleFlag.flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
        var notchStyle = SnapshotRenderer.NotchStyle()
        if let scale, scale > 0 { notchStyle.scale = scale }
        notchStyle.transparent = arguments.contains("--transparent")
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await SnapshotRenderer.run(
                outputDirectory: URL(fileURLWithPath: path),
                kitID: kitID ?? Edition.current.defaultKitID,
                themes: SnapshotRenderer.ThemeSelection(argument: theme),
                notchStyle: notchStyle
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
