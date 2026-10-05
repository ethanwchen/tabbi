import Foundation

/// Where the running app bundle sits, as far as installing it is concerned.
///
/// An app launched from its disk image, from Downloads, or from anywhere
/// Gatekeeper translocated it to (a random read-only folder) cannot keep a
/// login item or update itself, so Tabbi offers to move itself to an
/// Applications folder. Classifying the path is pure, so it is tested here;
/// the app only reads `Bundle.main.bundleURL` and acts on the answer.
public enum InstallLocation: Equatable, Sendable {
    /// In `/Applications` (or a folder inside it).
    case applications
    /// In `~/Applications` (or a folder inside it).
    case userApplications
    /// Run from Gatekeeper's App Translocation mirror: the user opened a
    /// quarantined copy where it lies (a disk image or Downloads).
    case translocated
    /// On a mounted volume under `/Volumes`, such as the Tabbi disk image.
    case diskImage
    /// In `~/Downloads`.
    case downloads
    /// A development build (`swift run`, `scripts/run.sh`, `.build`), or a
    /// bare executable with no `.app` bundle around it.
    case development
    /// Anywhere else, for example the Desktop.
    case elsewhere

    /// Classifies an app bundle path.
    /// - Parameters:
    ///   - bundleURL: the running app's bundle, `Bundle.main.bundleURL`.
    ///   - home: the user's home folder, for `~/Applications` and `~/Downloads`.
    public init(bundleURL: URL, home: URL) {
        let path = bundleURL.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        func isInside(_ folder: String) -> Bool { path.hasPrefix(folder + "/") }

        if bundleURL.pathExtension != "app" || path.contains("/.build/") || path.contains("/build/") {
            self = .development
        } else if path.contains("/AppTranslocation/") {
            self = .translocated
        } else if isInside("/Applications") {
            self = .applications
        } else if isInside(homePath + "/Applications") {
            self = .userApplications
        } else if isInside("/Volumes") {
            self = .diskImage
        } else if isInside(homePath + "/Downloads") {
            self = .downloads
        } else {
            self = .elsewhere
        }
    }

    /// True for the two Applications folders, where the app should live.
    public var isInstalled: Bool { self == .applications || self == .userApplications }

    /// True where Tabbi should offer to move itself. Development builds
    /// never ask, so `swift run` and `scripts/run.sh` stay quiet.
    public var shouldOfferMove: Bool {
        switch self {
        case .translocated, .diskImage, .downloads, .elsewhere: true
        case .applications, .userApplications, .development: false
        }
    }

    /// The mounted volume holding `url` (such as `/Volumes/Tabbi`), or nil
    /// when it is not under `/Volumes`.
    public static func volume(of url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes", isDirectory: true)
            .appendingPathComponent(components[2], isDirectory: true)
    }
}
