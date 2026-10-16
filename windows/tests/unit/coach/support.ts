import { SplitMix64 } from "../../../src/core/pets/petAnimator";
import type { RandomSource } from "../../../src/core/motivation/randomSource";

// Generators for the coach and motivation tests, after the Mac tests' SeededGenerator and FixedRandom.

/** A reproducible source over SplitMix64. */
export function seeded(seed: number): RandomSource {
  const generator = new SplitMix64(seed);
  return () => generator.nextIn(0, 1);
}

/** Every draw is `fraction`: 0 always wins a roll and picks the first element; 0.9 loses. */
export function fixed(fraction: number): RandomSource {
  return () => fraction;
}

/** `hour`:00 UTC on the `day`th day after Monday 2026-10-05, as the Mac tests' `time(day:hour:)`. */
export function utcTime(day: number, hour = 14, minute = 0): number {
  return Date.UTC(2026, 9, 5 + day, hour, minute) / 1000;
}
