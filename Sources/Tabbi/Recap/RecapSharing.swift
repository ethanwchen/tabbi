import AppKit
import SwiftUI
import TabbiKit
import TabbiKitCore

/// Exports a weekly recap as a PNG in either shape: through the share
/// sheet (Messages, AirDrop, Photos and the like) or to a file the user
/// picks with Save.
@MainActor
enum RecapSharing {
    /// Where shared images wait for the service that sends them. macOS
    /// clears the temporary folder on its own.
    static var shareFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Tabbi Recap", isDirectory: true)
    }

    /// Draws `recap` in `format` and writes it into `folder` under the
    /// format's file name, replacing an earlier export of the same week.
    static func writeImage(recap: WeeklyRecap, cheer: RecapCheer, pet: PetProfile?,
                           format: RecapShareFormat, into folder: URL) throws -> URL {
        let image = RecapShareImage(recap: recap, cheer: cheer, pet: pet, format: format)
        guard let png = image.png() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(format.fileName(for: recap.week))
        try png.write(to: url, options: .atomic)
        return url
    }

    /// Shows the share sheet for the image, pointing at `anchor`.
    static func share(recap: WeeklyRecap, cheer: RecapCheer, pet: PetProfile?,
                      format: RecapShareFormat, from anchor: NSView) {
        guard let url = try? writeImage(recap: recap, cheer: cheer, pet: pet, format: format,
                                        into: shareFolder) else { return NSSound.beep() }
        NSSharingServicePicker(items: [url])
            .show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// Asks where to save the image, then writes it there.
    static func save(recap: WeeklyRecap, cheer: RecapCheer, pet: PetProfile?, format: RecapShareFormat) {
        let panel = NSSavePanel()
        panel.title = "Save Your Week"
        panel.prompt = "Save"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = format.fileName(for: recap.week)
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let image = RecapShareImage(recap: recap, cheer: cheer, pet: pet, format: format)
        do {
            guard let png = image.png() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// The header's share button: a menu with the share sheet or Save for each
/// shape of the image.
struct RecapShareButton: View {
    let recap: WeeklyRecap
    let cheer: RecapCheer
    @Environment(\.statusPet) private var pet
    @State private var anchor = RecapShareAnchor()

    var body: some View {
        IconButton(symbol: "square.and.arrow.up", size: 22, help: "Share your week as an image") {
            showMenu()
        }
        .background(RecapShareAnchorView(anchor: anchor))
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        for format in RecapShareFormat.allCases {
            menu.addItem(RecapMenuItem(title: "Share \(format.title)") { [recap, cheer, pet] in
                RecapSharing.share(recap: recap, cheer: cheer, pet: pet, format: format, from: view)
            })
        }
        menu.addItem(.separator())
        for format in RecapShareFormat.allCases {
            menu.addItem(RecapMenuItem(title: "Save \(format.title)...") { [recap, cheer, pet] in
                RecapSharing.save(recap: recap, cheer: cheer, pet: pet, format: format)
            })
        }
        // Just under the button; the view isn't flipped, so below is negative.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -Theme.Spacing.xs), in: view)
    }
}

/// The share button's AppKit view, so the menu and the share sheet have
/// something to point at.
@MainActor
final class RecapShareAnchor {
    weak var view: NSView?
}

private struct RecapShareAnchorView: NSViewRepresentable {
    let anchor: RecapShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}

/// A menu item that runs a closure, after the menu has closed.
private final class RecapMenuItem: NSMenuItem {
    private let run: @MainActor @Sendable () -> Void

    init(title: String, run: @escaping @MainActor @Sendable () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func runAction() {
        // The menu is still tracking here; a share sheet or a save panel
        // opens cleanly once it is gone.
        Task { @MainActor [run] in run() }
    }
}
