/// Tracks which modules are running and works out which to start or stop
/// when the enabled tabs change.
///
/// A module runs while it is enabled in the layout (not only while its panel
/// is on screen), so background work such as a due-count refresh feeding
/// Today or the ticker can live in its lifecycle. Keeping the bookkeeping a
/// plain value lets the app's registry stay a thin shell around it.
public struct ModuleLifecycle: Equatable, Sendable {
    /// What one `update(enabled:)` asks the caller to do.
    public struct Changes: Equatable, Sendable {
        /// Newly enabled modules, in tab order.
        public var start: [ModuleID]
        /// Modules that are no longer enabled, in the order they were started.
        public var stop: [ModuleID]

        public init(start: [ModuleID] = [], stop: [ModuleID] = []) {
            self.start = start
            self.stop = stop
        }

        public var isEmpty: Bool { start.isEmpty && stop.isEmpty }
    }

    /// Running modules, in the order they were started.
    public private(set) var running: [ModuleID] = []

    public init() {}

    /// Moves to `enabled` (duplicates ignored) and returns the difference.
    /// Reordering tabs changes nothing, so modules aren't restarted for it.
    public mutating func update(enabled: [ModuleID]) -> Changes {
        var seen = Set<ModuleID>()
        let target = enabled.filter { seen.insert($0).inserted }
        let stop = running.filter { !seen.contains($0) }
        let start = target.filter { !running.contains($0) }
        running = running.filter(seen.contains) + start
        return Changes(start: start, stop: stop)
    }

    /// Stops everything, e.g. when the app quits.
    public mutating func stopAll() -> Changes {
        defer { running = [] }
        return Changes(stop: running)
    }
}
