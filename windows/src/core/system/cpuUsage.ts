/**
 * Cumulative scheduler counters for one core, the shape of Windows'
 * per-processor times (NtQuerySystemInformation's
 * SystemProcessorPerformanceInformation, in 100 ns units). `kernel`
 * includes `idle`, as Windows reports it. Port of CPUTicks, whose Mac
 * fields (user, system, idle, nice) map onto these.
 */
export interface ProcessorTimes {
  idle: number;
  kernel: number;
  user: number;
}

/** Port of CPUUsage: load between two snapshots, each value in 0 to 1. */
export interface CPUUsage {
  /** Busy fraction across all cores, weighted by each core's elapsed time. */
  total: number;
  /** Busy fraction per core, in the order Windows reports cores. */
  perCore: number[];
}

/**
 * Port of CPUUsageCalculator: two consecutive per-core snapshots as usage.
 * Undefined when they can't be compared (no cores, or the core count
 * changed), so the panel shows "-" instead of a misleading number. A
 * counter that went backwards (a reset) counts as no time.
 */
export function cpuUsage(previous: readonly ProcessorTimes[], current: readonly ProcessorTimes[]): CPUUsage | undefined {
  if (current.length === 0 || previous.length !== current.length) return undefined;
  let busyTotal = 0;
  let allTotal = 0;
  const perCore = current.map((now, index) => {
    const before = previous[index] ?? now;
    const idle = Math.max(now.idle - before.idle, 0);
    const kernel = Math.max(now.kernel - before.kernel, 0);
    const user = Math.max(now.user - before.user, 0);
    const all = kernel + user;
    const busy = Math.max(all - idle, 0);
    busyTotal += busy;
    allTotal += all;
    return all === 0 ? 0 : busy / all;
  });
  return { total: allTotal === 0 ? 0 : busyTotal / allTotal, perCore };
}
