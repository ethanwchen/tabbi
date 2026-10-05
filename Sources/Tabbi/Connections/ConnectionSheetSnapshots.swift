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

        let checkups: [(String, ConnectionDiagnosis)] = [
            ("anki-closed", AnkiConnectionState.notRunning.diagnosis),
            ("anki-addon", AnkiConnectionState.addOnMissing.diagnosis),
            ("calendar-connected", CalendarConnectionState(access: .fullAccess, accounts: ["iCloud"]).diagnosis),
            ("calendar-denied", CalendarConnectionState(access: .denied).diagnosis),
            ("claude-missing", ClaudeConnectionState.notInstalled.diagnosis),
            ("spotify-denied", MusicConnectionState(app: .spotify, isInstalled: true, permission: .denied).diagnosis),
            ("dnd-one-left", FocusShortcutsState(onName: FocusSettings.suggestedOnShortcut,
                                                 offName: FocusSettings.suggestedOffShortcut,
                                                 installed: [FocusSettings.suggestedOnShortcut]).diagnosis),
        ]
        for (name, diagnosis) in checkups {
            let view = ConnectionTroubleshootView(kind: diagnosis.kind, diagnosis: diagnosis, isChecking: false,
                                                  perform: { _ in }, checkAgain: {}, copyDetails: {}, close: {})
            await write(render(view), named: "connections-checkup-\(name)", to: outputDirectory)
        }

        for kind in ConnectionKind.allCases {
            await write(renderStates(of: kind), named: "connections-states-\(kind.rawValue)", to: outputDirectory)
        }
    }

    /// Every state of one row as Settings draws it, each under its
    /// support label, so the whole path from missing to connected can be
    /// read at once. (The Settings pane PNG only shows the first screenful.)
    private static func renderStates(of kind: ConnectionKind) async -> Data? {
        // A stack sized to its content, styled like the grouped Form, since
        // a Form scrolls and would clip whatever doesn't fit.
        let gallery = VStack(alignment: .leading, spacing: 16) {
            ForEach(kind.everyState, id: \.technical) { state in
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.technical)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                    ConnectionRow(kind: kind, status: state.status, perform: { _ in }, troubleshoot: {})
                        .padding(10)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(20)
        // The width of the Settings pane, so rows wrap as they do there.
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: gallery)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(500))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
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
