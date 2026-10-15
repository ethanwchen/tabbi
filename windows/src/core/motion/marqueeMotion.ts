/*
 * Port of MarqueeMotion: the clock behind the shared line of text that
 * scrolls to show what does not fit. A line that fits never moves. One that
 * overflows rests at its start, eases across until its end is in view, rests
 * again, then fades out and back in at the start, which reads calmer than
 * rewinding past every word.
 */

/** Where the line is drawn at one moment. */
export interface MarqueePose {
  /** How far the text has moved toward its end (0 at the start, `overflow` at the end). */
  readonly offset: number;
  /** Below 1 only while it fades back to the start. */
  readonly opacity: number;
}

const REST: MarqueePose = { offset: 0, opacity: 1 };

export const MarqueeMotion = {
  /** Rest at the start of each cycle, long enough to read the opening words. */
  startPause: 2,
  /** Rest once the end is in view, long enough to read the ending. */
  endPause: 1.6,
  /** The fade out at the end and the fade back in at the start, each. */
  fade: 0.3,
  /** Scroll speed in pixels per second: slow enough to read along. */
  speed: 30,
  /** The shortest scroll, so a line a few pixels too long glides instead of twitching. */
  minimumTravel: 0.8,
  /** The line redraws at most this often while it scrolls. */
  frameRate: 60,
  /** Width of the soft fade at an edge where text is cut off. */
  edgeFade: 12,
  /** Measured widths are rounded, so a line this close to its room counts as fitting. */
  slack: 0.5,

  rest: REST,

  /** How far the text overflows its room: zero when it fits. */
  overflow(contentWidth: number, containerWidth: number): number {
    if (
      !Number.isFinite(contentWidth) ||
      !Number.isFinite(containerWidth) ||
      !(containerWidth > 0) ||
      !(contentWidth > containerWidth + MarqueeMotion.slack)
    ) {
      return 0;
    }
    return contentWidth - containerWidth;
  },

  /** Only when it overflows, motion is allowed and someone can see it. */
  scrolls(overflow: number, reduceMotion: boolean, isVisible = true): boolean {
    return overflow > 0 && !reduceMotion && isVisible;
  },

  /** How long the scroll from start to end takes for `overflow` pixels. */
  travel(overflow: number): number {
    return Math.max(overflow / MarqueeMotion.speed, MarqueeMotion.minimumTravel);
  },

  /** One whole cycle: rest, scroll, rest, fade out, fade in. */
  cycle(overflow: number): number {
    return MarqueeMotion.startPause + MarqueeMotion.travel(overflow) + MarqueeMotion.endPause + 2 * MarqueeMotion.fade;
  },

  /** The pose `elapsed` seconds after the line started scrolling, eased with smoothstep. */
  pose(elapsed: number, overflow: number): MarqueePose {
    if (!(overflow > 0) || !Number.isFinite(elapsed) || !(elapsed > 0)) return REST;
    const travel = MarqueeMotion.travel(overflow);
    let t = elapsed % MarqueeMotion.cycle(overflow);
    if (t < MarqueeMotion.startPause) return REST;
    t -= MarqueeMotion.startPause;
    if (t < travel) {
      const progress = t / travel;
      return { offset: overflow * progress * progress * (3 - 2 * progress), opacity: 1 };
    }
    t -= travel;
    if (t < MarqueeMotion.endPause) return { offset: overflow, opacity: 1 };
    t -= MarqueeMotion.endPause;
    if (t < MarqueeMotion.fade) return { offset: overflow, opacity: 1 - t / MarqueeMotion.fade };
    t -= MarqueeMotion.fade;
    return { offset: 0, opacity: Math.min(t / MarqueeMotion.fade, 1) };
  },

  /** The pose a fraction of the way through the scroll, for still renders such as snapshots. */
  poseScrolled(fraction: number, overflow: number): MarqueePose {
    if (!(overflow > 0) || !Number.isFinite(fraction)) return REST;
    return { offset: overflow * Math.min(Math.max(fraction, 0), 1), opacity: 1 };
  },
} as const;
