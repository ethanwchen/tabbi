import Foundation

/// Deterministic, realistic-looking metrics for `NOTCHDECK_DEMO=1`, used by
/// snapshots and README screenshots so they never depend on the machine
/// they were rendered on.
public enum SystemDemoData {
    /// Performance + efficiency cores of a typical M-series MacBook Pro.
    public static let coreCount = 10
    public static let totalMemoryBytes: UInt64 = 16 * 1_073_741_824

    /// Whole-machine CPU busy fraction at a given step (one step per second).
    /// Layered sines give a gently wandering line with an occasional burst.
    public static func cpu(at step: Int) -> Double {
        let t = Double(step)
        let value = 0.24 + 0.08 * sin(t / 5.3) + 0.05 * sin(t / 1.7) + 0.16 * pow(max(0, sin(t / 9.1)), 6)
        return clamp(value)
    }

    /// Per-core busy fractions at a given step: performance cores (first
    /// four) run hotter than efficiency cores, and every core differs.
    public static func perCore(at step: Int) -> [Double] {
        let total = cpu(at: step)
        return (0..<coreCount).map { core in
            let bias = core < 4 ? 1.35 : 0.75
            let wobble = 0.12 * sin(Double(step + core * 7) / 2.3)
            return clamp(total * bias + wobble)
        }
    }

    /// GPU busy fraction at a given step: mostly idle with short spikes,
    /// the way a desktop compositor plus the odd video frame looks.
    public static func gpu(at step: Int) -> Double {
        let t = Double(step)
        let value = 0.12 + 0.04 * sin(t / 3.1) + 0.30 * pow(max(0, sin(t / 6.7 + 1)), 8)
        return clamp(value)
    }

    public static func memory(at step: Int) -> MemoryStats {
        let used = 11.4 + 0.3 * sin(Double(step) / 11)
        return MemoryStats(
            usedBytes: UInt64(used * 1_073_741_824),
            totalBytes: totalMemoryBytes,
            pressure: .normal
        )
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
