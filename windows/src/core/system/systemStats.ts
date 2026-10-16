import type { Instant } from "../time";
import { type CPUUsage, cpuUsage, type ProcessorTimes } from "./cpuUsage";
import { HistorySeries, RingBuffer } from "./history";
import { memoryFromStatus, memoryFromUsed, type MemoryStats, usedFraction } from "./memoryStats";
import { demoCPU, demoGPU, demoMemory, demoPerCore } from "./systemDemoData";

/*
 * The stats snapshot the Rust host sends once a second while the System tab
 * is visible, and the panel state built from it. Field names are camelCase
 * JSON; the host's serde types mirror these exactly. Sampling stops when the
 * tab is hidden, so nothing runs in the background.
 */

/** One reading of the machine. Each part is absent when Windows wouldn't report it. */
export interface SystemStatsSnapshot {
  /** When the host took the reading, seconds since 1970 (from a monotonic clock is fine: only gaps matter). */
  capturedAt: Instant;
  /**
   * Cumulative per-core times (NtQuerySystemInformation's
   * SystemProcessorPerformanceInformation, 100 ns units, `kernel` including
   * `idle`). Two readings make a usage.
   */
  processors?: ProcessorTimes[];
  /** From GlobalMemoryStatusEx: `ullTotalPhys` and `ullAvailPhys`, in bytes. */
  memory?: { totalBytes: number; availableBytes: number };
  /**
   * GPU busy fraction, 0 to 1: the busiest engine type summed over
   * processes from the PDH counter `\GPU Engine(*)\Utilization Percentage`,
   * divided by 100. Absent when no adapter reports it.
   */
  gpu?: number;
}

/**
 * One reading the Rust host sends (`system:stats`), with the load already
 * worked out from PDH counters: CPU is absent on the first reading (a rate
 * needs two samples), GPU where no adapter reports, memory if Windows
 * won't say.
 */
export interface SystemReading {
  capturedAt: Instant;
  cpu?: CPUUsage;
  memory?: { usedBytes: number; totalBytes: number };
  gpu?: number;
}

/** Samples kept per sparkline: one minute at one sample a second. */
export const HISTORY_CAPACITY = 60;

/**
 * A baseline older than this (from before the panel was last hidden) would
 * report the average over the whole gap, so it is replaced instead, and the
 * histories restart so each sparkline covers one unbroken window.
 */
export const MAX_SAMPLE_GAP = 3;

/**
 * Port of SystemMonitor's logic: the System panel's live readings and their
 * histories, fed by host snapshots (or demo data). Undefined values show as
 * "-": CPU until two readings a second apart exist, GPU when no adapter
 * reports, memory when Windows doesn't.
 */
export class SystemMonitorState {
  cpu: CPUUsage | undefined;
  gpu: number | undefined;
  memory: MemoryStats | undefined;
  readonly cpuHistory = new RingBuffer<number>(HISTORY_CAPACITY);
  readonly gpuHistory = new RingBuffer<number>(HISTORY_CAPACITY);
  /** Used-memory fraction over time. */
  readonly memoryHistory = new RingBuffer<number>(HISTORY_CAPACITY);
  private previous: { processors: ProcessorTimes[]; at: Instant } | undefined;
  /** When the last reading of either shape arrived, for the gap rule. */
  private previousAt: Instant | undefined;

  /** One reading: updates the values and histories, restarting them after a gap. */
  apply(snapshot: SystemStatsSnapshot): void {
    const processors = snapshot.processors ?? [];
    const continuous = this.previous !== undefined && this.continuous(snapshot.capturedAt);
    const cpu = continuous && this.previous ? cpuUsage(this.previous.processors, processors) : undefined;
    this.previous = { processors, at: snapshot.capturedAt };
    const memory = snapshot.memory ? memoryFromStatus(snapshot.memory.totalBytes, snapshot.memory.availableBytes) : undefined;
    this.record(snapshot.capturedAt, continuous, cpu, snapshot.gpu, memory);
  }

  /**
   * One reading the host already turned into usage (Windows' PDH counters
   * give rates, not ticks), under the same gap and history rules as `apply`.
   * The host's first reading has no CPU value, which also restarts the
   * histories, so each sparkline covers one unbroken window.
   */
  applyReading(reading: SystemReading): void {
    this.previous = undefined;
    const continuous = this.continuous(reading.capturedAt);
    const cpu = continuous ? reading.cpu : undefined;
    const memory = reading.memory ? memoryFromUsed(reading.memory.usedBytes, reading.memory.totalBytes) : undefined;
    this.record(reading.capturedAt, continuous, cpu, reading.gpu, memory);
  }

  private continuous(at: Instant): boolean {
    return this.previousAt !== undefined && at - this.previousAt < MAX_SAMPLE_GAP;
  }

  private record(at: Instant, continuous: boolean, cpu: CPUUsage | undefined, gpu: number | undefined, memory: MemoryStats | undefined): void {
    this.previousAt = at;
    this.cpu = cpu;
    if (!continuous) {
      this.cpuHistory.removeAll();
      this.gpuHistory.removeAll();
      this.memoryHistory.removeAll();
    }
    if (cpu) this.cpuHistory.append(cpu.total);

    this.gpu = gpu === undefined || !Number.isFinite(gpu) ? undefined : Math.min(Math.max(gpu, 0), 1);
    if (this.gpu !== undefined) this.gpuHistory.append(this.gpu);

    this.memory = memory;
    if (memory) this.memoryHistory.append(usedFraction(memory));
  }

  /** One demo step: the same curves as the Mac's demo mode. */
  applyDemo(step: number): void {
    const total = demoCPU(step);
    this.cpu = { total, perCore: demoPerCore(step) };
    this.cpuHistory.append(total);
    this.gpu = demoGPU(step);
    this.gpuHistory.append(this.gpu);
    this.memory = demoMemory(step);
    this.memoryHistory.append(usedFraction(this.memory));
  }

  /** A demo monitor with a full minute of history, as demo mode opens. */
  static demo(): SystemMonitorState {
    const state = new SystemMonitorState();
    for (let step = 1; step <= HISTORY_CAPACITY; step++) state.applyDemo(step);
    return state;
  }

  /** The sparklines, ready to draw. */
  get cpuSeries(): HistorySeries {
    return new HistorySeries(this.cpuHistory.elements, HISTORY_CAPACITY);
  }

  get gpuSeries(): HistorySeries {
    return new HistorySeries(this.gpuHistory.elements, HISTORY_CAPACITY);
  }

  get memorySeries(): HistorySeries {
    return new HistorySeries(this.memoryHistory.elements, HISTORY_CAPACITY);
  }
}
