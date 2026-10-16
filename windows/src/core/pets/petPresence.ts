import type { DayCalendar } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import type { PetMood } from "./petAnimator";
import type { UnlockProgress } from "../motivation/unlockProgress";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { PetNightRhythm } from "./petNightRhythm";
import type { PetProfile } from "./petProfile";

/*
 * Port of PetPresence (Coach/PetPresence.swift on the Mac): the study pet as
 * the closed island shows it, its look plus the last time a session ran, so
 * the island can tell when the pet should doze off.
 */

export class PetPresence {
  /** Quiet time after a session (or launch) before the pet falls asleep. */
  static readonly sleepAfter = 20 * 60;

  profile: PetProfile;
  /** Progress toward the next shop item from the pet's real points, so the closed island can hint at a near unlock; undefined when everything is owned. */
  nextUnlock: UnlockProgress | undefined;
  /** The pet's night, or undefined for a pet that only sleeps after `sleepAfter`. */
  night: PetNightRhythm | undefined;
  /** The calendar whose time zone places the night. */
  calendar: DayCalendar;
  private lastActiveValue: Instant;
  private lastWokenValue: Instant | undefined;
  /** Whether the last observed timer was mid-session, so the moment a session ends counts as activity too. */
  private sessionWasActive = false;

  constructor(
    profile: PetProfile,
    lastActive: Instant,
    calendar: DayCalendar,
    options: { nextUnlock?: UnlockProgress; night?: PetNightRhythm } = {},
  ) {
    this.profile = profile;
    this.lastActiveValue = lastActive;
    this.calendar = calendar;
    this.nextUnlock = options.nextUnlock;
    this.night = options.night;
  }

  /** When a session last ran, or when the pet came on screen. */
  get lastActive(): Instant {
    return this.lastActiveValue;
  }

  /** When the user last opened the island, which wakes a dozing pet at night. */
  get lastWoken(): Instant | undefined {
    return this.lastWokenValue;
  }

  /** Records the shared focus clock at `now`: running or paused sessions keep the pet awake, as does the moment one ends. */
  observe(focus: ProvidedFocus | undefined, now: Instant): void {
    const active = focus?.isActive === true;
    if (active || this.sessionWasActive) this.lastActiveValue = Math.max(this.lastActiveValue, now);
    this.sessionWasActive = active;
  }

  /** Records that the user opened or closed the island at `now`: at night the pet wakes for a wake spell. */
  wake(now: Instant): void {
    this.lastWokenValue = Math.max(this.lastWokenValue ?? now, now);
  }

  /** The pet's mood at `now` for the shared focus clock. */
  mood(focus: ProvidedFocus | undefined, now: Instant): PetMood {
    if (focus?.isRunning === true) return focus.phase === "focus" ? "studying" : "onBreak";
    if (focus?.isActive === true) return "awake";
    const night = this.night;
    if (night && night.isNight(now, this.calendar)) {
      return night.dozes(now, focus, this.lastStirred, this.calendar) ? "asleep" : "awake";
    }
    return now - this.lastActiveValue < PetPresence.sleepAfter ? "awake" : "asleep";
  }

  /** When the mood can next change if nothing else happens; undefined while a session runs. */
  sleepsAt(focus: ProvidedFocus | undefined, now: Instant): Instant | undefined {
    if (focus?.isActive === true) return undefined;
    const dates = [this.lastActiveValue + PetPresence.sleepAfter];
    const night = this.night;
    if (night) {
      dates.push(this.lastStirred + night.wakeSpell);
      const boundary = night.nextBoundary(now, this.calendar);
      if (boundary !== undefined) dates.push(boundary);
    }
    const future = dates.filter((date) => date > now);
    return future.length === 0 ? undefined : Math.min(...future);
  }

  /** The last session or island opening, whichever came later. */
  private get lastStirred(): Instant {
    return Math.max(this.lastActiveValue, this.lastWokenValue ?? this.lastActiveValue);
  }
}
