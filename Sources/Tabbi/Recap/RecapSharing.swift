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

    /// Shows the share sheet for the image, pointing at `rect` in `view`.
    static func share(recap: WeeklyRecap, cheer: RecapCheer, pet: PetProfile?,
                      format: RecapShareFormat, from rect: NSRect, in view: NSView) {
        guard let url = try? writeImage(recap: recap, cheer: cheer, pet: pet, format: format,
                                        into: shareFolder) else { return NSSound.beep() }
        NSSharingServicePicker(items: [url])
            .show(relativeTo: rect, of: view, preferredEdge: .minY)
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

    var body: some View {
        IconButton(symbol: "square.and.arrow.up", size: 22, help: "Share your week as an image") {
            showMenu()
        }
    }

    /// Opens the menu where the click landed, so it needs no AppKit view
    /// of its own (which would also draw as a placeholder in snapshots).
    private func showMenu() {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let click = view.convert(event.locationInWindow, from: nil)
        let below = view.isFlipped ? Theme.Spacing.m : -Theme.Spacing.m
        let anchor = NSRect(x: click.x - Theme.Spacing.m, y: click.y - Theme.Spacing.m,
                            width: Theme.Spacing.m * 2, height: Theme.Spacing.m * 2)
        let menu = NSMenu()
        for format in RecapShareFormat.allCases {
            menu.addItem(RecapMenuItem(title: "Share \(format.title)") { [recap, cheer, pet] in
                RecapSharing.share(recap: recap, cheer: cheer, pet: pet, format: format, from: anchor, in: view)
            })
        }
        menu.addItem(.separator())
        for format in RecapShareFormat.allCases {
            menu.addItem(RecapMenuItem(title: "Save \(format.title)...") { [recap, cheer, pet] in
                RecapSharing.save(recap: recap, cheer: cheer, pet: pet, format: format)
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: click.x, y: click.y + below), in: view)
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
