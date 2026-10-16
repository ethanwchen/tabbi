/*
 * Port of HangDetector: decides when the UI thread has hung, from a
 * watchdog that pings it once per tick and asks on the next tick whether
 * the ping was answered. It counts unanswered ticks rather than wall-clock
 * time, so a PC waking from sleep never reads as a hang. A hang begins
 * after `ticksToHang` unanswered ticks in a row and ends with the first
 * answer after that.
 */

export type HangEvent = "began" | "ended";

export class HangDetector {
  readonly ticksToHang: number;
  private unanswered = 0;
  private hanging = false;

  constructor(ticksToHang: number) {
    this.ticksToHang = Math.max(1, ticksToHang);
  }

  get unansweredTicks(): number {
    return this.unanswered;
  }

  get isHanging(): boolean {
    return this.hanging;
  }

  /** Call once per tick with whether the last ping was answered; returns the change this tick brings. */
  tick(answered: boolean): HangEvent | undefined {
    if (answered) {
      this.unanswered = 0;
      if (!this.hanging) return undefined;
      this.hanging = false;
      return "ended";
    }
    this.unanswered += 1;
    if (this.hanging || this.unanswered < this.ticksToHang) return undefined;
    this.hanging = true;
    return "began";
  }
}
