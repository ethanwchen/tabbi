/// Cumulative scheduler tick counters for one CPU core, as reported by
/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
///
/// The kernel counters are 32-bit and wrap around, so deltas are computed
/// with wrapping subtraction rather than plain `-`.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// CPU load between two tick snapshots, each value in `0...1`.
public struct CPUUsage: Equatable, Sendable {
    /// Busy fraction across all cores, weighted by each core's elapsed ticks.
    public var total: Double
    /// Busy fraction per core, in the order the kernel reports cores.
    public var perCore: [Double]

    public init(total: Double, perCore: [Double]) {
        self.total = total
        self.perCore = perCore
    }
}

/// Turns two consecutive per-core tick snapshots into usage percentages.
public enum CPUUsageCalculator {
    /// Returns `nil` when the snapshots can't be compared (no cores, or the
    /// core count changed between samples), so callers show "—" instead of
    /// a misleading number.
    public static func usage(from previous: [CPUTicks], to current: [CPUTicks]) -> CPUUsage? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        let perCore = zip(previous, current).map { old, new -> Double in
            let busy = UInt64(new.user &- old.user) + UInt64(new.system &- old.system) + UInt64(new.nice &- old.nice)
            let all = busy + UInt64(new.idle &- old.idle)
            busyTotal += busy
            allTotal += all
            return all == 0 ? 0 : Double(busy) / Double(all)
        }
        let total = allTotal == 0 ? 0 : Double(busyTotal) / Double(allTotal)
        return CPUUsage(total: total, perCore: perCore)
    }
}
