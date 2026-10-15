/*
 * Port of SplitMix64 (PetAnimator.swift): a tiny seeded generator, so a seed
 * always gives the same particles on both platforms. 64-bit wrapping math
 * runs on BigInt.
 */

const MASK = (1n << 64n) - 1n;

export class SplitMix64 {
  private state: bigint;

  constructor(seed: bigint | number) {
    this.state = BigInt(seed) & MASK;
  }

  next(): bigint {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
    return z ^ (z >> 31n);
  }

  /** A double in `lower...upper` from the top 53 bits, exactly as the Swift does. */
  nextIn(lower: number, upper: number): number {
    const unit = Number(this.next() >> 11n) / 2 ** 53;
    return lower + unit * (upper - lower);
  }
}
