import XCTest
@testable import TabbiKitCore

final class SystemDemoDataTests: XCTestCase {
    func testSeriesStayInUnitRangeAndAreDeterministic() {
        for step in -100...500 {
            XCTAssert((0...1).contains(SystemDemoData.cpu(at: step)))
            XCTAssert((0...1).contains(SystemDemoData.gpu(at: step)))
            XCTAssert(SystemDemoData.perCore(at: step).allSatisfy { (0...1).contains($0) })
        }
        XCTAssertEqual(SystemDemoData.cpu(at: 42), SystemDemoData.cpu(at: 42))
    }

    func testSeriesActuallyMoveSoSparklinesAreNotFlat() {
        let cpu = (1...60).map(SystemDemoData.cpu)
        let gpu = (1...60).map(SystemDemoData.gpu)
        XCTAssertGreaterThan(cpu.max()! - cpu.min()!, 0.1)
        XCTAssertGreaterThan(gpu.max()! - gpu.min()!, 0.1)
    }

    func testPerCoreMatchesCoreCountAndPerformanceCoresRunHotter() {
        let cores = SystemDemoData.perCore(at: 30)
        XCTAssertEqual(cores.count, SystemDemoData.coreCount)
        let performance = cores.prefix(4).reduce(0, +) / 4
        let efficiency = cores.suffix(6).reduce(0, +) / 6
        XCTAssertGreaterThan(performance, efficiency)
    }

    func testDemoMemoryIsPlausibleAndNormal() {
        let memory = SystemDemoData.memory(at: 0)
        XCTAssertEqual(memory.totalBytes, SystemDemoData.totalMemoryBytes)
        XCTAssert((0.6...0.8).contains(memory.usedFraction))
        XCTAssertEqual(memory.pressure, .normal)
        XCTAssertEqual(SystemFormat.memory(memory), "11.4 / 16 GB")
    }
}
