/*
 * Port of RingProgress: how a progress ring moves between two values. A ring
 * fills smoothly and unwinds when a little is taken back, but a big drop is a
 * new start (a Pomodoro phase change, a new day): the ring snaps back to
 * empty instead of sweeping backwards, which would read as progress undone.
 */

/** What a ring does when its value changes. */
export type RingChange = "none" | "advance" | "unwind" | "step" | "restart";

export const RingProgress = {
  /** A drop larger than this fraction of the ring is a restart, not an unwind. */
  restartDrop: 0.5,
  /**
   * A move smaller than this fraction is a step, not a glide: a 25 minute
   * countdown advances 1/1500 of the ring a second, and springing that every
   * second would keep redrawing for no visible motion.
   */
  stepLimit: 0.005,

  /** `value` as a ring fraction in 0...1; missing or non-finite values draw an empty ring. */
  clamped(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value)) return 0;
    return Math.min(Math.max(value, 0), 1);
  },

  /** How the ring should move from `old` to `next`. */
  change(old: number | undefined, next: number | undefined): RingChange {
    const from = RingProgress.clamped(old);
    const to = RingProgress.clamped(next);
    if (to === from) return "none";
    if (Math.abs(to - from) < RingProgress.stepLimit) return "step";
    if (to > from) return "advance";
    return from - to > RingProgress.restartDrop ? "restart" : "unwind";
  },
} as const;
