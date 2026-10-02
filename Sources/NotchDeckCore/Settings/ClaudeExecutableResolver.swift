import Foundation

/// Locates the `claude` binary for every Claude module and remembers the
/// answer until the user's path override changes.
///
/// Discovery can block for seconds (the login-shell fallback), so modules
/// must not locate on every request; but a module that caches its own URL
/// keeps using a stale binary after the user edits the override in Settings.
/// This resolver keys its cache on the override in effect, so a new override
/// takes effect on the next `resolve()` with no restart. Misses are never
/// cached, so installing `claude` later is picked up too.
public final class ClaudeExecutableResolver: @unchecked Sendable {
    /// Shared by Claude Usage and Ask Claude.
    public static let shared = ClaudeExecutableResolver()

    private let locate: @Sendable (String?) -> URL?
    private let currentOverride: @Sendable () -> String?
    private let isExecutable: @Sendable (String) -> Bool
    private let lock = NSLock()
    /// Guarded by `lock`.
    private var cached: (override: String?, url: URL)?

    public init(
        locate: @escaping @Sendable (String?) -> URL? = { ClaudeCLI.locate(pathOverride: $0) },
        currentOverride: @escaping @Sendable () -> String? = { ClaudeCLI.userPathOverride },
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.locate = locate
        self.currentOverride = currentOverride
        self.isExecutable = isExecutable
    }

    /// The binary to run, or `nil` when none is installed. Blocking on a
    /// cache miss; call off the main thread.
    public func resolve() -> URL? {
        let override = currentOverride()
        if let hit = lock.withLock({ cached }), hit.override == override, isExecutable(hit.url.path) {
            return hit.url
        }
        let url = locate(override)
        lock.withLock { cached = url.map { (override, $0) } }
        return url
    }
}
