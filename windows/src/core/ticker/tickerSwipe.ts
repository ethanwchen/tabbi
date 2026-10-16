import type { SwipePhase } from "../settings/tabSwipe";

/**
 * Port of TickerSwipe: turns vertical scroll events over the closed island
 * into "next live activity" steps. A two-finger swipe down cycles once,
 * however long it runs, like pulling the next card off a stack.
 *
 * Works like TabSwipe turned on its side: a gesture steps once, when its
 * downward travel passes `threshold`, and nothing else in that gesture (or
 * its momentum) steps again. A mouse wheel has no gestures, so each
 * `threshold` of its downward travel is a step. Upward and mostly
 * horizontal travel never cycles.
 */
export class TickerSwipe {
  /** Pixels of downward travel that make a step. */
  static readonly threshold = 40;

  private travel = 0;
  private hasStepped = false;

  /**
   * Feeds one scroll event and returns true when it completes a step.
   * `fingersDown` is the vertical travel with the user's scroll direction
   * taken out: positive when the fingers (or the wheel) move toward the user.
   */
  feed(deltaX: number, fingersDown: number, phase: SwipePhase): boolean {
    if (phase === "momentum") return false;
    if (phase === "began") {
      this.travel = 0;
      this.hasStepped = false;
    }
    try {
      if (this.hasStepped || !(Math.abs(fingersDown) > Math.abs(deltaX))) return false;
      this.travel = Math.max(this.travel + fingersDown, 0);
      if (!(this.travel > TickerSwipe.threshold)) return false;
      this.travel = 0;
      this.hasStepped = phase !== "none";
      return true;
    } finally {
      if (phase === "ended") {
        this.travel = 0;
        this.hasStepped = false;
      }
    }
  }
}
