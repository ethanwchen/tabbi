/*
 * What Today's focus card does to the shared Pomodoro, the slice of the
 * Mac's FocusStore the card needs: start or pause, skip, stop, and the link
 * between the timer and a checklist item. Every change goes through the
 * shared FocusTimerService, so the Focus tab, the ticker and the pet see
 * it; the Focus module owns the rest (sounds, notifications, the activity
 * log) and hears the same changes.
 */

import type { ModuleContext } from "../../app/context";
import type { FocusTimer } from "../../core/focus/focusTimer";
import { focusTimer, type FocusTimerService } from "../focus/focusServices";

export class FocusCardActions {
  readonly service: FocusTimerService;

  constructor(private readonly context: ModuleContext) {
    this.service = focusTimer(context);
  }

  get timer(): FocusTimer {
    return this.service.state.timer;
  }

  /** Starts a session (or the break), or pauses the running one. */
  toggleRunning(): void {
    const now = this.context.now();
    this.service.change((timer) => {
      if (timer.isRunning) timer.pause(now);
      else timer.start(now);
    });
  }

  /** Skips the rest of the current phase. */
  skip(): void {
    const now = this.context.now();
    this.service.change((timer) => {
      timer.skip(now);
    });
  }

  /** Stops the session, keeping the time focused so far. */
  stop(): void {
    const now = this.context.now();
    this.service.change((timer) => {
      timer.stop(now);
    });
  }

  /** Points the timer at a checklist item, or at nothing. */
  link(itemID: string | undefined): void {
    if (this.timer.linkedItemID === itemID) return;
    this.service.change((timer) => {
      timer.linkedItemID = itemID;
    });
  }

  /** Moves a phase that has run out on to the next one, so the card never sits at 0:00. */
  advance(): void {
    const now = this.context.now();
    const timer = this.timer;
    if (!timer.isRunning || (timer.endsAt ?? Number.POSITIVE_INFINITY) > now) return;
    this.service.change((candidate) => {
      candidate.advance(now);
    });
  }
}
