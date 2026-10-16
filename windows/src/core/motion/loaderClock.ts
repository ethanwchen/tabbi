/*
 * Port of LoaderClock: the clock behind Tabbi's loaders, as pure functions of
 * time. Loaders draw from the frame time rather than a repeating animation,
 * so they stop ticking the moment they leave the screen and render the same
 * frame for the same moment (which snapshots need).
 */

/* Swift's truncatingRemainder folded into 0..<1. */
function fraction(value: number): number {
  const turns = value % 1;
  return turns < 0 ? turns + 1 : turns;
}

const SPIN_PERIOD = 1;
const BREATH_PERIOD = 1.6;
const BREATH_FLOOR = 0.35;
const SHIMMER_PERIOD = 1.4;
const SHIMMER_BAND = 0.5;

export const LoaderClock = {
  /** One full turn of a spinner, in seconds. */
  spinPeriod: SPIN_PERIOD,
  /** One breath of the Reduce Motion fallback (dim, bright, dim), in seconds. */
  breathPeriod: BREATH_PERIOD,
  /** The dimmest a breathing loader gets, so it never disappears. */
  breathFloor: BREATH_FLOOR,
  /** Loaders redraw at most this often; a small arc looks smooth at 30 fps. */
  frameRate: 30,
  /** One sweep of a skeleton's highlight across its placeholder, in seconds. */
  shimmerPeriod: SHIMMER_PERIOD,
  /** The highlight's width, as a fraction of the skeleton's width. */
  shimmerBand: SHIMMER_BAND,

  /** The spinner's rotation in degrees at `time`, in 0..<360. */
  spinAngle(time: number, period = SPIN_PERIOD): number {
    if (!(period > 0)) return 0;
    return fraction(time / period) * 360;
  },

  /** A smooth cosine between `breathFloor` and 1, fully bright at whole periods. */
  breathingOpacity(time: number, period = BREATH_PERIOD): number {
    if (!(period > 0)) return 1;
    const wave = (1 + Math.cos((2 * Math.PI * time) / period)) / 2;
    return BREATH_FLOOR + (1 - BREATH_FLOOR) * wave;
  },

  /**
   * Where a skeleton's highlight starts at `time`, as a fraction of its width:
   * it eases from just past the leading edge (-band) to just past the trailing
   * edge (1), so each sweep begins and ends off the placeholder.
   */
  shimmerOffset(time: number, period = SHIMMER_PERIOD, band = SHIMMER_BAND): number {
    if (!(period > 0)) return -band;
    const progress = fraction(time / period);
    const eased = progress * progress * (3 - 2 * progress);
    return -band + (1 + band) * eased;
  },
} as const;
