import { hourOf, nextDateMatching, type DayCalendar } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import type { ProvidedFocus } from "../providers/providedFocus";

/*
 * Port of PetNightRhythm: late at night, when no session runs, the pet
 * beside the closed island dozes with a tiny "z". Opening the island or
 * starting a session wakes it. Hours are local wall-clock hours in the
 * calendar's zone, so the night follows the user across a zone change.
 */
export class PetNightRhythm {
  static readonly standard = new PetNightRhythm(23, 6, 10 * 60);

  /** The local hour the night starts (23 is 11 PM). */
  readonly startHour: number;
  /** The local hour the night ends (6 is 6 AM), exclusive. */
  readonly endHour: number;
  /** How long the pet stays up after something woke it. */
  readonly wakeSpell: number;

  constructor(startHour: number, endHour: number, wakeSpell: number) {
    this.startHour = Math.min(Math.max(startHour, 0), 23);
    this.endHour = Math.min(Math.max(endHour, 0), 23);
    this.wakeSpell = Math.max(0, wakeSpell);
  }

  /** Whether `date` falls in the night window; a window past midnight covers both ends. */
  isNight(date: Instant, calendar: DayCalendar): boolean {
    const hour = hourOf(date, calendar.timeZone);
    if (this.startHour === this.endHour) return false;
    if (this.startHour < this.endHour) return hour >= this.startHour && hour < this.endHour;
    return hour >= this.startHour || hour < this.endHour;
  }

  /** Whether the pet dozes at `now`: night, no session, and nothing woke it within the wake spell. */
  dozes(now: Instant, focus: ProvidedFocus | undefined, lastWoken: Instant | undefined, calendar: DayCalendar): boolean {
    if (!this.isNight(now, calendar) || focus?.isActive === true) return false;
    if (lastWoken === undefined) return true;
    return now - lastWoken >= this.wakeSpell || now < lastWoken;
  }

  /** The next moment after `date` the night starts or ends; undefined for a window that never opens. */
  nextBoundary(date: Instant, calendar: DayCalendar): Instant | undefined {
    if (this.startHour === this.endHour) return undefined;
    return Math.min(
      nextDateMatching(date, this.startHour, 0, calendar),
      nextDateMatching(date, this.endHour, 0, calendar),
    );
  }
}
