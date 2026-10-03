import Foundation
import SwiftUI
import NotchKitCore

/// Live CPU, GPU, memory and thermal readings for the System panel.
///
/// Sampling runs once per second only while the panel is visible: the
/// panel calls `start()` / `stop()` from `onAppear` / `onDisappear`. With
/// `NOTCHDECK_DEMO=1` it plays back `SystemDemoData` instead of reading
/// the machine, so snapshots look the same everywhere.
@MainActor
final class SystemMonitor: ObservableObject {
    static let historyCapacity = 60

    /// `nil` until two CPU samples a second apart exist (including right
    /// after a sampling gap), or when the kernel won't report.
    @Published private(set) var cpu: CPUUsage?
    @Published private(set) var cpuHistory = RingBuffer<Double>(capacity: historyCapacity)
    /// `nil` when no accelerator reports utilization.
    @Published private(set) var gpu: Double?
    @Published private(set) var gpuHistory = RingBuffer<Double>(capacity: historyCapacity)
    @Published private(set) var memory: MemoryStats?
    /// Used-memory fraction over time.
    @Published private(set) var memoryHistory = RingBuffer<Double>(capacity: historyCapacity)
    @Published private(set) var thermal: ThermalLevel = .nominal

    private let isDemo: Bool
    private var previousTicks: [CPUTicks] = []
    /// When `previousTicks` was taken. A baseline older than a couple of
    /// ticks (e.g. from before the panel was last hidden) would report the
    /// average over that whole gap, so it is replaced instead of used, and
    /// the histories restart so each sparkline covers one contiguous window.
    private var previousTicksTime: ContinuousClock.Instant?
    private var demoStep = 0
    private var samplingTask: Task<Void, Never>?
    /// Number of visible panels; sampling stops when it drops to zero.
    private var viewers = 0

    init(runMode: RunMode) {
        isDemo = runMode.isDemo
        if isDemo {
            demoStep = Self.historyCapacity
            for step in 1...Self.historyCapacity { applyDemo(step: step) }
        } else {
            // Cheap one-off reading so the first frame isn't empty; the CPU
            // baseline makes the first timer tick report a real percentage.
            previousTicks = SystemSampler.cpuTicks()
            previousTicksTime = .now
            memory = SystemSampler.memory()
            if let memory { memoryHistory.append(memory.usedFraction) }
            gpu = SystemSampler.gpuUtilization()
            if let gpu { gpuHistory.append(gpu) }
            thermal = SystemSampler.thermal()
        }
    }

    func start() {
        viewers += 1
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
            }
        }
    }

    func stop() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func sample() {
        if isDemo {
            demoStep += 1
            applyDemo(step: demoStep)
            return
        }
        let ticks = SystemSampler.cpuTicks()
        let now = ContinuousClock.now
        if let previousTicksTime, now - previousTicksTime < .seconds(3) {
            let usage = CPUUsageCalculator.usage(from: previousTicks, to: ticks)
            cpu = usage
            if let usage { cpuHistory.append(usage.total) }
        } else {
            cpu = nil
            cpuHistory.removeAll()
            gpuHistory.removeAll()
            memoryHistory.removeAll()
        }
        previousTicks = ticks
        previousTicksTime = now

        let gpuNow = SystemSampler.gpuUtilization()
        gpu = gpuNow
        if let gpuNow { gpuHistory.append(gpuNow) }

        let memoryNow = SystemSampler.memory()
        memory = memoryNow
        if let memoryNow { memoryHistory.append(memoryNow.usedFraction) }
        let thermalNow = SystemSampler.thermal()
        if thermalNow != thermal { thermal = thermalNow }
    }

    private func applyDemo(step: Int) {
        let total = SystemDemoData.cpu(at: step)
        cpu = CPUUsage(total: total, perCore: SystemDemoData.perCore(at: step))
        cpuHistory.append(total)
        let gpuNow = SystemDemoData.gpu(at: step)
        gpu = gpuNow
        gpuHistory.append(gpuNow)
        let memoryNow = SystemDemoData.memory(at: step)
        memory = memoryNow
        memoryHistory.append(memoryNow.usedFraction)
    }
}
