/// Raw page counters from `host_statistics64(HOST_VM_INFO64)`, decoupled
/// from Mach types so the math stays testable.
public struct MemoryPageCounts: Equatable, Sendable {
    public var pageSize: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    /// Anonymous (non-file-backed) pages; "app memory" before purgeable.
    public var internalPages: UInt64
    public var purgeable: UInt64

    public init(pageSize: UInt64, wired: UInt64, compressed: UInt64, internalPages: UInt64, purgeable: UInt64) {
        self.pageSize = pageSize
        self.wired = wired
        self.compressed = compressed
        self.internalPages = internalPages
        self.purgeable = purgeable
    }
}

/// How hard the system is working to find memory, mirroring Activity
/// Monitor's green / yellow / red pressure graph.
public enum MemoryPressure: Int, Comparable, Sendable, CaseIterable {
    case normal
    case warning
    case critical

    /// Maps `kern.memorystatus_vm_pressure_level` (1 normal, 2 warn, 4 critical).
    public init?(kernelLevel: Int) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }

    /// Fallback when the kernel level is unavailable: judge by used fraction.
    public init(usedFraction: Double) {
        switch usedFraction {
        case ..<0.80: self = .normal
        case ..<0.92: self = .warning
        default: self = .critical
        }
    }

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Memory in use versus installed, plus the current pressure level.
public struct MemoryStats: Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: MemoryPressure

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = min(usedBytes, totalBytes)
        self.totalBytes = totalBytes
        self.pressure = pressure
    }

    /// Builds stats the way Activity Monitor counts "Memory Used":
    /// app memory (internal minus purgeable) + wired + compressed.
    /// `kernelPressureLevel` wins when present; otherwise pressure is
    /// estimated from the used fraction.
    public init(pages: MemoryPageCounts, totalBytes: UInt64, kernelPressureLevel: Int? = nil) {
        let appPages = pages.internalPages > pages.purgeable ? pages.internalPages - pages.purgeable : 0
        let used = (appPages + pages.wired + pages.compressed) * pages.pageSize
        let clamped = min(used, totalBytes)
        let fraction = totalBytes == 0 ? 0 : Double(clamped) / Double(totalBytes)
        let pressure = kernelPressureLevel.flatMap(MemoryPressure.init(kernelLevel:))
            ?? MemoryPressure(usedFraction: fraction)
        self.init(usedBytes: clamped, totalBytes: totalBytes, pressure: pressure)
    }

    /// Used fraction in `0...1`.
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}
