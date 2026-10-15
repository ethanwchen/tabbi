import { BiquadFilter } from "./filters";
import { NoiseGenerator } from "./noise";
import { NoiseRandom, seedAdd, seedXor, type Seed } from "./random";

/*
 * Procedural ambiences for focus mode, ported from the Mac's
 * FocusAmbience.swift: rain and a fireplace, after the layered recipes in Andy
 * Farnell's "Designing Sound". A filtered-noise bed, slow random modulation so
 * it never sounds like a loop, and sparse random events built from short
 * decaying bursts, calibrated to NOISE_TARGET_RMS. Single precision throughout.
 */

const f = Math.fround;

/** Port of Drift: a smoothly wandering random value (gusts of rain, flicker of a fire). */
export class Drift {
  private value: number;
  private target: number;
  private readonly lower: number;
  private readonly span: number;
  private readonly smoothing: number;
  private readonly meanHold: number;
  private countdown = 0;

  /** A new target is picked every 0.5 to 1.5 times `seconds`, and the value glides there. */
  constructor(lower: number, upper: number, seconds: number, sampleRate: number) {
    this.lower = f(lower);
    this.span = f(f(upper) - this.lower);
    this.value = f(this.lower + f(this.span / 2));
    this.target = this.value;
    this.meanHold = f(seconds * sampleRate);
    this.smoothing = f(1 - Math.exp(-2 / (seconds * sampleRate)));
  }

  next(random: NoiseRandom): number {
    this.countdown -= 1;
    if (this.countdown <= 0) {
      this.target = f(this.lower + f(this.span * random.nextUnit()));
      this.countdown = Math.trunc(f(this.meanHold * f(0.5 + random.nextUnit())));
    }
    this.value = f(this.value + f(f(this.target - this.value) * this.smoothing));
    return this.value;
  }
}

const ACTIVE_LEVEL = f(1e-4);

/** Port of BurstVoice: one short, exponentially decaying burst of band-passed noise. */
export class BurstVoice {
  level = 0;
  private decay = 0;
  private filter = new BiquadFilter("bandPass", 1000, 48_000);

  get isActive(): boolean {
    return this.level > ACTIVE_LEVEL;
  }

  trigger(level: number, decaySeconds: number, frequency: number, q: number, sampleRate: number): void {
    this.level = level;
    this.decay = f(Math.exp(-1 / (decaySeconds * sampleRate)));
    this.filter = new BiquadFilter("bandPass", frequency, sampleRate, q);
  }

  next(random: NoiseRandom): number {
    if (!this.isActive) return 0;
    const y = this.filter.process(f(random.nextBipolar() * this.level));
    this.level = f(this.level * this.decay);
    return y;
  }
}

/** Port of BurstPool: a fixed pool of voices; a new event takes a free voice or steals the quietest. */
export class BurstPool {
  private readonly voices: BurstVoice[];

  constructor(size: number) {
    this.voices = Array.from({ length: size }, () => new BurstVoice());
  }

  trigger(level: number, decaySeconds: number, frequency: number, q: number, sampleRate: number): void {
    let slot = 0;
    for (let i = 0; i < this.voices.length; i++) {
      const voice = this.voices[i];
      const best = this.voices[slot];
      if (voice !== undefined && best !== undefined && voice.level < best.level) slot = i;
    }
    this.voices[slot]?.trigger(level, decaySeconds, frequency, q, sampleRate);
  }

  next(random: NoiseRandom): number {
    let sum = 0;
    for (const voice of this.voices) sum = f(sum + voice.next(random));
    return sum;
  }
}

/**
 * Port of RainSynth: steady rain. A pink-noise hiss, a soft low wash, and
 * nearby drops as resonant ticks whose rate and loudness follow slow gusts.
 */
export class RainSynth {
  private readonly sampleRate: number;
  private readonly random: NoiseRandom;
  private readonly hiss: NoiseGenerator;
  private readonly hissHighPass: BiquadFilter;
  private readonly hissLowPass: BiquadFilter;
  private readonly wash: NoiseGenerator;
  private readonly washLowPass: BiquadFilter;
  private readonly gust: Drift;
  private readonly drops = new BurstPool(12);
  private readonly dropChance: number;

  /** Calibrated on the Mac so the long-term RMS matches NOISE_TARGET_RMS. */
  static readonly outputGain = f(1.38);

  constructor(sampleRate: number, seed: Seed) {
    this.sampleRate = sampleRate;
    this.random = new NoiseRandom(seedXor(seed, 0xa11n));
    this.hiss = new NoiseGenerator("pink", sampleRate, seedAdd(seed, 1n));
    this.hissHighPass = new BiquadFilter("highPass", 500, sampleRate);
    this.hissLowPass = new BiquadFilter("lowPass", 9_000, sampleRate);
    this.wash = new NoiseGenerator("brown", sampleRate, seedAdd(seed, 2n));
    this.washLowPass = new BiquadFilter("lowPass", 400, sampleRate);
    this.gust = new Drift(0.7, 1.0, 3, sampleRate);
    this.dropChance = f(60 / sampleRate);
  }

  next(): number {
    const random = this.random;
    const intensity = this.gust.next(random);
    let y = f(f(this.hissLowPass.process(this.hissHighPass.process(this.hiss.next())) * f(1.1)) * intensity);
    y = f(y + f(this.washLowPass.process(this.wash.next()) * f(0.35)));
    if (random.nextUnit() < f(this.dropChance * intensity)) {
      /* Squaring skews toward quiet drops with the odd close, loud one. */
      const loudness = random.nextUnit();
      const level = f(f(0.2) + f(f(f(1.1) * loudness) * loudness));
      const decaySeconds = f(f(0.003) + f(f(0.01) * random.nextUnit()));
      const frequency = f(1_800 + f(5_000 * random.nextUnit()));
      const q = f(2 + f(4 * random.nextUnit()));
      this.drops.trigger(level, decaySeconds, frequency, q, this.sampleRate);
    }
    y = f(y + this.drops.next(random));
    return f(y * RainSynth.outputGain);
  }
}

/**
 * Port of FireplaceSynth: a wood fire. A deep, slowly breathing roar, a
 * flickering mid-band body, a faint hiss, and crackles in small clusters with
 * the occasional louder pop.
 */
export class FireplaceSynth {
  private readonly sampleRate: number;
  private readonly random: NoiseRandom;
  private readonly roar: NoiseGenerator;
  private readonly roarLowPass: BiquadFilter;
  private readonly body: NoiseGenerator;
  private readonly bodyBand: BiquadFilter;
  private readonly hissHighPass: BiquadFilter;
  private readonly breath: Drift;
  private readonly flicker: Drift;
  private readonly crackleRate: Drift;
  private readonly crackles = new BurstPool(8);
  /** Remaining clicks in the current crackle cluster, and samples until the next. */
  private pendingClicks = 0;
  private clusterGap = 0;

  static readonly outputGain = f(1.06);

  constructor(sampleRate: number, seed: Seed) {
    this.sampleRate = sampleRate;
    this.random = new NoiseRandom(seedXor(seed, 0xf12en));
    this.roar = new NoiseGenerator("brown", sampleRate, seedAdd(seed, 3n));
    this.roarLowPass = new BiquadFilter("lowPass", 160, sampleRate);
    this.body = new NoiseGenerator("pink", sampleRate, seedAdd(seed, 4n));
    this.bodyBand = new BiquadFilter("bandPass", 500, sampleRate, 0.8);
    this.hissHighPass = new BiquadFilter("highPass", 3_000, sampleRate);
    this.breath = new Drift(0.55, 1.0, 1.5, sampleRate);
    this.flicker = new Drift(0.2, 1.0, 0.12, sampleRate);
    this.crackleRate = new Drift(1.5, 9, 2.5, sampleRate);
  }

  next(): number {
    const random = this.random;
    const glow = this.flicker.next(random);
    const roar = this.roarLowPass.process(this.roar.next());
    let y = f(f(roar * f(1.2)) * this.breath.next(random));
    y = f(y + f(f(this.bodyBand.process(this.body.next()) * f(0.6)) * glow));
    y = f(y + f(f(f(this.hissHighPass.process(random.nextBipolar()) * f(0.04)) * glow) * glow));

    /* Crackles arrive in small clusters, like wood splitting. */
    if (this.pendingClicks === 0) {
      const roll = random.nextUnit();
      if (roll < f(this.crackleRate.next(random) / f(this.sampleRate))) {
        this.pendingClicks = 1 + Math.trunc(f(random.nextUnit() * 4));
        this.clusterGap = 0;
      }
    }
    if (this.pendingClicks > 0) {
      this.clusterGap -= 1;
      if (this.clusterGap <= 0) {
        this.triggerCrackle();
        this.pendingClicks -= 1;
        this.clusterGap = Math.trunc(f(f(this.sampleRate) * f(f(0.002) + f(f(0.02) * random.nextUnit()))));
      }
    }
    y = f(y + this.crackles.next(random));
    return f(y * FireplaceSynth.outputGain);
  }

  private triggerCrackle(): void {
    const random = this.random;
    const loudness = random.nextUnit();
    if (random.nextUnit() < f(0.12)) {
      /* A deeper pop: a pocket of sap bursting. */
      const level = f(f(0.6) + f(f(0.8) * loudness));
      const decaySeconds = f(f(0.015) + f(f(0.025) * random.nextUnit()));
      const frequency = f(250 + f(450 * random.nextUnit()));
      this.crackles.trigger(level, decaySeconds, frequency, 2, this.sampleRate);
    } else {
      const level = f(f(0.3) + f(f(f(1.2) * loudness) * loudness));
      const decaySeconds = f(f(0.0015) + f(f(0.008) * random.nextUnit()));
      const frequency = f(1_200 + f(4_300 * random.nextUnit()));
      const q = f(f(1.5) + f(f(1.5) * random.nextUnit()));
      this.crackles.trigger(level, decaySeconds, frequency, q, this.sampleRate);
    }
  }
}
