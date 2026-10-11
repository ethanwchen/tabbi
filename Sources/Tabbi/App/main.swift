import AppKit
import TabbiKitCore

// Tabbi is a menu-bar-less accessory app: no Dock icon, no main window.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: L10n.localeFlag), arguments.indices.contains(flag + 1) {
        L10n.use(language: arguments[flag + 1])
    }
    if let flag = arguments.firstIndex(of: PreviewRecorder.flag) {
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "preview-frames"
        let partFlag = arguments.firstIndex(of: "--part")
        let part = partFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "opening"
        let tabsFlag = arguments.firstIndex(of: "--tabs")
        let tabs = tabsFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .flatMap { ModuleLayout(enablingList: $0, catalog: ModuleList.catalog(for: .current)) }
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await PreviewRecorder.run(outputDirectory: URL(fileURLWithPath: path), part: part,
                                      kitID: Edition.current.defaultKitID, tabs: tabs)
            exit(0)
        }
        app.run()
    } else if let flag = arguments.firstIndex(of: RunMode.snapshotFlag) {
        let path = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : "snapshots"
        let kitFlag = arguments.firstIndex(of: "--kit")
        let kitID = kitFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let themeFlag = arguments.firstIndex(of: "--theme")
        let theme = themeFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let scaleFlag = arguments.firstIndex(of: "--scale")
        let scale = scaleFlag.flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
        let tabsFlag = arguments.firstIndex(of: "--tabs")
        let tabs = tabsFlag.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            .flatMap { ModuleLayout(enablingList: $0, catalog: ModuleList.catalog(for: .current)) }
        var notchStyle = SnapshotRenderer.NotchStyle()
        if let scale, scale > 0 { notchStyle.scale = scale }
        notchStyle.transparent = arguments.contains("--transparent")
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await SnapshotRenderer.run(
                outputDirectory: URL(fileURLWithPath: path),
                kitID: kitID ?? Edition.current.defaultKitID,
                tabs: tabs,
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
