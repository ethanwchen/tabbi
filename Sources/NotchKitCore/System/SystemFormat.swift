/// Display strings for system metrics. Missing values render as a plain
/// hyphen so an unavailable metric reads as "unknown", never as 0.
public enum SystemFormat {
    public static let unavailable = "-"

    /// `0.423` → `"42%"`; values are clamped to `0...100`.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return unavailable }
        let value = Int((min(max(fraction, 0), 1) * 100).rounded())
        return "\(value)%"
    }

    /// Bytes → binary gigabytes with one decimal, dropping a trailing `.0`
    /// so installed sizes read "16" rather than "16.0". Live values pass
    /// `alwaysShowTenths` so the headline doesn't jump between "34" and
    /// "34.1" from one second to the next.
    public static func gigabytes(_ bytes: UInt64?, alwaysShowTenths: Bool = false) -> String {
        guard let bytes else { return unavailable }
        let gb = Double(bytes) / 1_073_741_824
        let tenths = (gb * 10).rounded()
        if !alwaysShowTenths, tenths.truncatingRemainder(dividingBy: 10) == 0 {
            return "\(Int(tenths / 10))"
        }
        return "\(Int(tenths) / 10).\(Int(tenths) % 10)"
    }

    /// `"12.4 / 16 GB"`, or a plain hyphen when memory is unknown.
    public static func memory(_ stats: MemoryStats?) -> String {
        guard let stats else { return unavailable }
        return "\(gigabytes(stats.usedBytes, alwaysShowTenths: true)) / \(gigabytes(stats.totalBytes)) GB"
    }
}

/// Mirror of `ProcessInfo.ThermalState`, kept here so formatting and the
/// "only show when not nominal" rule are testable.
public enum ThermalLevel: Int, Comparable, Sendable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    public var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Throttling"
        }
    }

    /// The panel shows a thermal chip only when this is true.
    public var needsAttention: Bool { self != .nominal }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
