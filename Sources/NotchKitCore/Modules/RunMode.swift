/// How this process runs: live, with demo data, rendering snapshots, or
/// both of the latter.
///
/// Read once at launch and handed to every module in its `ModuleContext`,
/// so no store reads the environment itself and a new module cannot
/// forget demo mode.
public struct RunMode: Sendable, Hashable {
    /// `NOTCHDECK_DEMO=1`: show realistic sample data and never touch the
    /// network, Spotify, Music, Calendar or the `claude` CLI.
    public var isDemo: Bool
    /// `--snapshot <folder>`: render PNGs and exit. No sounds, nothing
    /// saved, no animations that would be caught mid-frame.
    public var isSnapshot: Bool

    public init(isDemo: Bool = false, isSnapshot: Bool = false) {
        self.isDemo = isDemo
        self.isSnapshot = isSnapshot
    }

    /// The mode a process with this environment and these arguments runs in.
    public init(environment: [String: String], arguments: [String]) {
        self.init(isDemo: environment[Self.demoVariable] == "1",
                  isSnapshot: arguments.contains(Self.snapshotFlag))
    }

    /// The real app: real data, saved to disk.
    public static let live = RunMode()
    /// Sample data, kept in memory.
    public static let demo = RunMode(isDemo: true)

    /// True when nothing may be saved to disk: demo data must not overwrite
    /// the user's files, and a snapshot run must leave no trace.
    public var isEphemeral: Bool { isDemo || isSnapshot }

    /// The environment variable that turns demo mode on.
    public static let demoVariable = "NOTCHDECK_DEMO"
    /// The argument that renders snapshots.
    public static let snapshotFlag = "--snapshot"
}
