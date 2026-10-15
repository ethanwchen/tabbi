/*
 * Small, allocation-free DSP building blocks for the focus sounds, ported from
 * the Mac's FocusDSP.swift. The Mac runs them in single precision (`Float`),
 * so every step here rounds through Math.fround the same way: the same seed
 * renders the same samples on both apps, give or take the last bit of the
 * transcendental functions (exp, cos, tanh), which each platform's math
 * library rounds on its own.
 */

/** Seeds are 64-bit, like the Mac's UInt64. */
export type Seed = bigint;

const MASK64 = (1n << 64n) - 1n;

/** Swift's `a &+ b` on UInt64. */
export function seedAdd(a: Seed, b: Seed): Seed {
  return (a + b) & MASK64;
}

/** Swift's `a &* b` on UInt64. */
export function seedMultiply(a: Seed, b: Seed): Seed {
  return (a * b) & MASK64;
}

/** Swift's `a ^ b` on UInt64. */
export function seedXor(a: Seed, b: Seed): Seed {
  return (a ^ b) & MASK64;
}

/* The xorshift64* multiplier, 0x2545F4914F6CDD1D, in 32-bit halves. */
const MULTIPLIER_HI = 0x2545f491;
const MULTIPLIER_LO = 0x4f6cdd1d;
const TWO_POW_16 = 0x10000;
const TWO_POW_32 = 0x100000000;

/**
 * Port of NoiseRandom: a seedable xorshift64* generator, fast enough to call
 * per audio sample. The 64-bit state is kept as two unsigned 32-bit halves,
 * since BigInt arithmetic is far too slow for the audio thread.
 */
export class NoiseRandom {
  private hi: number;
  private lo: number;
  /** The last output's halves, so a test can read the full 64 bits without allocating on the audio path. */
  outputHi = 0;
  outputLo = 0;

  constructor(seed: Seed) {
    /* A zero state would stay zero forever. */
    const state = (seed & MASK64) === 0n ? 0x9e3779b97f4a7c15n : seed & MASK64;
    this.hi = Number(state >> 32n) >>> 0;
    this.lo = Number(state & 0xffffffffn) >>> 0;
  }

  /** Advances the state and leaves the output in `outputHi` and `outputLo`. */
  step(): void {
    let hi = this.hi;
    let lo = this.lo;
    /* state ^= state >> 12 */
    lo = (lo ^ ((lo >>> 12) | (hi << 20))) >>> 0;
    hi = (hi ^ (hi >>> 12)) >>> 0;
    /* state ^= state << 25 */
    hi = (hi ^ ((hi << 25) | (lo >>> 7))) >>> 0;
    lo = (lo ^ (lo << 25)) >>> 0;
    /* state ^= state >> 27 */
    lo = (lo ^ ((lo >>> 27) | (hi << 5))) >>> 0;
    hi = (hi ^ (hi >>> 27)) >>> 0;
    this.hi = hi;
    this.lo = lo;

    /* state &* multiplier, low 64 bits: lo * mlo in full, plus the cross terms shifted up 32. */
    const a0 = lo & 0xffff;
    const a1 = lo >>> 16;
    const b0 = MULTIPLIER_LO & 0xffff;
    const b1 = MULTIPLIER_LO >>> 16;
    const middle = a0 * b1 + a1 * b0;
    const low = a0 * b0 + (middle % TWO_POW_16) * TWO_POW_16;
    const carry = Math.floor(low / TWO_POW_32);
    const productHi = a1 * b1 + Math.floor(middle / TWO_POW_16) + carry;
    this.outputLo = low % TWO_POW_32 >>> 0;
    this.outputHi = (productHi + Math.imul(hi, MULTIPLIER_LO) + Math.imul(lo, MULTIPLIER_HI)) >>> 0;
  }

  /** The next raw 64-bit value, as a BigInt; for tests and seeding, never the audio path. */
  nextUInt64(): bigint {
    this.step();
    return (BigInt(this.outputHi) << 32n) | BigInt(this.outputLo);
  }

  /** Uniform in 0 ..< 1: the top 24 bits over 2^24, exact in single precision. */
  nextUnit(): number {
    this.step();
    return (this.outputHi >>> 8) / 16_777_216;
  }

  /** Uniform in -1 ..< 1 (variance 1/3). */
  nextBipolar(): number {
    return this.nextUnit() * 2 - 1;
  }
}
