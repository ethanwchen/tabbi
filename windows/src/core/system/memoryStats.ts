/**
 * Port of MemoryPressure: how hard the system is working to find memory,
 * as a green, yellow or red level.
 */
export type MemoryPressure = "normal" | "warning" | "critical";

const pressureOrder: Record<MemoryPressure, number> = { normal: 0, warning: 1, critical: 2 };

export function comparePressure(a: MemoryPressure, b: MemoryPressure): number {
  return pressureOrder[a] - pressureOrder[b];
}

/** Judged by the used fraction: under 80% normal, under 92% warning, else critical. */
export function pressureFromUsedFraction(fraction: number): MemoryPressure {
  if (fraction < 0.8) return "normal";
  if (fraction < 0.92) return "warning";
  return "critical";
}

export function pressureTitle(pressure: MemoryPressure): string {
  switch (pressure) {
    case "normal":
      return "Normal";
    case "warning":
      return "Elevated";
    case "critical":
      return "Critical";
  }
}

/** Port of MemoryStats: memory in use versus installed, plus the pressure level. */
export interface MemoryStats {
  usedBytes: number;
  totalBytes: number;
  pressure: MemoryPressure;
}

export function memoryStats(usedBytes: number, totalBytes: number, pressure: MemoryPressure): MemoryStats {
  return { usedBytes: Math.min(Math.max(usedBytes, 0), totalBytes), totalBytes, pressure };
}

/**
 * Stats from Windows' GlobalMemoryStatusEx, counted the way Task Manager's
 * "In use" does: installed physical memory minus what is available. There
 * is no kernel pressure level on Windows, so pressure comes from the used
 * fraction.
 */
export function memoryFromStatus(totalBytes: number, availableBytes: number): MemoryStats {
  const used = Math.min(Math.max(totalBytes - availableBytes, 0), totalBytes);
  const fraction = totalBytes === 0 ? 0 : used / totalBytes;
  return memoryStats(used, totalBytes, pressureFromUsedFraction(fraction));
}

/** Used fraction in 0 to 1. */
export function usedFraction(stats: MemoryStats): number {
  return stats.totalBytes === 0 ? 0 : stats.usedBytes / stats.totalBytes;
}
