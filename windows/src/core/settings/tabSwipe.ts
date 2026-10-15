/** Where a scroll event sits in its gesture; `none` is a mouse wheel, which has no gestures. */
export type SwipePhase = "began" | "changed" | "ended" | "momentum" | "none";

/** Swiping right goes back to the tab on the left (`previous`); swiping left, on to the right (`next`). */
export type TabSwipeStep = "previous" | "next";

/**
 * Port of TabSwipe: turns horizontal scroll events into tab steps. A
 * gesture steps once, when its travel passes `threshold`, and nothing else
 * in that gesture (or its momentum) steps again. A wheel has no gestures;
 * each threshold of its travel is a step.
 */
export class TabSwipe {
  /** Points of horizontal travel that make a step. */
  static readonly threshold = 60;

  private travel = 0;
  private hasStepped = false;

  /** Feeds one scroll event and returns the step it completes, if any. Mostly vertical events are ignored. */
  feed(deltaX: number, deltaY: number, phase: SwipePhase): TabSwipeStep | undefined {
    if (phase === "momentum") return undefined;
    if (phase === "began") {
      this.travel = 0;
      this.hasStepped = false;
    }
    const step = this.advance(deltaX, deltaY, phase);
    if (phase === "ended") {
      this.travel = 0;
      this.hasStepped = false;
    }
    return step;
  }

  private advance(deltaX: number, deltaY: number, phase: SwipePhase): TabSwipeStep | undefined {
    if (this.hasStepped || !(Math.abs(deltaX) > Math.abs(deltaY))) return undefined;
    this.travel += deltaX;
    if (!(Math.abs(this.travel) > TabSwipe.threshold)) return undefined;
    const step: TabSwipeStep = this.travel > 0 ? "previous" : "next";
    this.travel = 0;
    this.hasStepped = phase !== "none";
    return step;
  }
}

/**
 * Port of CloseSwipe: a two-finger swipe up on the open panel closes it.
 * Only touchpad gestures count, momentum is ignored, and a gesture that
 * starts over a scrollable list belongs to the list.
 */
export class CloseSwipe {
  /** Points of upward travel that close the panel; longer than a tab swipe's. */
  static readonly threshold = 70;

  private travel = 0;
  private isActive = false;

  /**
   * Feeds one scroll event and returns true when it completes a close.
   * `fingersUp` is positive when the fingers move away from the user.
   */
  feed(deltaX: number, fingersUp: number, phase: SwipePhase, overScrollableList: boolean): boolean {
    switch (phase) {
      case "none":
      case "momentum":
        return false;
      case "began":
        this.travel = 0;
        this.isActive = !overScrollableList;
        break;
      case "changed":
        break;
      case "ended":
        this.isActive = false;
        return false;
    }
    if (!this.isActive || !(Math.abs(fingersUp) > Math.abs(deltaX))) return false;
    this.travel = Math.max(this.travel + fingersUp, 0);
    if (!(this.travel > CloseSwipe.threshold)) return false;
    this.isActive = false;
    return true;
  }
}
