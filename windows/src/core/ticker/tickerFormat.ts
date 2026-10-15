import { focusClock } from "../focus/focusTimerFormat";
import { tr } from "../localization/tr";
import type { ProgressItem } from "../providers/progressItem";
import { eventBadge, type EventTiming } from "../providers/providedEvent";
import type { Instant, Seconds } from "../time";
import { tickerPetIsSipping, tickerPetUnlockHint, type TickerFocus, type TickerMeeting, type TickerPet } from "./tickerItem";

/*
 * Port of TickerFormat: short strings for the closed-island preview, which
 * has room for a few words.
 */

/** Meeting countdown: "in 4 min" or "now". The title is drawn separately so it can scroll while the countdown stays whole. */
export function tickerMeetingCountdown(timing: EventTiming): string {
  return eventBadge(timing);
}

/** The whole meeting line, e.g. "Standup in 4 min" or "Design review now", for tooltips and accessibility. */
export function tickerMeetingSummary(meeting: TickerMeeting): string {
  return `${meeting.title} ${tickerMeetingCountdown(meeting.timing)}`;
}

/** "3 tasks left", "1 task left". */
export function tickerTasksLeft(count: number): string {
  return tr("%lld tasks left", count);
}

/** "84 cards left" or "1h 15m left": what remains of a shared goal, in its own unit. */
export function tickerProgressLeft(item: ProgressItem, locale: string): string {
  return item.remainingText(locale);
}

/** Focus countdown, e.g. "18:42", matching the focus card's clock. */
export function tickerFocusClock(remaining: Seconds): string {
  return focusClock(remaining);
}

/**
 * The focus line for tooltips and accessibility, e.g. "Focus 18:42",
 * "Review 3:10 (paused)" or "Focus 12:05 so far" for a clock counting up.
 */
export function tickerFocusSummary(focus: TickerFocus): string {
  const clock = tickerFocusClock(focus.time);
  const line = focus.countsUp ? tr("%@ %@ so far", focus.label, clock) : `${focus.label} ${clock}`;
  return focus.isRunning ? line : tr("%@ (paused)", line);
}

/** Party size, e.g. "4 in party". */
export function tickerPartySize(count: number): string {
  return tr("%lld in party", count);
}

/** The pet's line for tooltips and accessibility, e.g. "Mochi is napping until your next session". */
export function tickerPetSummary(pet: TickerPet, now: Instant): string {
  const name = pet.profile.name;
  /* The Mac says "Your Mac is charging"; Windows has its own string for the PC. */
  if (tickerPetIsSipping(pet)) return tr("Your PC is charging, and %@ is having a sip", name);
  if (pet.adventure?.isExploring(now) === true) {
    return tr("%@ is off on a little adventure and will be back as your session ends", name);
  }
  const unlock = tickerPetUnlockHint(pet);
  if (unlock !== undefined) return tr("%@ is keeping you company. %@", name, unlock.line);
  switch (pet.mood) {
    case "studying":
      return tr("%@ is studying with you", name);
    case "onBreak":
      return tr("%@ is on a break with you", name);
    case "awake":
      return tr("%@ is keeping you company", name);
    case "asleep":
      return tr("%@ is napping until your next session", name);
  }
}

/**
 * The name beside the pet in the closed island: only one the user chose. A
 * pet still going by a name the app gave it (its breed, "Biscuit") shows no
 * name, so "British Shorthair" doesn't stretch the island to its widest; the
 * tooltip still names it.
 */
export function tickerPetLabel(pet: TickerPet): string | undefined {
  return pet.profile.hasDefaultName ? undefined : pet.profile.name;
}

/** Shown beside the pet while it sips because the PC started charging. */
export function tickerCharging(): string {
  return tr("Charging");
}

/** Shown after the name while the pet sleeps. */
export const TICKER_PET_SLEEPING = "zzz";

/** Beside the pet's name while it is off on an adventure mid-session. */
export function tickerPetExploring(): string {
  return tr("exploring");
}
