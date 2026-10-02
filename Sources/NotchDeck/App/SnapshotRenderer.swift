import AppKit
import SwiftUI
import NotchKitCore

/// Renders every notch state and Settings pane to PNG without showing a window:
///
///     swift run NotchDeck --snapshot ./snapshots
///
/// Used to review UI changes (by people and by agents) without Screen
/// Recording permission. Live data sources run as usual, so panels show
/// whatever state they reach within `settle` seconds.
@MainActor
enum SnapshotRenderer {
    static func run(outputDirectory: URL, settle: TimeInterval = 1.5) async {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let services = AppServices(settings: .ephemeral())
        // 14"/16" MacBook Pro notch.
        let geometry = NotchGeometry(
            notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864
        )
        try? await Task.sleep(for: .seconds(settle))

        var shots: [(String, NotchViewModel)] = []
        let closed = NotchViewModel(geometry: geometry)
        closed.preview = services.ticker.item
        shots.append(("closed", closed))
        // One closed shot per preview kind that has data. Demo usage sits
        // below the 80% threshold, so demo mode fills that one in.
        let now = Date()
        let isDemo = ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1"
        for kind in TickerKind.allCases {
            let live = services.ticker.sources.items(at: now, enabled: [kind]).first
            let demoUsage: TickerItem? = isDemo && kind == .claudeUsage
                ? .claudeUsage(window: .fiveHour, utilization: 0.86) : nil
            guard let item = live ?? demoUsage else { continue }
            let model = NotchViewModel(geometry: geometry)
            model.preview = item
            shots.append(("closed-\(snapshotName(kind))", model))
        }
        for module in ModuleCatalog.builtIn.ids {
            let model = NotchViewModel(geometry: geometry)
            model.open(module)
            shots.append(("open-\(module.rawValue)", model))
        }

        for (name, model) in shots {
            let view = NotchView()
                .environmentObject(model)
                .environmentObject(services)
                .frame(width: Theme.Layout.expandedSize.width + 40,
                       height: Theme.Layout.expandedSize.height + 24, alignment: .top)
                .background(Color(white: 0.16)) // stand-in for a desktop
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            let url = outputDirectory.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            print(url.path)
        }

        let settingsWindow = SettingsWindowController(settings: services.settings)
        for pane in SettingsWindowController.Pane.allCases {
            guard let png = await settingsWindow.snapshot(of: pane) else { continue }
            let url = outputDirectory.appendingPathComponent("settings-\(pane.rawValue).png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    private static func snapshotName(_ kind: TickerKind) -> String {
        switch kind {
        case .meeting: "meeting"
        case .nowPlaying: "music"
        case .focus: "focus"
        case .tasks: "tasks"
        case .claudeUsage: "usage"
        }
    }
}
