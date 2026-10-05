import AppKit
import TabbiKitCore

/// Moves the running app into an Applications folder and opens the copy.
///
/// A small in-house take on LetsMove: it copies rather than moves (the
/// original may sit on a read-only disk image or in a translocated mirror),
/// clears the quarantine flag on the copy so Gatekeeper does not translocate
/// it again, then hands the relaunch to a tiny shell that waits for this
/// process to exit. Waiting matters twice: the copy must not see this
/// process as "another copy running", and a disk image can only be ejected
/// once nothing runs from it.
@MainActor
enum AppMover {
    enum Failure: LocalizedError {
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .copyFailed(let reason): "\(Edition.current.name) could not be copied to Applications. \(reason)"
            }
        }
    }

    /// Asks once whether to move, and moves when the user agrees.
    /// - Returns: true when the copy will open and this process must quit.
    static func offerMove(location: InstallLocation, record: inout InstallRecord) -> Bool {
        let name = Edition.current.name
        let alert = NSAlert()
        alert.messageText = "Move \(name) to your Applications folder?"
        alert.informativeText = "\(name) works best from Applications, where it can open when you log in and keep itself up to date. It copies itself there and opens again."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate()
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            record.neverOfferMove = true
        }
        guard response == .alertFirstButtonReturn else { return false }
        do {
            try move(from: Bundle.main.bundleURL, location: location)
            return true
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            return false
        }
    }

    private static func move(from source: URL, location: InstallLocation) throws {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let systemFolder = InstallHygienePlan.destinationFolder(
            home: home, systemApplicationsIsWritable: fileManager.isWritableFile(atPath: "/Applications"))
        var folders = [systemFolder]
        let userFolder = InstallHygienePlan.destinationFolder(home: home, systemApplicationsIsWritable: false)
        if systemFolder != userFolder { folders.append(userFolder) }

        var lastError: Error?
        for folder in folders {
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try replace(destination, with: source)
                clearQuarantine(at: destination)
                relaunch(destination, ejecting: originalURL(of: source, location: location).flatMap(InstallLocation.volume(of:)))
                return
            } catch {
                lastError = error
            }
        }
        throw Failure.copyFailed(lastError?.localizedDescription ?? "")
    }

    /// Quits a copy already running from `destination`, puts the old copy in
    /// the Trash (so it can be restored), and copies the new one in.
    private static func replace(_ destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            let running = NSWorkspace.shared.runningApplications.filter {
                $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL
            }
            running.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(5)
            while running.contains(where: { !$0.isTerminated }), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    /// Removes `com.apple.quarantine` from the copy and everything in it.
    /// The user already opened this download once, so Gatekeeper has done
    /// its check; leaving the flag would translocate the copy again.
    private static func clearQuarantine(at url: URL) {
        let attribute = "com.apple.quarantine"
        var paths = [url.path]
        if let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            paths += items.compactMap { ($0 as? URL)?.path }
        }
        for path in paths {
            removexattr(path, attribute, XATTR_NOFOLLOW)
        }
    }

    /// Where the user's copy really is: the translocated mirror's original,
    /// or the bundle itself.
    private static func originalURL(of bundle: URL, location: InstallLocation) -> URL? {
        location == .translocated ? Translocation.originalURL(of: bundle) : bundle
    }

    /// Opens the copy once this process has exited, then ejects the disk
    /// image it came from. A downloaded original stays where it is: deleting
    /// it needs the Downloads folder privacy permission, and a permission
    /// prompt in the middle of installing would be worse than a stray copy.
    private static func relaunch(_ destination: URL, ejecting volume: URL?) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done
        /usr/bin/open "$1"
        if [ -n "$2" ]; then /usr/bin/hdiutil detach "$2" -quiet; fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "tabbi-relaunch", destination.path, volume?.path ?? ""]
        try? process.run()
    }
}
