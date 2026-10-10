import Foundation

/// The website's Suggest page, opened from the notch's right-click menu and
/// Settings > About with the app version, macOS version and edition filled
/// in, so a bug report says where it happened without the person typing it.
/// Those three query parameters are all the link carries.
public enum FeedbackLink {
    public static let page = URL(string: "https://tabbinotch.com/suggest")!
    /// The menu item and the About link both read this.
    public static let title = "Suggest a Feature or Report a Bug"

    /// The query parameter names, which the site's form keeps as hidden
    /// fields and the suggestions backend validates.
    public enum Parameter {
        public static let appVersion = "version"
        public static let systemVersion = "macos"
        public static let edition = "edition"
    }

    /// The Suggest page with `environment` as query parameters.
    public static func url(for environment: DiagnosticEnvironment) -> URL {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: Parameter.appVersion, value: environment.appVersion),
            URLQueryItem(name: Parameter.systemVersion, value: environment.systemVersion),
            URLQueryItem(name: Parameter.edition, value: environment.edition),
        ]
        return components.url!
    }
}
