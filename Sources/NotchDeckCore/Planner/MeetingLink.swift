import Foundation

/// A video-call URL found in a calendar event, so the "Up next" card can
/// offer a one-click Join button.
public struct MeetingLink: Hashable, Sendable {
    public enum Provider: String, Hashable, Sendable {
        case zoom
        case googleMeet
        case teams

        /// Name for tooltips, e.g. "Join Zoom call".
        public var displayName: String {
            switch self {
            case .zoom: return "Zoom"
            case .googleMeet: return "Google Meet"
            case .teams: return "Teams"
            }
        }
    }

    public let provider: Provider
    public let url: URL

    public init(provider: Provider, url: URL) {
        self.provider = provider
        self.url = url
    }

    /// Finds the first Zoom, Google Meet, or Teams join link in an event.
    ///
    /// Fields are checked in order of intent: the event's URL field, then the
    /// location, then the notes (where invites bury the link among dial-in
    /// numbers and other URLs). Other links, such as a Zoom marketing page or
    /// a shared doc, are ignored so the button only appears for real calls.
    public static func detect(url: URL? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
        if let url, let link = classify(url) { return link }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = links(in: text).lazy.compactMap(classify).first { return link }
        }
        return nil
    }

    /// Recognizes a single URL as a meeting join link.
    public static func classify(_ url: URL) -> MeetingLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        let normalized = secured(url)

        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com") {
            // Meetings (/j/), personal rooms (/my/), and webinars (/w/).
            let joinPrefixes = ["/j/", "/my/", "/w/", "/s/"]
            return joinPrefixes.contains(where: path.hasPrefix) ? MeetingLink(provider: .zoom, url: normalized) : nil
        }
        if host == "meet.google.com" {
            // Meeting codes look like abc-defg-hij; "/" alone is the landing page.
            let code = path.dropFirst()
            let isCode = code.split(separator: "-").map(\.count) == [3, 4, 3]
            let isLookup = path.hasPrefix("/lookup/")
            return isCode || isLookup ? MeetingLink(provider: .googleMeet, url: normalized) : nil
        }
        if host == "teams.microsoft.com", path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/") {
            return MeetingLink(provider: .teams, url: normalized)
        }
        if host == "teams.live.com", path.hasPrefix("/meet/") {
            return MeetingLink(provider: .teams, url: normalized)
        }
        return nil
    }

    /// Every URL in free text, in order. `NSDataDetector` copes with the
    /// angle brackets, trailing punctuation, and line breaks invites contain.
    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }

    /// Upgrades plain-http links so the Join button never opens an insecure page.
    private static func secured(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }
}
