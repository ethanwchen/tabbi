import Foundation

public extension URLSession {
    /// The one session Tabbi's own HTTP clients share (Party, sync, crash
    /// reports, AnkiConnect). Ephemeral and with cookies and the URL cache
    /// turned off, so nothing a request sets outlives it or reaches disk.
    ///
    /// Shared on purpose: a session is never freed until it is invalidated,
    /// so the clients that made one per transport (and sync builds a
    /// transport per request) leaked about 40 KB per session, and every new
    /// session also opened a new connection.
    static let tabbiEphemeral: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}
