const f = Math.fround;

/** Port of OnePoleFilter.Kind. */
export type OnePoleKind = "lowPass" | "highPass";

/** The one-pole feedback coefficient for `cutoff`, clamped to 1 Hz...0.49 of the rate, in single precision. */
export function onePoleCoefficient(cutoff: number, sampleRate: number): number {
  const clamped = Math.min(Math.max(cutoff, 1), sampleRate * 0.49);
  return f(Math.exp((-2 * Math.PI * clamped) / sampleRate));
}

/** Port of OnePoleFilter: a first-order low- or high-pass, a cheap and gentle 6 dB per octave slope. */
export class OnePoleFilter {
  readonly kind: OnePoleKind;
  readonly a: number;
  private low = 0;

  constructor(kind: OnePoleKind, cutoff: number, sampleRate: number) {
    this.kind = kind;
    this.a = onePoleCoefficient(cutoff, sampleRate);
  }

  process(x: number): number {
    this.low = f(f(f(1 - this.a) * x) + f(this.a * this.low));
    return this.kind === "lowPass" ? this.low : f(x - this.low);
  }
}

/** Port of BiquadFilter.Kind. */
export type BiquadKind = "lowPass" | "highPass" | "bandPass";

/** Normalized biquad coefficients (a0 divided out), in single precision like the Mac's. */
export interface BiquadCoefficients {
  readonly b0: number;
  readonly b1: number;
  readonly b2: number;
  readonly a1: number;
  readonly a2: number;
}

/**
 * The RBJ "Audio EQ Cookbook" coefficients the Mac's BiquadFilter computes:
 * in double precision, then rounded to single. `q` is the resonance (0.707 is
 * Butterworth); a band-pass peaks at 0 dB with a bandwidth of `frequency / q`.
 */
export function biquadCoefficients(kind: BiquadKind, frequency: number, q: number, sampleRate: number): BiquadCoefficients {
  const clamped = Math.min(Math.max(frequency, 1), sampleRate * 0.49);
  const w0 = (2 * Math.PI * clamped) / sampleRate;
  const cosW = Math.cos(w0);
  const alpha = Math.sin(w0) / (2 * Math.max(q, 0.01));
  let nb0: number;
  let nb1: number;
  let nb2: number;
  switch (kind) {
    case "lowPass":
      nb0 = (1 - cosW) / 2;
      nb1 = 1 - cosW;
      nb2 = (1 - cosW) / 2;
      break;
    case "highPass":
      nb0 = (1 + cosW) / 2;
      nb1 = -(1 + cosW);
      nb2 = (1 + cosW) / 2;
      break;
    case "bandPass":
      nb0 = alpha;
      nb1 = 0;
      nb2 = -alpha;
      break;
  }
  const a0 = 1 + alpha;
  return { b0: f(nb0 / a0), b1: f(nb1 / a0), b2: f(nb2 / a0), a1: f((-2 * cosW) / a0), a2: f((1 - alpha) / a0) };
}

/** Port of BiquadFilter: a second-order RBJ filter in direct form I. */
export class BiquadFilter {
  readonly coefficients: BiquadCoefficients;
  private x1 = 0;
  private x2 = 0;
  private y1 = 0;
  private y2 = 0;

  constructor(kind: BiquadKind, frequency: number, sampleRate: number, q = 0.7071) {
    this.coefficients = biquadCoefficients(kind, frequency, q, sampleRate);
  }

  process(x: number): number {
    const { b0, b1, b2, a1, a2 } = this.coefficients;
    const y = f(f(f(f(f(b0 * x) + f(b1 * this.x1)) + f(b2 * this.x2)) - f(a1 * this.y1)) - f(a2 * this.y2));
    this.x2 = this.x1;
    this.x1 = x;
    this.y2 = this.y1;
    this.y1 = y;
    return y;
  }
}
