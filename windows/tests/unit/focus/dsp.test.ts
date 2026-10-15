import { describe, expect, it } from "vitest";
import { FocusMix } from "../../../src/core/focus/focusMix";
import { loudnessGain, type SynthesizedFocusSound } from "../../../src/core/focus/focusSound";
import { BiquadFilter, biquadCoefficients, onePoleCoefficient, OnePoleFilter } from "../../../src/core/focus/dsp/filters";
import {
  GainRamp,
  focusSoftClip,
  layerTargetGain,
  raisedCosine,
  raisedCosineCurve,
  volumeAmplitude,
} from "../../../src/core/focus/dsp/gain";
import { NOISE_TARGET_RMS, NoiseGenerator, brownNoiseTuning, type NoiseColor } from "../../../src/core/focus/dsp/noise";
import { NoiseRandom, type Seed } from "../../../src/core/focus/dsp/random";
import { SynthGenerator, layerSeed, recordingStartFraction } from "../../../src/core/focus/dsp/soundGenerator";
import { SAMPLE_RATE, decibels, loudness, mean, peak, powerNear, rms } from "../../support/signalAnalysis";

/*
 * Ports the Mac's FocusDSPTests, FocusAmbienceTests and FocusLoudnessTests
 * checks for the synthesized sounds: the random source bit for bit, filter
 * coefficients, every sound's level against NoiseGenerator.targetRMS, the
 * noise slopes, determinism per seed, and loudness after the trims.
 */

const SYNTHESIZED: SynthesizedFocusSound[] = ["brown", "pink", "white", "rain", "fireplace"];

/* The reference xorshift64* in BigInt, straight from FocusDSP.swift. */
function referenceStream(seed: Seed, count: number): bigint[] {
  const mask = (1n << 64n) - 1n;
  let state = seed === 0n ? 0x9e3779b97f4a7c15n : seed;
  const out: bigint[] = [];
  for (let i = 0; i < count; i++) {
    state ^= state >> 12n;
    state = (state ^ (state << 25n)) & mask;
    state ^= state >> 27n;
    out.push((state * 0x2545f4914f6cdd1dn) & mask);
  }
  return out;
}

/* Skips the first half second so filter start-up doesn't skew results. */
function render(sound: SynthesizedFocusSound, seconds: number, seed: Seed = 42n): Float32Array {
  const generator = new SynthGenerator(sound, SAMPLE_RATE, seed);
  const buffer = new Float32Array(Math.trunc(SAMPLE_RATE * seconds));
  generator.fill(buffer);
  return buffer.subarray(SAMPLE_RATE / 2);
}

function noise(color: NoiseColor, seconds = 4): Float32Array {
  const generator = new NoiseGenerator(color, SAMPLE_RATE, 42n);
  const buffer = new Float32Array(SAMPLE_RATE * seconds);
  generator.fill(buffer);
  return buffer.subarray(SAMPLE_RATE / 2);
}

describe("NoiseRandom", () => {
  it("matches xorshift64* bit for bit", () => {
    for (const seed of [0n, 0x5eedn, 42n, (1n << 64n) - 1n, 0x9e3779b9n * 5n + 0x5eedn]) {
      const random = new NoiseRandom(seed);
      const expected = referenceStream(seed, 2_000);
      const actual = expected.map(() => random.nextUInt64());
      expect(actual).toEqual(expected);
    }
  });

  it("stays in 0 ..< 1 with plenty of distinct values, even from a zero seed", () => {
    const random = new NoiseRandom(0n);
    const seen = new Set<number>();
    for (let i = 0; i < 10_000; i++) {
      const unit = random.nextUnit();
      expect(unit >= 0 && unit < 1).toBe(true);
      expect(Math.fround(unit)).toBe(unit);
      seen.add(unit);
    }
    expect(seen.size).toBeGreaterThan(9_900);
  });

  it("derives layer seeds and loop start points like FocusMixer", () => {
    expect(layerSeed(0x5eedn, "brown")).toBe(0x5eedn);
    expect(layerSeed(0x5eedn, "cafe")).toBe(0x5eedn + 5n * 0x9e3779b9n);
    expect(layerSeed((1n << 64n) - 1n, "pink")).toBe(0x9e3779b8n);
    const start = recordingStartFraction(0x5eedn);
    expect(start).toBeGreaterThanOrEqual(0);
    expect(start).toBeLessThan(1);
    expect(recordingStartFraction(0x5eedn)).toBe(start);
  });
});

describe("filters", () => {
  it("computes the Mac's coefficients in double and rounds them to single", () => {
    expect(onePoleCoefficient(20, 48_000)).toBe(Math.fround(Math.exp((-2 * Math.PI * 20) / 48_000)));
    expect(onePoleCoefficient(0, 48_000)).toBe(Math.fround(Math.exp((-2 * Math.PI) / 48_000)));
    expect(onePoleCoefficient(1e9, 48_000)).toBe(Math.fround(Math.exp(-2 * Math.PI * 0.49)));

    const w0 = (2 * Math.PI * 500) / 48_000;
    const alpha = Math.sin(w0) / (2 * 0.7071);
    const a0 = 1 + alpha;
    expect(biquadCoefficients("highPass", 500, 0.7071, 48_000)).toEqual({
      b0: Math.fround((1 + Math.cos(w0)) / 2 / a0),
      b1: Math.fround(-(1 + Math.cos(w0)) / a0),
      b2: Math.fround((1 + Math.cos(w0)) / 2 / a0),
      a1: Math.fround((-2 * Math.cos(w0)) / a0),
      a2: Math.fround((1 - alpha) / a0),
    });
    const band = biquadCoefficients("bandPass", 500, 0.8, 48_000);
    expect(band.b1).toBe(0);
    expect(band.b2).toBe(-band.b0);
  });

  it("passes and stops what each kind should", () => {
    const gainAt = (filter: { process(x: number): number }, frequency: number): number => {
      const out = new Float32Array(SAMPLE_RATE);
      for (let i = 0; i < out.length; i++) out[i] = filter.process(Math.sin((2 * Math.PI * frequency * i) / SAMPLE_RATE));
      return rms(out.subarray(SAMPLE_RATE / 2)) / Math.SQRT1_2;
    };
    expect(gainAt(new BiquadFilter("lowPass", 1000, SAMPLE_RATE), 100)).toBeCloseTo(1, 1);
    expect(gainAt(new BiquadFilter("lowPass", 1000, SAMPLE_RATE), 8000)).toBeLessThan(0.05);
    expect(gainAt(new BiquadFilter("highPass", 1000, SAMPLE_RATE), 100)).toBeLessThan(0.02);
    expect(gainAt(new BiquadFilter("bandPass", 1000, SAMPLE_RATE, 2), 1000)).toBeCloseTo(1, 1);
    expect(gainAt(new OnePoleFilter("highPass", 20, SAMPLE_RATE), 1000)).toBeCloseTo(1, 2);
  });

  it("tunes brown noise to undo the leak and the low cut", () => {
    const { coefficient, gain } = brownNoiseTuning(48_000);
    expect(coefficient).toBe(Math.fround(Math.exp((-2 * Math.PI * 10) / 48_000)));
    const a = Math.exp((-2 * Math.PI * 10) / 48_000);
    expect(gain).toBe(Math.fround(Math.sqrt(1 / (((1 - a) / (1 + a)) * (10 / 30)))));
  });
});

describe("noise colors", () => {
  it("play at the shared level without DC or clipping", () => {
    for (const color of ["white", "pink", "brown"] as const) {
      const x = noise(color);
      expect(Math.abs(rms(x) - NOISE_TARGET_RMS), `${color} level`).toBeLessThan(0.015);
      expect(Math.abs(mean(x)), `${color} DC`).toBeLessThan(0.02);
      expect(peak(x), `${color} peak`).toBeLessThan(1);
    }
  });

  it("fall 0, 3 and 6 dB per octave", () => {
    const white = noise("white");
    expect(decibels(powerNear(white, 250) / powerNear(white, 4000))).toBeCloseTo(0, -0.3);
    const pink = noise("pink");
    expect(Math.abs(decibels(powerNear(pink, 250) / powerNear(pink, 4000)) - 12)).toBeLessThan(1.5);
    const brown = noise("brown");
    expect(Math.abs(decibels(powerNear(brown, 250) / powerNear(brown, 2000)) - 18)).toBeLessThan(1.5);
  });
});

describe("synthesized sounds", () => {
  it("are deterministic per seed and differ between seeds", () => {
    for (const sound of SYNTHESIZED) {
      const a = new SynthGenerator(sound, SAMPLE_RATE, 9n);
      const b = new SynthGenerator(sound, SAMPLE_RATE, 9n);
      const c = new SynthGenerator(sound, SAMPLE_RATE, 10n);
      const first = Array.from({ length: 4_096 }, () => a.next());
      expect(Array.from({ length: 4_096 }, () => b.next()), sound).toEqual(first);
      expect(Array.from({ length: 4_096 }, () => c.next()), sound).not.toEqual(first);
      expect(first.every((value) => Math.fround(value) === value), `${sound} stays single precision`).toBe(true);
    }
  });

  it("all play at NoiseGenerator.targetRMS without DC or wild peaks", () => {
    for (const sound of SYNTHESIZED) {
      const x = render(sound, 10);
      expect(Math.abs(rms(x) - NOISE_TARGET_RMS), `${sound} level ${rms(x)}`).toBeLessThan(0.03);
      expect(Math.abs(mean(x)), `${sound} DC`).toBeLessThan(0.01);
      expect(peak(x), `${sound} peak`).toBeLessThan(1.6);
    }
  });

  it("reach the shared loudness target once trimmed, so switching never jumps", () => {
    const levels = SYNTHESIZED.map((sound) => {
      const x = Float32Array.from(render(sound, 10), (value) => value * loudnessGain(sound));
      return loudness(x);
    });
    levels.forEach((level, index) => expect(Math.abs(level - -17), `${SYNTHESIZED[index]} at ${level} LUFS`).toBeLessThan(1));
    expect(Math.max(...levels) - Math.min(...levels)).toBeLessThan(1.5);
  });
});

describe("gains", () => {
  it("map volume on a squared curve and trim each layer", () => {
    expect(volumeAmplitude(0.5)).toBe(0.25);
    expect(volumeAmplitude(Number.NaN)).toBe(0);
    expect(volumeAmplitude(4)).toBe(1);
    expect(layerTargetGain(FocusMix.single("white"), "white")).toBe(Math.fround(loudnessGain("white")));
    expect(layerTargetGain(FocusMix.single("white"), "rain")).toBe(0);
  });

  it("glide along a raised cosine with flat ends", () => {
    expect(raisedCosine(0, 1, 0, 100)).toBe(0);
    expect(raisedCosine(0, 1, 50, 100)).toBeCloseTo(0.5, 6);
    expect(raisedCosine(0, 1, 100, 100)).toBe(1);
    expect(raisedCosine(0, 1, 1, 100)).toBeLessThan(0.001);
    const curve = raisedCosineCurve(0.2, 0.8, 5);
    expect(Array.from(curve)).toEqual([0.2, raisedCosine(0.2, 0.8, 1, 4), raisedCosine(0.2, 0.8, 2, 4), raisedCosine(0.2, 0.8, 3, 4), Math.fround(0.8)].map(Math.fround));

    const ramp = new GainRamp(0);
    ramp.ramp(1, 4);
    const values = [ramp.next(), ramp.next()];
    ramp.ramp(0, 2);
    expect(ramp.isRamping).toBe(true);
    values.push(ramp.next(), ramp.next(), ramp.next());
    expect(values[1]).toBeCloseTo(0.5, 6);
    expect(values[2]).toBeCloseTo(0.25, 6);
    expect(values.slice(3)).toEqual([0, 0]);
    expect(ramp.isRamping).toBe(false);
  });

  it("soft-clips only above the knee", () => {
    expect(focusSoftClip(0.4)).toBe(0.4);
    expect(focusSoftClip(-0.5)).toBe(-0.5);
    expect(focusSoftClip(0.75)).toBeGreaterThan(0.7);
    expect(focusSoftClip(0.75)).toBeLessThan(0.75);
    expect(focusSoftClip(100)).toBeLessThanOrEqual(1);
    expect(focusSoftClip(-100)).toBe(-focusSoftClip(100));
  });
});
