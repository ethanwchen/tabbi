import { FOCUS_SOUNDS, type FocusSound, type SynthesizedFocusSound } from "../focusSound";
import { FireplaceSynth, RainSynth } from "./ambience";
import { DEFAULT_SEED, NoiseGenerator } from "./noise";
import { NoiseRandom, seedAdd, seedMultiply, seedXor, type Seed } from "./random";

interface Voice {
  next(): number;
}

/**
 * Port of FocusSoundGenerator for the synthesized sounds: renders brown,
 * pink or white noise, rain or the fireplace at about NOISE_TARGET_RMS. The
 * cafe is a recording, which the Web Audio engine loops itself.
 */
export class SynthGenerator {
  readonly sound: SynthesizedFocusSound;
  private readonly voice: Voice;

  constructor(sound: SynthesizedFocusSound, sampleRate: number, seed: Seed = DEFAULT_SEED) {
    this.sound = sound;
    switch (sound) {
      case "brown":
      case "pink":
      case "white":
        this.voice = new NoiseGenerator(sound, sampleRate, seed);
        break;
      case "rain":
        this.voice = new RainSynth(sampleRate, seed);
        break;
      case "fireplace":
        this.voice = new FireplaceSynth(sampleRate, seed);
        break;
    }
  }

  next(): number {
    return this.voice.next();
  }

  /** Fills `buffer` with consecutive samples. */
  fill(buffer: Float32Array): void {
    for (let i = 0; i < buffer.length; i++) buffer[i] = this.voice.next();
  }
}

/**
 * The seed FocusMixer gives `sound`'s generator, so two layers never share a
 * random stream: the mixer's seed plus the sound's index times 0x9E3779B9.
 */
export function layerSeed(mixerSeed: Seed, sound: FocusSound): Seed {
  return seedAdd(mixerSeed, seedMultiply(BigInt(FOCUS_SOUNDS.indexOf(sound)), 0x9e3779b9n));
}

/**
 * Port of RecordingLoop's start point: each seed opens the loop at a different
 * place, so two mixers (or a restart) don't always start on the same moment.
 * A fraction of the loop, 0 ..< 1.
 */
export function recordingStartFraction(seed: Seed): number {
  return new NoiseRandom(seedXor(seed, 0x100fn)).nextUnit();
}
