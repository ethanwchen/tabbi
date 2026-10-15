import type { MemoryStats } from "./memoryStats";

/*
 * Port of SystemFormat: display strings for system metrics. A missing
 * value renders as a plain hyphen, so an unavailable metric reads as
 * unknown, never as 0.
 */

export const UNAVAILABLE = "-";

const GIB = 1_073_741_824;

/** Swift's `.rounded()`: half away from zero. */
function round(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

/** 0.423 reads "42%"; values are clamped to 0 to 100. */
export function percent(fraction: number | undefined): string {
  if (fraction === undefined || !Number.isFinite(fraction)) return UNAVAILABLE;
  return `${round(Math.min(Math.max(fraction, 0), 1) * 100)}%`;
}

/**
 * Bytes as binary gigabytes with one decimal, dropping a trailing ".0" so
 * installed sizes read "16" rather than "16.0". Live values pass
 * `alwaysShowTenths` so the headline doesn't jump between "34" and "34.1".
 */
export function gigabytes(bytes: number | undefined, alwaysShowTenths = false): string {
  if (bytes === undefined) return UNAVAILABLE;
  const tenths = round((bytes / GIB) * 10);
  if (!alwaysShowTenths && tenths % 10 === 0) return String(tenths / 10);
  return `${Math.trunc(tenths / 10)}.${tenths % 10}`;
}

/** "12.4 / 16 GB", or a plain hyphen when memory is unknown. */
export function memorySummary(stats: MemoryStats | undefined): string {
  if (!stats) return UNAVAILABLE;
  return `${gigabytes(stats.usedBytes, true)} / ${gigabytes(stats.totalBytes)} GB`;
}
