import { memoryStats, type MemoryStats } from "./memoryStats";

/*
 * Port of SystemDemoData: deterministic, realistic metrics for demo runs, so
 * snapshots never depend on the machine they were rendered on. The same
 * curves as the Mac, so both apps' screenshots move alike.
 */

/** Cores of a typical laptop: four fast cores first, then six efficient ones. */
export const DEMO_CORE_COUNT = 10;
export const DEMO_TOTAL_MEMORY_BYTES = 16 * 1_073_741_824;

const clamp = (value: number) => Math.min(Math.max(value, 0), 1);

/** Whole-machine CPU busy fraction at a step (one step per second): a wandering line with an occasional burst. */
export function demoCPU(step: number): number {
  const t = step;
  return clamp(0.24 + 0.08 * Math.sin(t / 5.3) + 0.05 * Math.sin(t / 1.7) + 0.16 * Math.max(0, Math.sin(t / 9.1)) ** 6);
}

/** Per-core busy fractions at a step: the fast cores run hotter, and every core differs. */
export function demoPerCore(step: number): number[] {
  const total = demoCPU(step);
  return Array.from({ length: DEMO_CORE_COUNT }, (_, core) => {
    const bias = core < 4 ? 1.35 : 0.75;
    const wobble = 0.12 * Math.sin((step + core * 7) / 2.3);
    return clamp(total * bias + wobble);
  });
}

/** GPU busy fraction at a step: mostly idle with short spikes, like a compositor and the odd video frame. */
export function demoGPU(step: number): number {
  const t = step;
  return clamp(0.12 + 0.04 * Math.sin(t / 3.1) + 0.3 * Math.max(0, Math.sin(t / 6.7 + 1)) ** 8);
}

export function demoMemory(step: number): MemoryStats {
  const used = 11.4 + 0.3 * Math.sin(step / 11);
  return memoryStats(Math.trunc(used * 1_073_741_824), DEMO_TOTAL_MEMORY_BYTES, "normal");
}
