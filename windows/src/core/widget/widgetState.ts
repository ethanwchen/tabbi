import { ACTIVITY_KINDS, wholeSeconds, type ActivityRecord } from "../activity/activityRecord";
import { formatISODate, parseISODate } from "../activity/isoDate";
import type { FocusPhase } from "../focus/focusTimer";
import { focusPhaseName } from "../focus/focusTimerFormat";
import { isJSONObject, type JSONObject } from "../persistence/json";
import type { DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import { NO_BOND_LOOK } from "../pets/petBond";
import { PetProfile } from "../pets/petProfile";
import { addingDaysToKey, dayKeyStart, isPlannerDayKey, plannerDayKeyOf, type PlannerDayKey } from "../planner/plannerDayKey";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { Instant, Seconds } from "../time";

/*
 * Port of WidgetState: what a desktop widget shows, in the same versioned
 * shape the Mac's widget extension reads, kept for a future Windows widget
 * (a Windows 11 Widgets board card would read the same document).
 *
 * The app writes it only when something the widget shows changes (a session
 * starts, pauses or ends, the pet's look changes, today's minutes grow), so
 * the widget never polls. Values that go stale on their own (a countdown
 * that ran out, minutes and a streak after midnight) are worked out at the
 * entry's date with `minutesAt`, `streakAt` and `timerAt`, so the widget
 * stays right while the app is not running.
 */

/** The clock the widget shows while a timer runs. Port of WidgetState.Timer.Clock. */
export type WidgetClock =
  /** Counting down to a wall-clock end. */
  | { readonly kind: "countdown"; readonly endsAt: Instant }
  /** An open-ended phase counting up from a wall-clock start. */
  | { readonly kind: "countUp"; readonly since: Instant }
  /** Stopped part-way, showing a frozen clock. */
  | { readonly kind: "paused"; readonly shown: Seconds };

/** The clock the widget shows while a focus or break timer runs. Port of WidgetState.Timer. */
export interface WidgetTimer {
  readonly phase: FocusPhase;
  /** The engine's name for the phase, such as "Focus" or "Long break". */
  readonly label: string;
  readonly clock: WidgetClock;
}

/** A timer with its dates in whole seconds, so it reads back from its ISO 8601 file exactly as it was written. */
export function widgetTimer(phase: FocusPhase, label: string, clock: WidgetClock): WidgetTimer {
  switch (clock.kind) {
    case "countdown":
      return { phase, label, clock: { kind: "countdown", endsAt: wholeSeconds(clock.endsAt) } };
    case "countUp":
      return { phase, label, clock: { kind: "countUp", since: wholeSeconds(clock.since) } };
    case "paused":
      return { phase, label, clock };
  }
}

/** The widget's view of a running clock; undefined for an idle one, which the widget does not show. */
export function widgetTimerFrom(focus: ProvidedFocus): WidgetTimer | undefined {
  const clock = focus.clock;
  switch (clock.kind) {
    case "idle":
      return undefined;
    case "countdown":
      return widgetTimer(focus.phase, focus.label, { kind: "countdown", endsAt: clock.endsAt });
    case "countUp":
      return widgetTimer(focus.phase, focus.label, { kind: "countUp", since: clock.since });
    case "paused":
      return widgetTimer(focus.phase, focus.label, { kind: "paused", shown: clock.shown });
  }
}

function sameTimer(a: WidgetTimer | undefined, b: WidgetTimer | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  if (a.phase !== b.phase || a.label !== b.label || a.clock.kind !== b.clock.kind) return false;
  switch (a.clock.kind) {
    case "countdown":
      return b.clock.kind === "countdown" && a.clock.endsAt === b.clock.endsAt;
    case "countUp":
      return b.clock.kind === "countUp" && a.clock.since === b.clock.since;
    case "paused":
      return b.clock.kind === "paused" && a.clock.shown === b.clock.shown;
  }
}

export interface WidgetStateFields {
  readonly pet: PetProfile;
  readonly day: PlannerDayKey;
  readonly focusMinutes?: number;
  readonly streakDays?: number;
  readonly lastFocusDay?: PlannerDayKey;
  readonly timer?: WidgetTimer;
}

export class WidgetState {
  /** The format of the shared file; a change to it is a new step here. */
  static readonly schema = new VersionedJSON(1);
  /** The file's name in the folder the app and the widget share. */
  static readonly fileName = "WidgetState.json";

  /** The pet as dressed in the Closet. */
  readonly pet: PetProfile;
  /** The day `focusMinutes` counts. */
  readonly day: PlannerDayKey;
  /** Minutes focused on `day`. */
  readonly focusMinutes: number;
  /** Days in a row with focus, ending on `lastFocusDay`. */
  readonly streakDays: number;
  /** The latest day with focus, or undefined before the first session. */
  readonly lastFocusDay: PlannerDayKey | undefined;
  /** The running clock, or undefined when no timer runs. */
  readonly timer: WidgetTimer | undefined;

  constructor(fields: WidgetStateFields) {
    /*
     * The bond look is never saved with the pet, so the state leaves it out
     * too: otherwise a grown pet would never equal the saved file, and the
     * app would rewrite it and reload the widget every time.
     */
    const pet = fields.pet.copy();
    pet.bondLook = NO_BOND_LOOK;
    this.pet = pet;
    this.day = fields.day;
    this.focusMinutes = Math.max(fields.focusMinutes ?? 0, 0);
    this.streakDays = Math.max(fields.streakDays ?? 0, 0);
    this.lastFocusDay = fields.lastFocusDay;
    this.timer = fields.timer;
  }

  /*
   * Port of the WidgetState+Activity initializer: the state the app shares
   * from what it knows now, the pet's look, the running clock and the days
   * with focus in the activity log. `todayRecords` are the log's records for
   * the day of `now`; `focusDays` reach at least as far back as the streak
   * (`widgetFocusDays` collects them).
   */
  static fromActivity(options: {
    pet: PetProfile;
    timer: WidgetTimer | undefined;
    todayRecords: readonly ActivityRecord[];
    focusDays: ReadonlySet<PlannerDayKey>;
    now: Instant;
    timeZone: string;
  }): WidgetState {
    const today = plannerDayKeyOf(options.now, options.timeZone);
    const streak = widgetStreak(options.focusDays, today);
    return new WidgetState({
      pet: options.pet,
      day: today,
      focusMinutes: widgetFocusMinutes(options.todayRecords),
      streakDays: streak.days,
      lastFocusDay: streak.last,
      timer: options.timer,
    });
  }

  /** Minutes focused on the day containing `instant`: none once `day` is over. */
  minutesAt(instant: Instant, timeZone: string): number {
    return this.day === plannerDayKeyOf(instant, timeZone) ? this.focusMinutes : 0;
  }

  /**
   * The streak on the day containing `instant`. It still counts on the day
   * after the last focus (there is time left to keep it) and is 0 after.
   */
  streakAt(instant: Instant, timeZone: string): number {
    const last = this.lastFocusDay;
    if (last === undefined) return 0;
    const today = plannerDayKeyOf(instant, timeZone);
    return last === today || last === addingDaysToKey(today, -1) ? this.streakDays : 0;
  }

  /** The timer at `instant`: undefined once a countdown has run out, since the app may not be running to say what came next. */
  timerAt(instant: Instant): WidgetTimer | undefined {
    const timer = this.timer;
    if (timer?.clock.kind === "countdown" && timer.clock.endsAt <= instant) return undefined;
    return timer;
  }

  /**
   * The instants after `now` at which what the widget shows changes without
   * a new write from the app: the end of a countdown and the next midnight.
   */
  changeDates(now: Instant, timeZone: string): Instant[] {
    const dates = new Set<Instant>();
    const clock = this.timer?.clock;
    if (clock?.kind === "countdown" && clock.endsAt > now) dates.add(clock.endsAt);
    dates.add(dayKeyStart(addingDaysToKey(plannerDayKeyOf(now, timeZone), 1), timeZone));
    return [...dates].sort((a, b) => a - b);
  }

  equals(other: WidgetState): boolean {
    return (
      this.pet.equals(other.pet) &&
      this.day === other.day &&
      this.focusMinutes === other.focusMinutes &&
      this.streakDays === other.streakDays &&
      this.lastFocusDay === other.lastFocusDay &&
      sameTimer(this.timer, other.timer)
    );
  }

  /* Encoding */

  /** The Mac's Codable shape: dates as ISO 8601, the clock as Swift encodes an enum with associated values. */
  toJSON(): JSONObject {
    const json: JSONObject = {
      pet: this.pet.toJSON() as JSONObject,
      day: this.day,
      focusMinutes: this.focusMinutes,
      streakDays: this.streakDays,
    };
    if (this.lastFocusDay !== undefined) json.lastFocusDay = this.lastFocusDay;
    if (this.timer !== undefined) json.timer = encodeTimer(this.timer);
    return json;
  }

  /** The file's text, keys sorted and not pretty-printed, as the Mac writes it. */
  encode(): string {
    return WidgetState.schema.encode(this.toJSON(), { sortedKeys: true });
  }

  /** Reads the file's text; throws on a field it can't read. */
  static decode(text: string): WidgetState {
    return WidgetState.schema.decode(text, (document) => {
      const day = document.day;
      if (typeof day !== "string" || !isPlannerDayKey(day)) throw new TypeError("Invalid day");
      const integer = (key: string): number => {
        const value = document[key];
        if (typeof value !== "number" || !Number.isInteger(value)) throw new TypeError(`Invalid ${key}`);
        return value;
      };
      const last = document.lastFocusDay;
      if (last !== undefined && last !== null && (typeof last !== "string" || !isPlannerDayKey(last))) {
        throw new TypeError("Invalid lastFocusDay");
      }
      const timer = document.timer;
      return new WidgetState({
        pet: PetProfile.fromJSON(document.pet),
        day,
        focusMinutes: integer("focusMinutes"),
        streakDays: integer("streakDays"),
        lastFocusDay: typeof last === "string" ? last : undefined,
        timer: timer === undefined || timer === null ? undefined : decodeTimer(timer),
      });
    });
  }

  /* Samples */

  /** What the widget shows before the app has written anything: the starter cat with no focus yet. */
  static empty(now: Instant, timeZone: string): WidgetState {
    return new WidgetState({ pet: PetProfile.starter("cat"), day: plannerDayKeyOf(now, timeZone) });
  }

  /** Demo and widget gallery data: the starter cat on a five day streak, mid-way through a focus block. */
  static sample(now: Instant, timeZone: string): WidgetState {
    const today = plannerDayKeyOf(now, timeZone);
    return new WidgetState({
      pet: PetProfile.starter("cat"),
      day: today,
      focusMinutes: 85,
      streakDays: 5,
      lastFocusDay: today,
      timer: widgetTimer("focus", focusPhaseName("focus"), { kind: "countdown", endsAt: now + 18 * 60 }),
    });
  }
}

function encodeTimer(timer: WidgetTimer): JSONObject {
  let clock: JSONObject;
  switch (timer.clock.kind) {
    case "countdown":
      clock = { countdown: { endsAt: formatISODate(timer.clock.endsAt) } };
      break;
    case "countUp":
      clock = { countUp: { since: formatISODate(timer.clock.since) } };
      break;
    case "paused":
      clock = { paused: { shown: timer.clock.shown } };
      break;
  }
  return { phase: timer.phase, label: timer.label, clock };
}

function decodeTimer(json: unknown): WidgetTimer {
  if (!isJSONObject(json)) throw new TypeError("Invalid timer");
  const { phase, label, clock } = json;
  if (phase !== "focus" && phase !== "rest") throw new TypeError("Invalid timer phase");
  if (typeof label !== "string") throw new TypeError("Invalid timer label");
  if (!isJSONObject(clock)) throw new TypeError("Invalid timer clock");
  const date = (value: unknown): Instant => {
    const instant = typeof value === "string" ? parseISODate(value) : undefined;
    if (instant === undefined) throw new TypeError("Invalid timer date");
    return instant;
  };
  if (isJSONObject(clock.countdown)) return widgetTimer(phase, label, { kind: "countdown", endsAt: date(clock.countdown.endsAt) });
  if (isJSONObject(clock.countUp)) return widgetTimer(phase, label, { kind: "countUp", since: date(clock.countUp.since) });
  if (isJSONObject(clock.paused) && typeof clock.paused.shown === "number") {
    return widgetTimer(phase, label, { kind: "paused", shown: clock.paused.shown });
  }
  throw new TypeError("Invalid timer clock");
}

/**
 * The streak and its last day from the days that had focus, as of `today`:
 * consecutive days ending on the latest focus day on or before `today`.
 * Days after `today` (a clock set back) are ignored.
 */
export function widgetStreak(focusDays: ReadonlySet<PlannerDayKey>, today: PlannerDayKey): { days: number; last: PlannerDayKey | undefined } {
  const last = [...focusDays].filter((day) => day <= today).sort().pop();
  if (last === undefined) return { days: 0, last: undefined };
  let count = 0;
  let day = last;
  while (focusDays.has(day)) {
    count += 1;
    day = addingDaysToKey(day, -1);
  }
  return { days: count, last };
}

/** Whether a record is time spent focusing. Stretches stopped early count too, as they do in Wrap Up's study minutes. */
export function isWidgetFocus(record: ActivityRecord): boolean {
  return record.kind === ACTIVITY_KINDS.focusCompleted && (record.quantity ?? 0) > 0;
}

/** Whole minutes focused across `records`. */
export function widgetFocusMinutes(records: readonly ActivityRecord[]): number {
  return Math.trunc(records.filter(isWidgetFocus).reduce((sum, record) => sum + (record.quantity ?? 0), 0));
}

/**
 * The days with focus that a streak ending on `today` (or on the day before,
 * which still keeps it) can reach, read one day at a time from `records` and
 * stopping at the first day without focus, so a long history costs only as
 * many reads as the streak is long. `limit` bounds the walk.
 */
export async function widgetFocusDays(
  today: PlannerDayKey,
  records: (day: PlannerDayKey) => Promise<readonly ActivityRecord[]> | readonly ActivityRecord[],
  limit = 3660,
): Promise<Set<PlannerDayKey>> {
  const days = new Set<PlannerDayKey>();
  let day = today;
  for (let step = 0; step < Math.max(limit, 1); step++) {
    if ((await records(day)).some(isWidgetFocus)) {
      days.add(day);
    } else if (step > 0 || days.size > 0) {
      /* Today may have no focus yet; yesterday's streak still counts. */
      break;
    }
    day = addingDaysToKey(day, -1);
  }
  return days;
}

/**
 * Port of WidgetStateFile: reads and writes the shared state document in a
 * DocumentStore (the folder the widget reads, or memory in tests).
 */
export class WidgetStateFile {
  constructor(
    private readonly store: DocumentStore,
    readonly name: string = WidgetState.fileName,
  ) {}

  /** The saved state, or undefined when there is none or it can't be read. */
  async read(): Promise<WidgetState | undefined> {
    try {
      const text = await this.store.read(this.name);
      return text === undefined ? undefined : WidgetState.decode(text);
    } catch {
      return undefined;
    }
  }

  /** Saves `state` unless the file already holds it. Returns whether it wrote, so the widget reloads only on a change. */
  async write(state: WidgetState): Promise<boolean> {
    const saved = await this.read();
    if (saved?.equals(state)) return false;
    await this.store.write(this.name, state.encode());
    return true;
  }
}
