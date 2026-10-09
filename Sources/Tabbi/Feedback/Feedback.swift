import AppKit
import TabbiKitCore

/// Opens the website's Suggest page with this copy's app version, macOS
/// version and edition filled in (`FeedbackLink`), from the notch's
/// right-click menu and Settings > About.
enum Feedback {
    /// This process's version, macOS version and edition.
    static let environment = DiagnosticEnvironment(
        infoDictionary: Bundle.main.infoDictionary,
        system: ProcessInfo.processInfo.operatingSystemVersion,
        edition: Edition.current.id
    )

    /// The Suggest page for this copy of Tabbi.
    static var url: URL { FeedbackLink.url(for: environment) }

    /// Opens the Suggest page in the default browser.
    @MainActor
    static func open() {
        NSWorkspace.shared.open(url)
    }
}
