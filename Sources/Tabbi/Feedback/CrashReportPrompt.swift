import AppKit
import TabbiKitCore

/// The one-time question after a crash: "Tabbi closed unexpectedly. Send a
/// crash report?", with the exact body that would be sent shown below it.
/// A standard alert like the Move to Applications offer, so it reads as a
/// calm system question rather than part of the notch.
@MainActor
enum CrashReportPrompt {
    static let disclosureSize = NSSize(width: 420, height: 140)

    /// Shows the prompt and waits for the answer.
    static func ask(about report: CrashReport) -> CrashReportFlow.Answer {
        let alert = makeAlert(for: report)
        NSApp.activate()
        let response = alert.runModal()
        return CrashReportFlow.Answer(
            choice: response == .alertFirstButtonReturn ? .send : .dontSend,
            dontAskAgain: alert.suppressionButton?.state == .on
        )
    }

    static func makeAlert(for report: CrashReport) -> NSAlert {
        let name = Edition.current.name
        let alert = NSAlert()
        alert.messageText = "\(name) closed unexpectedly. Send a crash report?"
        alert.informativeText = "A report helps fix the problem. It holds the app version, macOS version, edition, the crash stack and thread names, and never your content, names, tasks or tokens. This is exactly what is sent:"
        alert.accessoryView = disclosureView(report.disclosure)
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Don't Send")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.suppressionButton?.toolTip = "Remember this answer and stop asking after a crash"
        return alert
    }

    /// The report body, read-only and selectable, in a small scrolling box.
    private static func disclosureView(_ text: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(origin: .zero, size: disclosureSize)
        scroll.borderType = .bezelBorder
        scroll.hasHorizontalScroller = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textColor = .secondaryLabelColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.string = text
        textView.setAccessibilityLabel("Crash report contents")
        return scroll
    }

    /// The prompt as a PNG, for the snapshot run. The alert's controls only
    /// draw in a window that is on screen, so it is shown far off the visible
    /// desktop for a moment. Caching leaves out the dark translucent backdrop
    /// that light text needs, so the shot uses the light appearance.
    static func snapshot(of report: CrashReport) async -> Data? {
        let alert = makeAlert(for: report)
        let window = alert.window
        window.appearance = NSAppearance(named: .aqua)
        alert.layout()
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(300))
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// A realistic report for the snapshot run and tests: a Swift trap on
    /// the main thread.
    static let sample = CrashReport(
        environment: DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi"),
        kind: .signal,
        name: "SIGTRAP",
        threads: [CrashReport.Thread(name: "main", crashed: true, frames: [
            "0   Tabbi        0x0000000102a1c3f4 $s5Tabbi10TodayStoreC6reloadyyF + 212",
            "1   Tabbi        0x0000000102a1b9e0 $s5Tabbi10TodayStoreC5startyyF + 64",
            "2   SwiftUI      0x00000001c4f2a118 $s7SwiftUI4ViewPAAE6onAppear + 96",
            "3   AppKit       0x000000018d3e2c10 -[NSApplication run] + 476",
            "4   Tabbi        0x0000000102a01e2c main + 88",
            "5   dyld         0x000000018a5c0274 start + 2840",
        ])]
    )!
}
