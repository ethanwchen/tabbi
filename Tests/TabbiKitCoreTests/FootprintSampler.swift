import Darwin
import Foundation

/// Samples this process's physical footprint (what Activity Monitor and
/// `footprint` report) on a background thread and returns the peak growth.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var peak: UInt64
    private let baseline: UInt64

    init() {
        // Return pages freed by earlier work so they can't hide new growth.
        malloc_zone_pressure_relief(nil, 0)
        baseline = Self.footprint()
        peak = baseline
        Thread { [self] in
            while lock.withLock({ running }) {
                let now = Self.footprint()
                lock.withLock { peak = max(peak, now) }
                usleep(2_000)
            }
        }.start()
    }

    /// Stops sampling and returns the peak growth over the baseline in bytes.
    func stop() -> Int {
        let now = Self.footprint()
        return lock.withLock {
            running = false
            peak = max(peak, now)
            return Int(peak - baseline)
        }
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
