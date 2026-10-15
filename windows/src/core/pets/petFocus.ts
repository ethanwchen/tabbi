import type { Instant } from "../time";

/*
 * The shared focus clock as the pet reads it: a narrow local copy of the
 * Mac's ProvidedFocus (the providers port owns the full type), with the
 * same fields and the same clock rules, so the shared one fits here as is.
 */

/** Port of FocusPhase. */
export type FocusPhase = "focus" | "rest";

/** How the shown time moves. Port of ProvidedFocus.Clock. */
export type FocusClock =
  | { readonly kind: "idle" }
  | { readonly kind: "countdown"; readonly endsAt: Instant }
  | { readonly kind: "countUp"; readonly since: Instant }
  | { readonly kind: "paused"; readonly shown: number };

export interface PetFocus {
  /** The module whose clock this is. */
  readonly source: string;
  readonly phase: FocusPhase;
  readonly clock: FocusClock;
  /** The phase's planned length in seconds; undefined for an open-ended phase. */
  readonly phaseLength?: number;
  /** A full focus phase's length in seconds, for the pet's points. */
  readonly focusLength?: number;
  /** Focus phases this clock finished, lifetime or per session. */
  readonly completedFocusCount: number;
  /** Whether the clock logs its early ends to the activity log itself. */
  readonly logsEarlyEnds?: boolean;
}

export function focusIsRunning(focus: PetFocus): boolean {
  return focus.clock.kind === "countdown" || focus.clock.kind === "countUp";
}

/** Running or paused: a session is under way. */
export function focusIsActive(focus: PetFocus): boolean {
  return focus.clock.kind !== "idle";
}

/** The planned focus length: the phase length during a focus phase, unless given. */
export function focusLength(focus: PetFocus): number | undefined {
  return focus.focusLength ?? (focus.phase === "focus" ? focus.phaseLength : undefined);
}

export function focusRemaining(focus: PetFocus, now: Instant): number | undefined {
  const length = focus.phaseLength;
  if (length === undefined) return undefined;
  switch (focus.clock.kind) {
    case "idle":
      return length;
    case "countdown":
      return Math.max(focus.clock.endsAt - now, 0);
    case "countUp":
      return Math.max(length - (now - focus.clock.since), 0);
    case "paused":
      return focus.clock.shown;
  }
}

/** Seconds of the phase already behind. */
export function focusElapsed(focus: PetFocus, now: Instant): number {
  const clock = focus.clock;
  switch (clock.kind) {
    case "idle":
      return 0;
    case "countUp":
      return Math.max(now - clock.since, 0);
    case "paused":
      return focus.phaseLength === undefined ? clock.shown : Math.max(focus.phaseLength - clock.shown, 0);
    case "countdown": {
      const remaining = focusRemaining(focus, now);
      if (focus.phaseLength === undefined || remaining === undefined) return 0;
      return Math.max(focus.phaseLength - remaining, 0);
    }
  }
}
