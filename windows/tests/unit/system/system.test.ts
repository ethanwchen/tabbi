import { describe, expect, it } from "vitest";
import { cpuUsage } from "../../../src/core/system/cpuUsage";
import { HistorySeries, RingBuffer } from "../../../src/core/system/history";
import {
  comparePressure,
  memoryFromStatus,
  memoryStats,
  pressureFromUsedFraction,
  pressureTitle,
  usedFraction,
} from "../../../src/core/system/memoryStats";
import { DEMO_CORE_COUNT, DEMO_TOTAL_MEMORY_BYTES, demoCPU, demoGPU, demoMemory, demoPerCore } from "../../../src/core/system/systemDemoData";
import { gigabytes, memorySummary, percent, UNAVAILABLE } from "../../../src/core/system/systemFormat";
import { HISTORY_CAPACITY, SystemMonitorState, type SystemStatsSnapshot } from "../../../src/core/system/systemStats";

/* Port of SystemMetricsTests and SystemDemoDataTests, with the Mac's ticks replaced by Windows processor times. */

const GIB = 1_073_741_824;

describe("cpuUsage", () => {
  it("computes per-core and weighted total", () => {
    const previous = [
      { idle: 850, kernel: 900, user: 100 },
      { idle: 0, kernel: 0, user: 0 },
    ];
    const current = [
      /* 60 busy of 100 elapsed: kernel grew 50 (40 of it idle), user 50. */
      { idle: 890, kernel: 950, user: 150 },
      /* 25 busy of 300 elapsed. */
      { idle: 275, kernel: 280, user: 20 },
    ];
    const usage = cpuUsage(previous, current);
    expect(usage?.perCore[0]).toBeCloseTo(0.6, 9);
    expect(usage?.perCore[1]).toBeCloseTo(25 / 300, 9);
    /* Weighted by elapsed time, not a plain average of cores. */
    expect(usage?.total).toBeCloseTo(85 / 400, 9);
  });

  it("reads an idle interval as zero, not NaN, and a counter reset as no time", () => {
    const times = [{ idle: 5, kernel: 10, user: 5 }];
    expect(cpuUsage(times, times)).toEqual({ total: 0, perCore: [0] });
    expect(cpuUsage([{ idle: 100, kernel: 200, user: 100 }], [{ idle: 10, kernel: 20, user: 10 }])).toEqual({ total: 0, perCore: [0] });
  });

  it("is unavailable for mismatched or empty snapshots", () => {
    const one = [{ idle: 1, kernel: 2, user: 1 }];
    expect(cpuUsage(one, [...one, ...one])).toBeUndefined();
    expect(cpuUsage([], [])).toBeUndefined();
  });

  it("handles counters past 2^32, as 64-bit Windows times are", () => {
    const base = 2 ** 40;
    expect(cpuUsage([{ idle: base, kernel: base, user: base }], [{ idle: base + 10, kernel: base + 20, user: base }])?.total).toBeCloseTo(0.5, 9);
  });
});

describe("RingBuffer", () => {
  it("keeps the newest elements in order", () => {
    const buffer = new RingBuffer<number>(3);
    expect(buffer.isEmpty).toBe(true);
    expect(buffer.last).toBeUndefined();
    for (let value = 1; value <= 5; value++) buffer.append(value);
    expect(buffer.isFull).toBe(true);
    expect(buffer.count).toBe(3);
    expect(buffer.elements).toEqual([3, 4, 5]);
    expect(buffer.last).toBe(5);
  });

  it("works partially filled and resets", () => {
    const buffer = new RingBuffer<number>(60);
    buffer.append(7);
    buffer.append(8);
    expect(buffer.isFull).toBe(false);
    expect(buffer.elements).toEqual([7, 8]);
    const small = new RingBuffer<number>(2);
    for (let value = 1; value <= 3; value++) small.append(value);
    small.removeAll();
    expect(small.isEmpty).toBe(true);
    small.append(9);
    expect(small.elements).toEqual([9]);
    expect(small.last).toBe(9);
    expect(() => new RingBuffer<number>(0)).toThrow();
  });
});

describe("HistorySeries", () => {
  it("right-aligns points, clamps them and drops non-finite samples", () => {
    const series = new HistorySeries([0.2, Number.NaN, 1.4, -0.1], 5);
    expect(series.points).toEqual([
      { x: 2, y: 0.2 },
      { x: 3, y: 1 },
      { x: 4, y: 0 },
    ]);
    expect(series.peak).toBe(1);
    expect(series.average).toBeCloseTo(0.4, 9);
    expect(new HistorySeries([], 5).isEmpty).toBe(true);
    expect(new HistorySeries([], 5).peak).toBeUndefined();
    expect(new HistorySeries([1, 2, 3].map((v) => v / 10), 2).points.map((p) => p.y)).toEqual([0.2, 0.3]);
  });

  it("draws a monotone curve that never overshoots", () => {
    expect(new HistorySeries([0.5], 10).monotoneCurve).toEqual([]);
    const two = new HistorySeries([0, 1], 2).monotoneCurve;
    expect(two).toHaveLength(1);
    expect(two[0]?.control1.x).toBeCloseTo(1 / 3, 12);
    expect(two[0]?.control1.y).toBeCloseTo(1 / 3, 12);
    expect(two[0]?.control2.x).toBeCloseTo(2 / 3, 12);
    expect(two[0]?.control2.y).toBeCloseTo(2 / 3, 12);
    expect(two[0]?.end).toEqual({ x: 1, y: 1 });
    const values = [0.1, 0.9, 0.9, 0.2, 0.5, 0.5, 1, 0];
    const curve = new HistorySeries(values, values.length).monotoneCurve;
    expect(curve).toHaveLength(values.length - 1);
    curve.forEach((segment, index) => {
      const low = Math.min(values[index] ?? 0, values[index + 1] ?? 0);
      const high = Math.max(values[index] ?? 0, values[index + 1] ?? 0);
      for (const control of [segment.control1, segment.control2]) {
        expect(control.y).toBeGreaterThanOrEqual(low - 1e-12);
        expect(control.y).toBeLessThanOrEqual(high + 1e-12);
      }
      expect(segment.end).toEqual({ x: index + 1, y: values[index + 1] });
    });
  });
});

describe("memory", () => {
  it("counts used as installed minus available, with pressure from the fraction", () => {
    const stats = memoryFromStatus(16 * GIB, 8 * GIB);
    expect(stats.usedBytes).toBe(8 * GIB);
    expect(usedFraction(stats)).toBeCloseTo(0.5, 9);
    expect(stats.pressure).toBe("normal");
    expect(memoryFromStatus(GIB, 0).pressure).toBe("critical");
    expect(memoryFromStatus(GIB, 2 * GIB).usedBytes).toBe(0);
    expect(memoryStats(5 * GIB, GIB, "normal").usedBytes).toBe(GIB);
  });

  it("judges pressure from the used fraction", () => {
    expect(pressureFromUsedFraction(0.5)).toBe("normal");
    expect(pressureFromUsedFraction(0.85)).toBe("warning");
    expect(pressureFromUsedFraction(0.95)).toBe("critical");
    expect(comparePressure("warning", "critical")).toBeLessThan(0);
    expect(pressureTitle("warning")).toBe("Elevated");
  });
});

describe("SystemFormat", () => {
  it("writes percents", () => {
    expect(percent(0.423)).toBe("42%");
    expect(percent(1.4)).toBe("100%");
    expect(percent(-0.2)).toBe("0%");
    expect(percent(undefined)).toBe(UNAVAILABLE);
    expect(percent(Number.NaN)).toBe(UNAVAILABLE);
  });

  it("writes gigabytes", () => {
    expect(gigabytes(16 * GIB)).toBe("16");
    expect(gigabytes(Math.trunc(12.4 * GIB))).toBe("12.4");
    expect(gigabytes(Math.trunc(0.96 * GIB))).toBe("1");
    expect(gigabytes(undefined)).toBe(UNAVAILABLE);
    expect(gigabytes(34 * GIB, true)).toBe("34.0");
    expect(gigabytes(Math.trunc(12.44 * GIB), true)).toBe("12.4");
  });

  it("summarizes memory", () => {
    expect(memorySummary(memoryStats(Math.trunc(9.5 * GIB), 16 * GIB, "normal"))).toBe("9.5 / 16 GB");
    expect(memorySummary(undefined)).toBe(UNAVAILABLE);
  });
});

describe("SystemDemoData", () => {
  it("stays in range and is deterministic", () => {
    for (let step = -100; step <= 500; step++) {
      for (const value of [demoCPU(step), demoGPU(step), ...demoPerCore(step)]) {
        expect(value).toBeGreaterThanOrEqual(0);
        expect(value).toBeLessThanOrEqual(1);
      }
    }
    expect(demoCPU(42)).toBe(demoCPU(42));
  });

  it("moves, so sparklines are not flat, and the fast cores run hotter", () => {
    const cpu = Array.from({ length: 60 }, (_, i) => demoCPU(i + 1));
    const gpu = Array.from({ length: 60 }, (_, i) => demoGPU(i + 1));
    expect(Math.max(...cpu) - Math.min(...cpu)).toBeGreaterThan(0.1);
    expect(Math.max(...gpu) - Math.min(...gpu)).toBeGreaterThan(0.1);
    const cores = demoPerCore(30);
    expect(cores).toHaveLength(DEMO_CORE_COUNT);
    const fast = cores.slice(0, 4).reduce((a, b) => a + b, 0) / 4;
    const efficient = cores.slice(-6).reduce((a, b) => a + b, 0) / 6;
    expect(fast).toBeGreaterThan(efficient);
  });

  it("has plausible, normal demo memory", () => {
    const memory = demoMemory(0);
    expect(memory.totalBytes).toBe(DEMO_TOTAL_MEMORY_BYTES);
    expect(usedFraction(memory)).toBeGreaterThanOrEqual(0.6);
    expect(usedFraction(memory)).toBeLessThanOrEqual(0.8);
    expect(memory.pressure).toBe("normal");
    expect(memorySummary(memory)).toBe("11.4 / 16 GB");
  });
});

describe("SystemMonitorState", () => {
  const snapshot = (at: number, busy: number, fields: Partial<SystemStatsSnapshot> = {}): SystemStatsSnapshot => ({
    capturedAt: at,
    processors: [{ idle: at * 100 - busy, kernel: at * 100, user: 0 }],
    memory: { totalBytes: 16 * GIB, availableBytes: 6 * GIB },
    gpu: 0.25,
    ...fields,
  });

  it("needs two readings a second apart for CPU, and keeps histories", () => {
    const state = new SystemMonitorState();
    state.apply(snapshot(1, 0));
    expect(state.cpu).toBeUndefined();
    expect(state.memory?.usedBytes).toBe(10 * GIB);
    expect(state.gpu).toBe(0.25);
    state.apply(snapshot(2, 40));
    expect(state.cpu?.total).toBeCloseTo(0.4, 9);
    expect(state.cpuHistory.elements).toHaveLength(1);
    expect(state.gpuHistory.elements).toEqual([0.25, 0.25]);
    expect(state.memorySeries.points).toHaveLength(2);
  });

  it("restarts every history after a gap, so a sparkline covers one unbroken window", () => {
    const state = new SystemMonitorState();
    state.apply(snapshot(1, 0));
    state.apply(snapshot(2, 30));
    state.apply(snapshot(10, 80));
    expect(state.cpu).toBeUndefined();
    expect(state.cpuHistory.isEmpty).toBe(true);
    expect(state.gpuHistory.elements).toEqual([0.25]);
    expect(state.memoryHistory.count).toBe(1);
  });

  it("shows missing readings as unknown", () => {
    const state = new SystemMonitorState();
    state.apply({ capturedAt: 1 });
    state.apply({ capturedAt: 2 });
    expect(state.cpu).toBeUndefined();
    expect(state.gpu).toBeUndefined();
    expect(state.memory).toBeUndefined();
    expect(percent(state.gpu)).toBe(UNAVAILABLE);
  });

  it("opens demo mode with a full minute of history", () => {
    const demo = SystemMonitorState.demo();
    expect(demo.cpuHistory.count).toBe(HISTORY_CAPACITY);
    expect(demo.cpu?.perCore).toHaveLength(DEMO_CORE_COUNT);
    expect(demo.cpuSeries.points[0]?.x).toBe(0);
  });
});
