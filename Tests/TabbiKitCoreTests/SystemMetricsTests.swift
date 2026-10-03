import XCTest
import TabbiKitCore

final class CPUUsageCalculatorTests: XCTestCase {
    func testComputesPerCoreAndWeightedTotal() throws {
        let previous = [
            CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
        ]
        let current = [
            // 60 busy of 100 elapsed.
            CPUTicks(user: 140, system: 60, idle: 890, nice: 10),
            // 25 busy of 300 elapsed.
            CPUTicks(user: 20, system: 5, idle: 275, nice: 0),
        ]
        let usage = try XCTUnwrap(CPUUsageCalculator.usage(from: previous, to: current))
        XCTAssertEqual(usage.perCore[0], 0.60, accuracy: 1e-9)
        XCTAssertEqual(usage.perCore[1], 25.0 / 300.0, accuracy: 1e-9)
        // Weighted by elapsed ticks, not a plain average of cores.
        XCTAssertEqual(usage.total, 85.0 / 400.0, accuracy: 1e-9)
    }

    func testHandlesCounterWraparound() throws {
        let previous = [CPUTicks(user: .max - 9, system: 0, idle: .max - 9, nice: 0)]
        let current = [CPUTicks(user: 10, system: 0, idle: 10, nice: 0)]
        let usage = try XCTUnwrap(CPUUsageCalculator.usage(from: previous, to: current))
        XCTAssertEqual(usage.total, 0.5, accuracy: 1e-9)
    }

    func testIdleIntervalIsZeroNotNaN() throws {
        let ticks = [CPUTicks(user: 5, system: 5, idle: 5, nice: 5)]
        let usage = try XCTUnwrap(CPUUsageCalculator.usage(from: ticks, to: ticks))
        XCTAssertEqual(usage, CPUUsage(total: 0, perCore: [0]))
    }

    func testMismatchedOrEmptySnapshotsAreUnavailable() {
        let one = [CPUTicks(user: 1, system: 1, idle: 1, nice: 1)]
        XCTAssertNil(CPUUsageCalculator.usage(from: one, to: one + one))
        XCTAssertNil(CPUUsageCalculator.usage(from: [], to: []))
    }
}

final class RingBufferTests: XCTestCase {
    func testKeepsNewestElementsInOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.last)
        for value in 1...5 { buffer.append(value) }
        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.last, 5)
    }

    func testPartiallyFilled() {
        var buffer = RingBuffer<Int>(capacity: 60)
        buffer.append(7)
        buffer.append(8)
        XCTAssertFalse(buffer.isFull)
        XCTAssertEqual(buffer.elements, [7, 8])
    }

    func testRemoveAllResets() {
        var buffer = RingBuffer<Int>(capacity: 2)
        for value in 1...3 { buffer.append(value) }
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        buffer.append(9)
        XCTAssertEqual(buffer.elements, [9])
        XCTAssertEqual(buffer.last, 9)
    }
}

final class MemoryStatsTests: XCTestCase {
    private let gib: UInt64 = 1 << 30
    private let page: UInt64 = 16_384

    func testUsedCountsAppWiredAndCompressed() {
        let pagesPerGiB = gib / page
        let pages = MemoryPageCounts(
            pageSize: page,
            wired: 2 * pagesPerGiB,
            compressed: 1 * pagesPerGiB,
            internalPages: 6 * pagesPerGiB,
            purgeable: 1 * pagesPerGiB
        )
        let stats = MemoryStats(pages: pages, totalBytes: 16 * gib)
        XCTAssertEqual(stats.usedBytes, 8 * gib)
        XCTAssertEqual(stats.usedFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(stats.pressure, .normal)
    }

    func testKernelPressureLevelWins() {
        let pages = MemoryPageCounts(pageSize: page, wired: 0, compressed: 0, internalPages: 0, purgeable: 0)
        XCTAssertEqual(MemoryStats(pages: pages, totalBytes: gib, kernelPressureLevel: 4).pressure, .critical)
        XCTAssertEqual(MemoryStats(pages: pages, totalBytes: gib, kernelPressureLevel: 2).pressure, .warning)
        // Unknown kernel values fall back to the used-fraction estimate.
        XCTAssertEqual(MemoryStats(pages: pages, totalBytes: gib, kernelPressureLevel: 99).pressure, .normal)
    }

    func testUsedIsClampedToTotal() {
        let pages = MemoryPageCounts(pageSize: page, wired: 1_000_000, compressed: 0, internalPages: 0, purgeable: 5)
        let stats = MemoryStats(pages: pages, totalBytes: gib)
        XCTAssertEqual(stats.usedBytes, gib)
        XCTAssertEqual(stats.pressure, .critical)
    }

    func testPressureFromFraction() {
        XCTAssertEqual(MemoryPressure(usedFraction: 0.5), .normal)
        XCTAssertEqual(MemoryPressure(usedFraction: 0.85), .warning)
        XCTAssertEqual(MemoryPressure(usedFraction: 0.95), .critical)
    }
}

final class SystemFormatTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(SystemFormat.percent(0.423), "42%")
        XCTAssertEqual(SystemFormat.percent(1.4), "100%")
        XCTAssertEqual(SystemFormat.percent(-0.2), "0%")
        XCTAssertEqual(SystemFormat.percent(nil), SystemFormat.unavailable)
        XCTAssertEqual(SystemFormat.percent(.nan), SystemFormat.unavailable)
    }

    func testGigabytes() {
        XCTAssertEqual(SystemFormat.gigabytes(16 << 30), "16")
        XCTAssertEqual(SystemFormat.gigabytes(UInt64(12.4 * 1_073_741_824)), "12.4")
        XCTAssertEqual(SystemFormat.gigabytes(UInt64(0.96 * 1_073_741_824)), "1")
        XCTAssertEqual(SystemFormat.gigabytes(nil), SystemFormat.unavailable)
        XCTAssertEqual(SystemFormat.gigabytes(34 << 30, alwaysShowTenths: true), "34.0")
        XCTAssertEqual(SystemFormat.gigabytes(UInt64(12.44 * 1_073_741_824), alwaysShowTenths: true), "12.4")
    }

    func testMemorySummary() {
        let stats = MemoryStats(usedBytes: UInt64(9.5 * 1_073_741_824), totalBytes: 16 << 30, pressure: .normal)
        XCTAssertEqual(SystemFormat.memory(stats), "9.5 / 16 GB")
        XCTAssertEqual(SystemFormat.memory(nil), SystemFormat.unavailable)
    }

    func testThermalAttention() {
        XCTAssertFalse(ThermalLevel.nominal.needsAttention)
        XCTAssertTrue(ThermalLevel.serious.needsAttention)
        XCTAssertLessThan(ThermalLevel.fair, ThermalLevel.critical)
    }
}
