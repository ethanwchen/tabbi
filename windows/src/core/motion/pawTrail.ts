/*
 * Port of PawTrail: the clock behind the paw print loader for longer waits,
 * as pure functions of time. Prints appear one after another, left, right,
 * left, right, as if the pet trotted past, then fade behind it.
 */

const STEP_COUNT = 4;
const STEP_INTERVAL = 0.32;
const PRESS_DURATION = 0.12;
const FADE_DURATION = 1.1;
const CYCLE = (STEP_COUNT + 3) * STEP_INTERVAL;
const REVEAL_DELAY = 0.3;
const REVEAL_DURATION = 0.2;

/* How long ago print `step` landed in the current walk; negative before it lands. */
function age(step: number, time: number): number {
  const phase = time % CYCLE;
  return (phase < 0 ? phase + CYCLE : phase) - step * STEP_INTERVAL;
}

function inRange(step: number): boolean {
  return Number.isInteger(step) && step >= 0 && step < STEP_COUNT;
}

export const PawTrail = {
  /** How many prints the trail has. */
  stepCount: STEP_COUNT,
  /** The time between one print and the next, in seconds: a calm trot. */
  stepInterval: STEP_INTERVAL,
  /** How long a print takes to press in. */
  pressDuration: PRESS_DURATION,
  /** How long a print takes to fade once it is pressed. */
  fadeDuration: FADE_DURATION,
  /** One full walk: every print plus a short pause, so each walk reads as a new one. */
  cycle: CYCLE,
  /** A loader that would show for less than this is never shown, so a fast answer doesn't flash one. */
  revealDelay: REVEAL_DELAY,
  /** How long the loader takes to fade in once the delay has passed. */
  revealDuration: REVEAL_DURATION,

  /** The opacity of print `step` at `time`, in 0...1: it presses in quickly, then fades. */
  opacity(step: number, time: number): number {
    if (!inRange(step)) return 0;
    const a = age(step, time);
    if (a < 0) return 0;
    const pressed = Math.min(1, a / PRESS_DURATION);
    const faded = Math.max(0, 1 - Math.max(0, a - PRESS_DURATION) / FADE_DURATION);
    return pressed * faded;
  },

  /** The scale of print `step` at `time`: it lands slightly large and settles, like a footfall. */
  scale(step: number, time: number): number {
    if (!inRange(step)) return 1;
    const a = age(step, time);
    if (a < 0 || a >= PRESS_DURATION) return 1;
    return 1 + 0.15 * (1 - a / PRESS_DURATION);
  },

  /** Even steps are left feet, odd ones right, so the trail zigzags. */
  isLeftFoot(step: number): boolean {
    return step % 2 === 0;
  },

  /** The whole loader's opacity `elapsed` seconds after it was asked to show. */
  revealOpacity(elapsed: number, delay: number = REVEAL_DELAY): number {
    if (elapsed < delay) return 0;
    return Math.min(1, (elapsed - delay) / REVEAL_DURATION);
  },
} as const;
