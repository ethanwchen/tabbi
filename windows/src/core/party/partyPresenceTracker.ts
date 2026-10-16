import { plannerDayKeyOf as dayKeyOf } from "../planner/plannerDayKey";
import { instantOf } from "../calendar/zonedCalendar";
import { VersionedJSON } from "../persistence/versionedJson";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { Instant, Seconds } from "../time";
import { OFFLINE_HEARTBEAT, statusToWire, statusFromWire, type PartyHeartbeat, type PartyStatus } from "./partyModels";

/*
 * Port of PartyPresenceTracker: turns the shared focus clock into
 * heartbeats, so friends see when the user studies without Party knowing
 * which module runs the clock.
 *
 * - Status: a running focus phase is `studying`, a running break or a paused
 *   clock is `break`, no session is `idle`, and going invisible is `offline`.
 * - When to send at once: `observe` returns true when status, method or
 *   phase end changed since it last said so (and on the first call, for the
 *   heartbeat at launch). Counters alone never trigger a heartbeat.
 * - Minutes: wall-clock time in running focus phases, clipped to each
 *   phase's end, split at local midnight; `todayMinutes` restarts each day.
 * - Streak: consecutive local days with focus time; it stays visible on the
 *   day after the last study day and drops to 0 once a day is missed.
 *
 * Only timer state and minute counts are kept: nothing about what is
 * studied. Days are local days in the IANA zone passed in.
 */

/* A focus phase with no end (one that counts up) credits until the next observation. */
const OPEN_ENDED = Number.POSITIVE_INFINITY;

function minutes(seconds: Seconds): number {
  return Math.min(1440, Math.trunc(seconds / 60));
}

/** `YYYY-MM-DD` of `instant` in `timeZone`, as the server expects. */
export function presenceDayString(instant: Instant, timeZone: string): string {
  return dayKeyOf(instant, timeZone);
}

function dayParts(day: string): [number, number, number] | undefined {
  const parts = day.split("-").map(Number);
  if (parts.length !== 3 || parts.some((part) => !Number.isInteger(part))) return undefined;
  return [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0];
}

/** Whether `earlier` is the calendar day right before `later`. */
function isDayBefore(earlier: string, later: string): boolean {
  const parts = dayParts(later);
  if (parts === undefined) return false;
  const previous = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] - 1));
  const text = `${String(previous.getUTCFullYear()).padStart(4, "0")}-${String(previous.getUTCMonth() + 1).padStart(2, "0")}-${String(previous.getUTCDate()).padStart(2, "0")}`;
  return text === earlier;
}

/** The first local midnight after `instant` in `timeZone`. */
function nextMidnight(instant: Instant, timeZone: string): Instant {
  const parts = dayParts(dayKeyOf(instant, timeZone));
  if (parts === undefined) return instant + 86400;
  const tomorrow = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + 1));
  return instantOf({ year: tomorrow.getUTCFullYear(), month: tomorrow.getUTCMonth() + 1, day: tomorrow.getUTCDate(), hour: 0 }, timeZone);
}

export class PartyPresenceTracker {
  /** The stored format of `toJSON`. */
  static readonly schema = new VersionedJSON(1);

  /** The `catalog.studyMethods` id reported while studying or on a break. */
  method: string;
  private invisible = false;
  private statusValue: PartyStatus = "idle";
  private phaseEnd: Instant | undefined;
  /* The signature last reported as changed, so edits made between observations are caught. */
  private announced: readonly (string | null)[] = [];
  private lastObserved: Instant | undefined;
  /* End of the focus phase running at `lastObserved`, if any. */
  private focusEndsAt: Instant | undefined;
  private sessionSeconds: Seconds = 0;
  private todaySeconds: Seconds = 0;
  /* The local day `todaySeconds` belongs to. */
  private day: string | undefined;
  /* The last local day with focus time, and the streak ending on it. */
  private lastStudyDay: string | undefined;
  private streak = 0;

  constructor(method = "pomodoro") {
    this.method = method;
  }

  get isInvisible(): boolean {
    return this.invisible;
  }

  /** What friends currently see, from the last observation. */
  get status(): PartyStatus {
    return this.statusValue;
  }

  get phaseEndsAt(): Instant | undefined {
    return this.phaseEnd;
  }

  /**
   * Records the clock at `now` and credits focus time since the last
   * observation. Returns true when friends should hear about it now.
   */
  observe(timer: ProvidedFocus | undefined, now: Instant, timeZone: string): boolean {
    this.credit(now, timeZone);
    const clock = timer?.clock;
    const focusing = timer?.phase === "focus";
    if (clock === undefined || clock.kind === "idle") {
      this.statusValue = "idle";
      this.phaseEnd = undefined;
      this.focusEndsAt = undefined;
      this.sessionSeconds = 0;
    } else if (clock.kind === "countdown" && clock.endsAt <= now) {
      /* The phase ran out between ticks: a finished focus phase leads to a break, a finished break to no session. */
      this.statusValue = focusing ? "onBreak" : "idle";
      this.phaseEnd = undefined;
      this.focusEndsAt = undefined;
      if (this.statusValue === "idle") this.sessionSeconds = 0;
    } else if (clock.kind === "countdown") {
      this.statusValue = focusing ? "studying" : "onBreak";
      this.phaseEnd = Math.round(clock.endsAt);
      this.focusEndsAt = focusing ? clock.endsAt : undefined;
    } else if (clock.kind === "countUp") {
      /* Open-ended: no end to report, and focus time runs until the next observation says otherwise. */
      this.statusValue = focusing ? "studying" : "onBreak";
      this.phaseEnd = undefined;
      this.focusEndsAt = focusing ? OPEN_ENDED : undefined;
    } else {
      this.statusValue = "onBreak";
      this.phaseEnd = undefined;
      this.focusEndsAt = undefined;
    }
    this.lastObserved = now;
    return this.takeChange();
  }

  /** Going invisible reports `offline` (send it once, then stop); coming back reports the current status. */
  setInvisible(invisible: boolean): boolean {
    this.invisible = invisible;
    return this.takeChange();
  }

  /** The body of a heartbeat at `now`, crediting focus time up to then. Call `observe` first. */
  heartbeat(now: Instant, timeZone: string): PartyHeartbeat {
    this.credit(now, timeZone);
    if (this.invisible) return OFFLINE_HEARTBEAT;
    const today = presenceDayString(now, timeZone);
    const active = this.statusValue === "studying" || this.statusValue === "onBreak";
    return {
      status: this.statusValue,
      ...(active ? { method: this.method } : {}),
      ...(active && this.phaseEnd !== undefined ? { phaseEndsAt: this.phaseEnd } : {}),
      sessionMinutes: active ? minutes(this.sessionSeconds) : 0,
      todayMinutes: this.day === today ? minutes(this.todaySeconds) : 0,
      streakDays: this.streakOn(today),
      day: today,
    };
  }

  /** Whole minutes studied today, for showing the user their own numbers. */
  todayMinutes(now: Instant, timeZone: string): number {
    return this.day === presenceDayString(now, timeZone) ? minutes(this.todaySeconds) : 0;
  }

  /** The streak as of `now`, kept through the day after the last study day. */
  streakDays(now: Instant, timeZone: string): number {
    return this.streakOn(presenceDayString(now, timeZone));
  }

  private get signature(): (string | null)[] {
    if (this.invisible) return ["offline"];
    return [statusToWire(this.statusValue), this.method, this.phaseEnd === undefined ? null : String(Math.trunc(this.phaseEnd))];
  }

  private takeChange(): boolean {
    const current = this.signature;
    const changed = current.length !== this.announced.length || current.some((value, index) => value !== this.announced[index]);
    this.announced = current;
    return changed;
  }

  /** Adds the focus time between the last observation and `now`. */
  private credit(now: Instant, timeZone: string): void {
    const start = this.lastObserved;
    const focusEnd = this.focusEndsAt;
    if (start === undefined || focusEnd === undefined) return;
    const end = Math.min(now, focusEnd);
    if (end > start) {
      this.sessionSeconds += end - start;
      /* Split at local midnights so each day gets its own minutes. */
      let from = start;
      while (from < end) {
        const to = Math.min(end, nextMidnight(from, timeZone));
        this.add(to - from, presenceDayString(from, timeZone));
        from = to;
      }
    }
    if (now >= focusEnd) this.focusEndsAt = undefined;
    this.lastObserved = now;
  }

  private add(seconds: Seconds, day: string): void {
    if (seconds <= 0) return;
    if (this.day !== day) {
      this.day = day;
      this.todaySeconds = 0;
    }
    this.todaySeconds += seconds;
    if (this.lastStudyDay !== day) {
      this.streak = this.lastStudyDay !== undefined && isDayBefore(this.lastStudyDay, day) ? this.streak + 1 : 1;
      this.lastStudyDay = day;
    }
  }

  private streakOn(today: string): number {
    const last = this.lastStudyDay;
    if (last === undefined) return 0;
    return last === today || isDayBefore(last, today) ? this.streak : 0;
  }

  /* MARK: Persistence */

  /** The tracker as a versioned JSON document, so today's minutes and the streak survive a restart. */
  toJSON(): Record<string, unknown> {
    return {
      method: this.method,
      isInvisible: this.invisible,
      status: statusToWire(this.statusValue),
      phaseEndsAt: this.phaseEnd ?? null,
      announced: [...this.announced],
      lastObserved: this.lastObserved ?? null,
      focusEndsAt: this.focusEndsAt === undefined ? null : this.focusEndsAt === OPEN_ENDED ? "open" : this.focusEndsAt,
      sessionSeconds: this.sessionSeconds,
      todaySeconds: this.todaySeconds,
      day: this.day ?? null,
      lastStudyDay: this.lastStudyDay ?? null,
      streak: this.streak,
    };
  }

  encoded(): string {
    return PartyPresenceTracker.schema.encode(this.toJSON());
  }

  /** Reads a stored tracker leniently: anything unreadable starts that field fresh. */
  static decode(text: string): PartyPresenceTracker {
    return PartyPresenceTracker.schema.decode(text, (object) => {
      const tracker = new PartyPresenceTracker(typeof object.method === "string" ? object.method : "pomodoro");
      const num = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : undefined);
      const str = (value: unknown) => (typeof value === "string" ? value : undefined);
      tracker.invisible = object.isInvisible === true;
      tracker.statusValue = statusFromWire(str(object.status) ?? "idle") ?? "idle";
      tracker.phaseEnd = num(object.phaseEndsAt);
      tracker.announced = Array.isArray(object.announced)
        ? object.announced.map((value) => (typeof value === "string" ? value : null))
        : [];
      tracker.lastObserved = num(object.lastObserved);
      tracker.focusEndsAt = object.focusEndsAt === "open" ? OPEN_ENDED : num(object.focusEndsAt);
      tracker.sessionSeconds = num(object.sessionSeconds) ?? 0;
      tracker.todaySeconds = num(object.todaySeconds) ?? 0;
      tracker.day = str(object.day);
      tracker.lastStudyDay = str(object.lastStudyDay);
      tracker.streak = Math.max(0, Math.trunc(num(object.streak) ?? 0));
      return tracker;
    });
  }
}
