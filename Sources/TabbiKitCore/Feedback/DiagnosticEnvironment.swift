import Foundation

/// The three facts about this copy of Tabbi that a suggestion or a crash
/// report carries: the app version, the macOS version and the edition id.
/// Nothing else about the Mac or the person goes with them, and each value
/// is cleaned to a short run of plain characters, so a stray Info.plist
/// value can never smuggle more along.
public struct DiagnosticEnvironment: Equatable, Codable, Sendable {
    /// Longest value kept for each field; real ones are far shorter.
    public static let maxFieldLength = 32

    /// "1.4.0 (52)", or "development" for a build without a bundle.
    public let appVersion: String
    /// "15.1.0".
    public let systemVersion: String
    /// The edition id, such as "tabbi" or "appstore".
    public let edition: String

    public init(appVersion: String, systemVersion: String, edition: String) {
        self.appVersion = Self.clean(appVersion) ?? "unknown"
        self.systemVersion = Self.clean(systemVersion) ?? "unknown"
        self.edition = Self.clean(edition) ?? "unknown"
    }

    /// Reads the version from a bundle's Info.plist and the system version
    /// from its numbers (`ProcessInfo.operatingSystemVersion`).
    public init(infoDictionary: [String: Any]?, system: OperatingSystemVersion, edition: String) {
        self.init(
            appVersion: Self.appVersion(infoDictionary: infoDictionary),
            systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            edition: edition
        )
    }

    /// "1.4.0 (52)" from the short version and the build number, "1.4.0"
    /// without a build number, and "development" without a version (`swift run`).
    public static func appVersion(infoDictionary: [String: Any]?) -> String {
        guard let version = infoDictionary?["CFBundleShortVersionString"] as? String else { return "development" }
        guard let build = infoDictionary?["CFBundleVersion"] as? String, build != version else { return version }
        return "\(version) (\(build))"
    }

    /// Keeps letters, digits, spaces and `. _ - ( )`, trimmed and capped at
    /// `maxFieldLength`; nil when nothing is left.
    static func clean(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-()")
        let kept = String(String.UnicodeScalarView(value.unicodeScalars.filter { allowed.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        let capped = String(kept.prefix(maxFieldLength)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? nil : capped
    }
}
