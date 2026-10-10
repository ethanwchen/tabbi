import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// `SystemMonitor` feeds the System panel. These tests run it on scripted
/// readings and a fake clock, stepping `sample()` by hand, so the CPU
/// baseline, the gap rule and the sparkline histories are checked without
/// real load or real seconds.
@MainActor
final class SystemMonitorTests: XCTestCase {
    // MARK: - Live readings

    func testTheFirstFrameShowsMemoryGPUAndThermalButWaitsForASecondCPUSample() {
        let machine = FakeMachine()
        machine.thermal = .fair
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)

        XCTAssertNil(monitor.cpu, "one tick snapshot is not a percentage yet")
        XCTAssertTrue(monitor.cpuHistory.isEmpty)
        XCTAssertEqual(monitor.memory, machine.memory)
        XCTAssertEqual(monitor.memoryHistory.elements, [0.5])
        XCTAssertEqual(monitor.gpu, 0.2)
        XCTAssertEqual(monitor.gpuHistory.elements, [0.2])
        XCTAssertEqual(monitor.thermal, .fair)
        XCTAssertFalse(monitor.isSampling, "nothing samples until a panel is shown")
    }

    func testASampleASecondLaterReportsCPUFromTheTickDelta() throws {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)

        // Core 0: 30 busy of 100. Core 1: 10 busy of 100 (nice counts as busy).
        machine.advance(by: .seconds(1), ticks: [
            CPUTicks(user: 20, system: 10, idle: 70, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 90, nice: 10),
        ])
        machine.gpu = 0.6
        machine.memory = FakeMachine.memory(usedFraction: 0.75)
        monitor.sample()

        let cpu = try XCTUnwrap(monitor.cpu)
        XCTAssertEqual(cpu.total, 0.2, accuracy: 1e-9)
        XCTAssertEqual(cpu.perCore[0], 0.3, accuracy: 1e-9)
        XCTAssertEqual(cpu.perCore[1], 0.1, accuracy: 1e-9)
        XCTAssertEqual(monitor.cpuHistory.count, 1)
        XCTAssertEqual(monitor.gpuHistory.elements, [0.2, 0.6])
        XCTAssertEqual(monitor.memoryHistory.elements, [0.5, 0.75])
        XCTAssertEqual(monitor.memory?.pressure, .normal)
    }

    func testAGapWhileThePanelWasHiddenRestartsTheSparklinesInsteadOfAveragingIt() throws {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        machine.advance(by: .seconds(1), busyPerCore: 50)
        monitor.sample()
        machine.advance(by: .seconds(1), busyPerCore: 50)
        monitor.sample()
        XCTAssertEqual(monitor.cpuHistory.count, 2)
        XCTAssertEqual(monitor.memoryHistory.count, 3)

        // The panel was closed for a minute, then opened again.
        machine.advance(by: .seconds(60), busyPerCore: 50)
        monitor.sample()
        XCTAssertNil(monitor.cpu, "an average over the whole gap would mislead")
        XCTAssertTrue(monitor.cpuHistory.isEmpty)
        XCTAssertEqual(monitor.gpuHistory.count, 1, "the histories restart with this reading")
        XCTAssertEqual(monitor.memoryHistory.count, 1)

        // The stale baseline was replaced, so the next second reports again.
        machine.advance(by: .seconds(1), busyPerCore: 80)
        monitor.sample()
        let cpu = try XCTUnwrap(monitor.cpu)
        XCTAssertEqual(cpu.total, 0.8, accuracy: 1e-9)
        XCTAssertEqual(monitor.cpuHistory.count, 1)
        XCTAssertEqual(monitor.memoryHistory.count, 2)
    }

    func testALateTickUnderThreeSecondsStillCountsButThreeSecondsIsAGap() {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        machine.advance(by: .milliseconds(2900), busyPerCore: 50)
        monitor.sample()
        XCTAssertNotNil(monitor.cpu, "a busy main thread can delay a tick")

        machine.advance(by: .seconds(3), busyPerCore: 50)
        monitor.sample()
        XCTAssertNil(monitor.cpu)
        XCTAssertTrue(monitor.cpuHistory.isEmpty)
    }

    func testReadingsTheMacRefusesShowAsMissingWithoutBreakingTheHistories() {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        machine.advance(by: .seconds(1), ticks: [])
        machine.gpu = nil
        machine.memory = nil
        monitor.sample()

        XCTAssertNil(monitor.cpu)
        XCTAssertNil(monitor.gpu)
        XCTAssertNil(monitor.memory)
        XCTAssertTrue(monitor.cpuHistory.isEmpty)
        XCTAssertEqual(monitor.gpuHistory.elements, [0.2], "a missing reading adds no fake zero")
        XCTAssertEqual(monitor.memoryHistory.elements, [0.5])

        // The sensors come back. The empty baseline gives no CPU yet, then
        // the next second does.
        machine.advance(by: .seconds(1), busyPerCore: 0)
        machine.gpu = 0.4
        machine.memory = FakeMachine.memory(usedFraction: 0.5)
        monitor.sample()
        XCTAssertNil(monitor.cpu)
        XCTAssertEqual(monitor.gpu, 0.4)
        machine.advance(by: .seconds(1), busyPerCore: 25)
        monitor.sample()
        XCTAssertEqual(monitor.cpu?.total ?? -1, 0.25, accuracy: 1e-9)
    }

    func testACoreCountChangeSkipsOneCPUReadingButKeepsTheSparklines() {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        machine.advance(by: .seconds(1), busyPerCore: 50)
        monitor.sample()
        XCTAssertEqual(monitor.cpuHistory.count, 1)

        machine.advance(by: .seconds(1), ticks: Array(repeating: CPUTicks(user: 0, system: 0, idle: 0, nice: 0), count: 4))
        monitor.sample()
        XCTAssertNil(monitor.cpu, "cores can't be compared one to one")
        XCTAssertEqual(monitor.cpuHistory.count, 1, "only a time gap restarts the sparklines")
        XCTAssertEqual(monitor.memoryHistory.count, 3)
    }

    func testTheSparklinesKeepTheLastMinute() {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        for second in 1...75 {
            machine.advance(by: .seconds(1), busyPerCore: UInt32(second))
            monitor.sample()
        }
        XCTAssertEqual(monitor.cpuHistory.count, SystemMonitor.historyCapacity)
        XCTAssertEqual(monitor.gpuHistory.count, SystemMonitor.historyCapacity)
        XCTAssertEqual(monitor.memoryHistory.count, SystemMonitor.historyCapacity)
        XCTAssertEqual(monitor.cpuHistory.elements.first ?? -1, 0.16, accuracy: 1e-9, "the oldest kept is second 16")
        XCTAssertEqual(monitor.cpuHistory.last ?? -1, 0.75, accuracy: 1e-9)
    }

    func testThermalFollowsTheMac() {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .live, readings: machine.readings)
        XCTAssertEqual(monitor.thermal, .nominal)
        machine.thermal = .critical
        machine.advance(by: .seconds(1), busyPerCore: 0)
        monitor.sample()
        XCTAssertEqual(monitor.thermal, .critical)
        machine.thermal = .nominal
        machine.advance(by: .seconds(1), busyPerCore: 0)
        monitor.sample()
        XCTAssertEqual(monitor.thermal, .nominal)
    }

    // MARK: - Viewers

    func testSamplingRunsWhileAnyPanelIsVisible() {
        let monitor = SystemMonitor(runMode: .live, readings: FakeMachine().readings)
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isSampling)
        monitor.stop()
        XCTAssertTrue(monitor.isSampling, "a second panel is still showing")
        monitor.stop()
        XCTAssertFalse(monitor.isSampling)

        // An extra stop (a disappear without an appear) must not leave the
        // count negative, or the next panel would never start sampling.
        monitor.stop()
        monitor.start()
        XCTAssertTrue(monitor.isSampling)
        monitor.stop()
        XCTAssertFalse(monitor.isSampling)
    }

    // MARK: - Demo

    func testDemoModePlaysBackSampleDataAndNeverReadsTheMac() throws {
        let machine = FakeMachine()
        let monitor = SystemMonitor(runMode: .demo, readings: machine.readings)
        let capacity = SystemMonitor.historyCapacity

        XCTAssertEqual(monitor.cpuHistory.count, capacity, "the sparklines start full")
        XCTAssertEqual(monitor.gpuHistory.count, capacity)
        XCTAssertEqual(monitor.memoryHistory.count, capacity)
        XCTAssertEqual(monitor.cpu?.perCore.count, SystemDemoData.coreCount)
        XCTAssertEqual(monitor.gpu, SystemDemoData.gpu(at: capacity))
        XCTAssertEqual(monitor.memory, SystemDemoData.memory(at: capacity))

        monitor.sample()
        let cpu = try XCTUnwrap(monitor.cpu)
        XCTAssertEqual(cpu.total, SystemDemoData.cpu(at: capacity + 1))
        XCTAssertEqual(monitor.cpuHistory.last, SystemDemoData.cpu(at: capacity + 1))
        XCTAssertEqual(monitor.memory, SystemDemoData.memory(at: capacity + 1))
        XCTAssertEqual(machine.reads, 0)
    }
}

/// Scripted Mac readings with a clock the test moves by hand. Each core's
/// ticks add up to 100 per step, so a busy count reads as a percentage.
@MainActor
private final class FakeMachine {
    var ticks = Array(repeating: CPUTicks(user: 0, system: 0, idle: 0, nice: 0), count: 2)
    var memory: MemoryStats? = FakeMachine.memory(usedFraction: 0.5)
    var gpu: Double? = 0.2
    var thermal = ThermalLevel.nominal
    private(set) var now = ContinuousClock.now
    private(set) var reads = 0

    /// Holds the machine strongly, so a monitor can outlive the test's
    /// own reference to it.
    var readings: SystemReadings {
        SystemReadings(
            cpuTicks: { self.reads += 1; return self.ticks },
            memory: { self.reads += 1; return self.memory },
            gpu: { self.reads += 1; return self.gpu },
            thermal: { self.reads += 1; return self.thermal },
            now: { self.now }
        )
    }

    /// Moves the clock and sets the next tick snapshot.
    func advance(by duration: Duration, ticks next: [CPUTicks]) {
        now += duration
        ticks = next
    }

    /// Moves the clock and adds 100 ticks to each core, `busy` of them busy.
    func advance(by duration: Duration, busyPerCore busy: UInt32) {
        let base = ticks.isEmpty ? Array(repeating: CPUTicks(user: 0, system: 0, idle: 0, nice: 0), count: 2) : ticks
        advance(by: duration, ticks: base.map {
            CPUTicks(user: $0.user &+ busy, system: $0.system, idle: $0.idle &+ (100 &- busy), nice: $0.nice)
        })
    }

    static func memory(usedFraction: Double) -> MemoryStats {
        let total: UInt64 = 16 * 1_073_741_824
        return MemoryStats(usedBytes: UInt64(Double(total) * usedFraction), totalBytes: total, pressure: .normal)
    }
}
