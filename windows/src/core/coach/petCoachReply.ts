import { tr } from "../localization/tr";
import type { Seconds } from "../time";
import type { PetCoachNudgeKind } from "./petCoachMessages";

/*
 * Port of PetCoachReply: a button on the coach's speech bubble. Every
 * answer sends the pet home; what else happens is up to the app (pause or
 * resume the timer, snooze).
 */

export type PetCoachReply =
  /** "Back to it": the user is heading back. Nothing else changes. */
  | "backToIt"
  /** "Still here": answers an idle check; the timer keeps running. */
  | "stillHere"
  /** Pause the study timer. */
  | "pause"
  /** Resume a timer the coach paused. */
  | "resume"
  /** Silence the coach for `PET_COACH_SNOOZE_DURATION`. */
  | "snooze"
  /** "Yay!": closes a celebration bubble. Nothing else changes. */
  | "thanks";

export const PET_COACH_REPLIES: readonly PetCoachReply[] = ["backToIt", "stillHere", "pause", "resume", "snooze", "thanks"];

/** How long "Snooze" keeps the pet quiet. */
export const PET_COACH_SNOOZE_DURATION: Seconds = 15 * 60;

/* The Mac keeps these as plain English; tr() looks them up by that text, so a translation added to the catalog shows on both apps. */
const TITLES: Record<PetCoachReply, string> = {
  backToIt: "Back to it",
  stillHere: "Still here",
  pause: "Pause",
  resume: "Resume",
  snooze: "Snooze 15 min",
  thanks: "Yay!",
};

/*
 * The Mac's "Send your pet back to the notch" names the notch, so Windows
 * uses the catalog's platform-neutral (and translated) "Click to send the
 * pet home" for the two answers that only send the pet home.
 */
const HELP: Record<PetCoachReply, string> = {
  backToIt: "Click to send the pet home",
  thanks: "Click to send the pet home",
  stillHere: "Keep the timer running",
  pause: "Pause the study timer",
  resume: "Resume the study timer",
  snooze: "No nudges for the next 15 minutes",
};

/** The button's label, short enough for a small bubble. */
export function replyTitle(reply: PetCoachReply): string {
  return tr(TITLES[reply]);
}

/** The tooltip, saying exactly what the click does. */
export function replyHelp(reply: PetCoachReply): string {
  return tr(HELP[reply]);
}

/** Whether the app should pause the study timer on this answer. */
export function replyPausesTimer(reply: PetCoachReply): boolean {
  return reply === "pause";
}

/** Whether the app should resume the study timer on this answer. */
export function replyResumesTimer(reply: PetCoachReply): boolean {
  return reply === "resume";
}

/** The bubble's buttons, the kind's default first. Snooze is always last and always there, so the user can quiet the pet from any bubble. */
export function nudgeReplies(kind: PetCoachNudgeKind): PetCoachReply[] {
  switch (kind) {
    case "distraction":
      return ["backToIt", "snooze"];
    case "offerPause":
      return ["pause", "backToIt", "snooze"];
    case "idleCheck":
      return ["stillHere", "pause", "snooze"];
    case "autoPause":
      return ["resume", "snooze"];
  }
}
