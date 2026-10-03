import Darwin
import Foundation
import IOKit
import NotchKitCore

/// Reads raw system metrics from the kernel and IOKit. Every call works on
/// Apple Silicon without root or entitlements; anything the OS refuses to
/// report comes back as `nil` so the panel can show "—".
enum SystemSampler {
    /// `mach_host_self()` hands out a new send right on every call, so take
    /// one for the lifetime of the process.
    private static let host = mach_host_self()

    /// Cumulative per-core scheduler ticks, or an empty array on failure.
    static func cpuTicks() -> [CPUTicks] {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(coreCount)).map { core in
            let base = core * stride
            func ticks(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[base + Int(state)]) }
            return CPUTicks(
                user: ticks(CPU_STATE_USER), system: ticks(CPU_STATE_SYSTEM),
                idle: ticks(CPU_STATE_IDLE), nice: ticks(CPU_STATE_NICE)
            )
        }
    }

    static func memory() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        // The counts are in kernel pages. Asking the host for their size
        // avoids reading the `vm_kernel_page_size` global, which Swift 6
        // treats as shared mutable state.
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let pages = MemoryPageCounts(
            pageSize: UInt64(pageSize),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            internalPages: UInt64(stats.internal_page_count),
            purgeable: UInt64(stats.purgeable_count)
        )
        return MemoryStats(pages: pages, totalBytes: ProcessInfo.processInfo.physicalMemory,
                           kernelPressureLevel: kernelPressureLevel())
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    private static func kernelPressureLevel() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return Int(level)
    }

    /// GPU busy fraction from the accelerator's `PerformanceStatistics`,
    /// the same source Activity Monitor's GPU history uses. Takes the
    /// busiest accelerator when there are several.
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var busiest: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            let percent = (property["Device Utilization %"] ?? property["Renderer Utilization %"]) as? NSNumber
            guard let percent else { continue }
            busiest = max(busiest ?? 0, percent.doubleValue / 100)
        }
        return busiest.map { min(max($0, 0), 1) }
    }

    static func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}
