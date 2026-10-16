import { OnePoleFilter } from "./filters";
import { NoiseRandom, type Seed } from "./random";

const f = Math.fround;

/** The Mac's default generator seed. */
export const DEFAULT_SEED: Seed = 0x5eedn;

/** Port of NoiseColor: white (flat), pink (3 dB per octave) and brown (6 dB per octave). */
export type NoiseColor = "white" | "pink" | "brown";

/** Every sound targets this RMS so they sound about equally loud and leave headroom for mixing. */
export const NOISE_TARGET_RMS = f(0.2);
/** Uniform white in -1 ..< 1 has RMS 1/sqrt(3). */
const WHITE_RMS = f(1 / f(Math.sqrt(3)));
const SQRT_3 = f(Math.sqrt(3));

/* Leaky-integrator corner and low cut for brown noise, in hertz. */
const LEAK_CORNER = 10;
const LOW_CUT_CORNER = 20;

/**
 * The brown noise leak coefficient and the gain that undoes what the leaky
 * integrator and the low cut take away, for `sampleRate`.
 */
export function brownNoiseTuning(sampleRate: number): { coefficient: number; gain: number } {
  const a = Math.exp((-2 * Math.PI * LEAK_CORNER) / sampleRate);
  const survivingPower = (((1 - a) / (1 + a)) * LEAK_CORNER) / (LEAK_CORNER + LOW_CUT_CORNER);
  return { coefficient: f(a), gain: f(Math.sqrt(1 / survivingPower)) };
}

/**
 * Port of PinkState: Paul Kellet's refined pink filter, seven parallel
 * one-pole stages whose staggered corners sum to a 1/f slope.
 */
export class PinkState {
  private b0 = 0;
  private b1 = 0;
  private b2 = 0;
  private b3 = 0;
  private b4 = 0;
  private b5 = 0;
  private b6 = 0;

  /** Normalizes the output to unit RMS for unit-variance input. */
  static readonly outputGain = f(0.3754);

  process(white: number): number {
    const w = f(white * SQRT_3);
    this.b0 = f(f(f(0.99886) * this.b0) + f(w * f(0.0555179)));
    this.b1 = f(f(f(0.99332) * this.b1) + f(w * f(0.0750759)));
    this.b2 = f(f(f(0.969) * this.b2) + f(w * f(0.153852)));
    this.b3 = f(f(f(0.8665) * this.b3) + f(w * f(0.3104856)));
    this.b4 = f(f(f(0.55) * this.b4) + f(w * f(0.5329522)));
    this.b5 = f(f(f(-0.7616) * this.b5) - f(w * f(0.016898)));
    const pink = f(
      f(f(f(f(f(f(f(this.b0 + this.b1) + this.b2) + this.b3) + this.b4) + this.b5) + this.b6) + f(w * f(0.5362))),
    );
    this.b6 = f(w * f(0.115926));
    return f(pink * PinkState.outputGain);
  }
}

/** Port of NoiseGenerator: one color of noise, sample by sample, at `NOISE_TARGET_RMS`. */
export class NoiseGenerator {
  readonly color: NoiseColor;
  private readonly random: NoiseRandom;
  private readonly pink = new PinkState();
  private brown = 0;
  private readonly brownCoefficient: number;
  private readonly brownGain: number;
  private readonly lowCut: OnePoleFilter;

  constructor(color: NoiseColor, sampleRate: number, seed: Seed = DEFAULT_SEED) {
    this.color = color;
    this.random = new NoiseRandom(seed);
    const tuning = brownNoiseTuning(sampleRate);
    this.brownCoefficient = tuning.coefficient;
    this.brownGain = tuning.gain;
    /* Inaudible DC and sub-bass would only eat headroom and move speaker cones. */
    this.lowCut = new OnePoleFilter("highPass", LOW_CUT_CORNER, sampleRate);
  }

  next(): number {
    const white = this.random.nextBipolar();
    let raw: number;
    switch (this.color) {
      case "white":
        raw = f(white / WHITE_RMS);
        return f(raw * NOISE_TARGET_RMS);
      case "pink":
        raw = this.pink.process(white);
        break;
      case "brown": {
        const c = this.brownCoefficient;
        this.brown = f(f(c * this.brown) + f(f(1 - c) * white));
        raw = f(f(this.brown * this.brownGain) / WHITE_RMS);
        break;
      }
    }
    return f(this.lowCut.process(raw) * NOISE_TARGET_RMS);
  }

  /** Fills `buffer` with consecutive samples. */
  fill(buffer: Float32Array): void {
    for (let i = 0; i < buffer.length; i++) buffer[i] = this.next();
  }
}
