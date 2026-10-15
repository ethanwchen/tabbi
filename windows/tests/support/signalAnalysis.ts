/*
 * Port of the Mac's FocusSignalAnalysis: measurements the focus sound tests
 * share, at the 48 kHz every focus sound test renders at.
 */

export const SAMPLE_RATE = 48_000;

export function rms(x: Float32Array): number {
  let sum = 0;
  for (const v of x) sum += v * v;
  return Math.sqrt(sum / x.length);
}

export function mean(x: Float32Array): number {
  let sum = 0;
  for (const v of x) sum += v;
  return sum / x.length;
}

export function peak(x: Float32Array): number {
  let max = 0;
  for (const v of x) max = Math.max(max, Math.abs(v));
  return max;
}

export function decibels(ratio: number): number {
  return 10 * Math.log10(ratio);
}

/** Average spectral power near `frequency`, via Hann-windowed Goertzel over blocks and a few neighbouring bins. */
export function powerNear(x: Float32Array, frequency: number): number {
  const n = 2048;
  const window = Array.from({ length: n }, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (n - 1)));
  const centerBin = Math.round((frequency * n) / SAMPLE_RATE);
  let total = 0;
  let count = 0;
  for (let start = 0; start + n <= x.length; start += n) {
    for (let bin = centerBin - 2; bin <= centerBin + 2; bin++) {
      const coefficient = 2 * Math.cos((2 * Math.PI * bin) / n);
      let s1 = 0;
      let s2 = 0;
      for (let i = 0; i < n; i++) {
        const s0 = (x[start + i] ?? 0) * (window[i] ?? 0) + coefficient * s1 - s2;
        s2 = s1;
        s1 = s0;
      }
      total += s1 * s1 + s2 * s2 - coefficient * s1 * s2;
      count += 1;
    }
  }
  return total / count;
}

function biquad(x: Float64Array, b: readonly number[], a: readonly number[]): Float64Array {
  const [b0 = 0, b1 = 0, b2 = 0] = b;
  const [, a1 = 0, a2 = 0] = a;
  const out = new Float64Array(x.length);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const v = x[i] ?? 0;
    const y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = v;
    y2 = y1;
    y1 = y;
    out[i] = y;
  }
  return out;
}

/**
 * Integrated loudness in LUFS per ITU-R BS.1770-4: K-weighting, mean square
 * over 400 ms blocks with 75% overlap, then the -70 LUFS absolute gate and the
 * -10 LU relative gate, with the standard's coefficients for 48 kHz.
 */
export function loudness(x: Float32Array): number {
  const shelf = biquad(Float64Array.from(x), [1.53512485958697, -2.69169618940638, 1.19839281085285], [
    1, -1.69065929318241, 0.73248077421585,
  ]);
  const weighted = biquad(shelf, [1, -2, 1], [1, -1.99004745483398, 0.99007225036621]);
  const block = Math.trunc(SAMPLE_RATE * 0.4);
  const hop = Math.trunc(block / 4);
  const powers: number[] = [];
  for (let start = 0; start <= weighted.length - block; start += hop) {
    let sum = 0;
    for (let i = start; i < start + block; i++) sum += (weighted[i] ?? 0) ** 2;
    powers.push(sum / block);
  }
  const lufs = (power: number): number => -0.691 + 10 * Math.log10(power);
  const gatedMean = (values: number[]): number => values.reduce((a, b) => a + b, 0) / Math.max(values.length, 1);
  const audible = powers.filter((power) => lufs(power) > -70);
  const relativeGate = lufs(gatedMean(audible)) - 10;
  return lufs(gatedMean(audible.filter((power) => lufs(power) > relativeGate)));
}
