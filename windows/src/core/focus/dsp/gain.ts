import { FocusMix } from "../focusMix";
import { loudnessGain, type FocusSound } from "../focusSound";

const f = Math.fround;

/** Port of FocusMixer.fadeSeconds: fade in, fade out and crossfade time between mixes. */
export const FADE_SECONDS = 2;
/** Port of FocusMixer.volumeGlideSeconds: fast enough to feel immediate, slow enough never to zip. */
export const VOLUME_GLIDE_SECONDS = 0.05;

/** Port of FocusMixer.clampVolume: 0...1, and silence for a value that isn't a number. */
export function clampVolume(volume: number): number {
  return Number.isFinite(volume) ? f(Math.min(Math.max(volume, 0), 1)) : 0;
}

/**
 * Port of FocusMixer.amplitude(forVolume:): loudness is roughly logarithmic,
 * so a squared curve makes the slider feel even across its travel.
 */
export function volumeAmplitude(volume: number): number {
  const v = clampVolume(volume);
  return f(v * v);
}

/**
 * The gain a sound's layer glides to for `mix`, as FocusMixer.setMix sets it:
 * its share of the mix times its loudness trim, or 0 when it is not in the mix.
 */
export function layerTargetGain(mix: FocusMix, sound: FocusSound): number {
  return f((mix.gains.get(sound) ?? 0) * loudnessGain(sound));
}

/**
 * The raised-cosine (S-shaped) value of a glide from `start` to `target` after
 * `position` of `length` steps: zero slope at both ends, so no audible corner
 * where a fade starts or lands, which a linear ramp has.
 */
export function raisedCosine(start: number, target: number, position: number, length: number): number {
  if (position >= length) return f(target);
  const t = f(position / length);
  const shaped = f(f(0.5) - f(f(0.5) * f(Math.cos(f(f(Math.PI) * t)))));
  return f(start + f(f(target - start) * shaped));
}

/**
 * The glide as a value curve for `AudioParam.setValueCurveAtTime`, `points`
 * long, from `start` to `target`. Web Audio interpolates linearly between the
 * points, so a few hundred points trace the S-curve closely.
 */
export function raisedCosineCurve(start: number, target: number, points: number): Float32Array {
  const count = Math.max(Math.trunc(points), 2);
  const curve = new Float32Array(count);
  for (let i = 0; i < count; i++) curve[i] = raisedCosine(start, target, i, count - 1);
  return curve;
}

/**
 * Port of GainRamp: a gain that glides to its target over a number of samples
 * instead of jumping, along the raised-cosine curve. Retargeting mid-ramp
 * starts from wherever the gain is now.
 */
export class GainRamp {
  value: number;
  target: number;
  private start: number;
  private position = 0;
  private length = 0;

  constructor(value = 0) {
    this.value = f(value);
    this.target = this.value;
    this.start = this.value;
  }

  /** True while gliding toward `target`. */
  get isRamping(): boolean {
    return this.position < this.length;
  }

  ramp(target: number, samples: number): void {
    this.start = this.value;
    this.target = f(target);
    this.position = 0;
    this.length = Math.max(samples, 0);
    if (this.length === 0) this.value = this.target;
  }

  /** Advances one sample and returns the gain to apply to it. */
  next(): number {
    if (this.position >= this.length) return this.value;
    this.position += 1;
    this.value = raisedCosine(this.start, this.target, this.position, this.length);
    return this.value;
  }
}

/**
 * Port of focusSoftClip: keeps summed layers inside -1...1 without a hard
 * edge. Exactly linear up to the knee at 0.5, so normal levels pass untouched;
 * only rare peaks bend, along a tanh curve that meets the line with the same
 * slope.
 */
export function focusSoftClip(x: number): number {
  const knee = f(0.5);
  const magnitude = Math.abs(x);
  if (!(magnitude > knee)) return x;
  const bent = f(knee + f(f(1 - knee) * f(Math.tanh(f(f(magnitude - knee) / f(1 - knee))))));
  return x < 0 ? -bent : bent;
}
