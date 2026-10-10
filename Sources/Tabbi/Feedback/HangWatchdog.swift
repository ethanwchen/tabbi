import Darwin
import Foundation
import TabbiKitCore

/// Notices when Tabbi's main thread stops answering and leaves a hang log
/// through `CrashHandler`, so a hang that ends in a force quit is offered
/// on the next launch like a crash.
///
/// A background queue pings the main queue every `interval` and lets a
/// `HangDetector` judge the answers. When a hang begins, it suspends the
/// main thread just long enough to copy its return addresses (walking the
/// frame pointers, with every read checked by the kernel, and with no
/// allocation or lock while it is suspended), then names the frames with
/// `dladdr` once the thread runs again. The log is taken back as soon as
/// the main thread answers.
final class HangWatchdog: @unchecked Sendable {
    /// A ping every 2 seconds; three missed in a row (about 6 seconds of
    /// spinning beach ball) count as a hang.
    static let interval: DispatchTimeInterval = .seconds(2)
    static let ticksToHang = 3

    /// The app's one watchdog, started at launch in live, non-App Store runs.
    static let shared = HangWatchdog()

    private let queue = DispatchQueue(label: "Tabbi.HangWatchdog", qos: .utility)
    private let interval: DispatchTimeInterval
    // Read and written only on `queue`.
    private var detector: HangDetector
    private var answered = true
    private var timer: DispatchSourceTimer?
    private var mainThread: thread_act_t = 0
    /// Where the suspended thread's return addresses go, allocated up front.
    private let addresses = UnsafeMutableBufferPointer<UInt>.allocate(capacity: CrashReport.maxFrames)

    init(interval: DispatchTimeInterval = HangWatchdog.interval, ticksToHang: Int = HangWatchdog.ticksToHang) {
        self.interval = interval
        detector = HangDetector(ticksToHang: ticksToHang)
    }

    deinit {
        addresses.deallocate()
    }

    /// Starts watching. Call on the main thread, the one it watches.
    /// `CrashHandler` must be prepared, since the hang log goes where a
    /// crash log would.
    func start() {
        precondition(Thread.isMainThread, "HangWatchdog watches the thread that starts it")
        let mainThread = pthread_mach_thread_np(pthread_self())
        queue.async { [self] in
            self.mainThread = mainThread
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Stops watching and takes back a hang log that is still open.
    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            if detector.isHanging { CrashHandler.removeHangLog() }
            detector = HangDetector(ticksToHang: detector.ticksToHang)
            answered = true
        }
    }

    private func tick() {
        let answered = answered
        switch detector.tick(answered: answered) {
        case .began:
            CrashHandler.writeHangLog(frames: mainThreadFrames())
        case .ended:
            CrashHandler.removeHangLog()
        case nil:
            break
        }
        // One ping at a time, so a long hang doesn't pile them up.
        guard answered else { return }
        self.answered = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            queue.async { self.answered = true }
        }
    }

    // MARK: The main thread's stack

    /// The main thread's frames, innermost first, in `backtrace_symbols` form.
    private func mainThreadFrames() -> [String] {
        let count = Self.copyReturnAddresses(of: mainThread, into: addresses)
        return (0 ..< count).map { Self.frameLine(index: $0, address: addresses[$0]) }
    }

    /// Suspends the thread, copies its program counter and the return
    /// addresses along its frame-pointer chain, and resumes it. Nothing here
    /// allocates or takes a lock, since the suspended thread may hold one.
    /// A leaf function that keeps no frame of its own hides its caller.
    private static func copyReturnAddresses(of thread: thread_act_t, into buffer: UnsafeMutableBufferPointer<UInt>) -> Int {
        guard thread != 0, pthread_main_np() == 0, thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(thread) }
        guard let (pc, framePointer) = registers(of: thread) else { return 0 }
        buffer[0] = strip(pc)
        var count = 1
        var frame = framePointer
        // Each frame holds the caller's frame pointer and the return address.
        var record: (UInt, UInt) = (0, 0)
        while count < buffer.count, frame != 0, frame % UInt(MemoryLayout<UInt>.size) == 0 {
            var size = mach_vm_size_t(0)
            let read = withUnsafeMutableBytes(of: &record) { bytes in
                mach_vm_read_overwrite(mach_task_self_, mach_vm_address_t(frame), mach_vm_size_t(bytes.count),
                                       mach_vm_address_t(UInt(bitPattern: bytes.baseAddress)), &size)
            }
            guard read == KERN_SUCCESS, record.1 != 0 else { break }
            buffer[count] = strip(record.1)
            count += 1
            // The stack grows down, so a caller's frame always sits higher.
            guard record.0 > frame else { break }
            frame = record.0
        }
        return count
    }

    private static func registers(of thread: thread_act_t) -> (pc: UInt, fp: UInt)? {
        #if arch(arm64)
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt(state.__pc), UInt(state.__fp))
        #elseif arch(x86_64)
        var state = x86_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, x86_THREAD_STATE64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (UInt(state.__rip), UInt(state.__rbp))
        #else
        return nil
        #endif
    }

    /// Drops the pointer-authentication bits Apple silicon signs return
    /// addresses with, leaving the 47-bit user address.
    private static func strip(_ address: UInt) -> UInt {
        address & 0x0000_7FFF_FFFF_FFFF
    }

    /// One frame as `backtrace_symbols` prints it: index, image, address,
    /// symbol and offset.
    static func frameLine(index: Int, address: UInt) -> String {
        var info = Dl_info()
        let found = dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0
        let image = found ? info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } : nil
        let symbol = found ? info.dli_sname.map { String(cString: $0) } : nil
        let base = UInt(bitPattern: symbol != nil ? info.dli_saddr : info.dli_fbase)
        let location = "\(symbol ?? "0x" + String(base, radix: 16)) + \(address - min(base, address))"
        let hex = String(address, radix: 16)
        let paddedImage = (image ?? "???").padding(toLength: max(35, (image ?? "???").count), withPad: " ", startingAt: 0)
        let paddedIndex = String(index).padding(toLength: 4, withPad: " ", startingAt: 0)
        return "\(paddedIndex)\(paddedImage) 0x\(String(repeating: "0", count: max(0, 16 - hex.count)))\(hex) \(location)"
    }
}
