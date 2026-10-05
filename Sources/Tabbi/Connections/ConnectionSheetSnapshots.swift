import AppKit
import SwiftUI
import TabbiKitCore

extension SnapshotRenderer {
    /// Every Connections walkthrough while it waits, one after it worked,
    /// and every priming screen, so each can be reviewed for clarity.
    static func renderConnectionSheets(to outputDirectory: URL) async {
        var shots: [(String, ConnectionWalkthroughView)] = ConnectionGuide.allCases.map { guide in
            ("connections-guide-\(guide.rawValue)",
             ConnectionWalkthroughView(kind: guide.kind, walkthrough: guide.walkthrough(), light: .notSetUp, isFinished: false,
                                       start: { _ in }, copy: { _ in }, close: {}))
        }
        let done = ConnectionGuide.ankiAddOn
        shots.append(("connections-guide-\(done.rawValue)-connected",
                      ConnectionWalkthroughView(kind: done.kind, walkthrough: done.walkthrough(), light: .notSetUp, isFinished: true,
                                                start: { _ in }, copy: { _ in }, close: {})))
        for (name, view) in shots {
            await write(render(view), named: name, to: outputDirectory)
        }

        let permissions: [(String, ConnectionKind, ConnectionPermission)] = [
            ("calendar", .calendar, .calendar), ("notifications", .notifications, .notifications),
            ("spotify", .spotify, .automation(.spotify)), ("music", .music, .automation(.music)),
        ]
        for (name, kind, permission) in permissions {
            let view = ConnectionPrimingView(kind: kind, priming: permission.priming, proceed: {})
            await write(render(view), named: "connections-priming-\(name)", to: outputDirectory)
        }
    }

    /// Presents the view as a real sheet on an off-screen window and draws
    /// the sheet, so the PNG shows what Settings shows. (The shared
    /// `sheetSnapshot` window resizes to follow its content, which loops
    /// forever on these sheets' wrapped text.)
    private static func render(_ content: some View) async -> Data? {
        let parent = Color.clear.frame(width: 600, height: 560)
            .sheet(isPresented: .constant(true)) { content }
        let window = NSWindow(contentViewController: NSHostingController(rootView: parent))
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .seconds(1))
        guard let sheet = window.attachedSheet, let frameView = sheet.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)
        else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(_ png: Data?, named name: String, to outputDirectory: URL) async {
        guard let png else { return }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print(url.path)
    }
}
