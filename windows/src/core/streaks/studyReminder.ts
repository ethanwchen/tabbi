import { tr } from "../localization/tr";
import { breedDisplayName, breedSpecies } from "../pets/petBreed";
import type { PetBreed } from "../pets/petKinds";
import { REFERENCE_DATE_OFFSET } from "../pets/petUnlocks";
import type { Instant } from "../time";
import { addDays, dayKey, nextDateMatching, startOfDay, type DayCalendar, type DayKey } from "./dayCalendar";

/*
 * Port of StudyReminder.swift: the optional daily study reminder. It is off
 * until the user turns it on, fires at most once a day at the time they
 * pick, and skips a day once the user has studied or met the day's goal.
 */

/** 7 pm: after school or work, with time left for a short session. */
const DEFAULT_MINUTE_OF_DAY = 19 * 60;

function clampMinute(minute: number): number {
  return Math.min(Math.max(Math.trunc(minute), 0), 24 * 60 - 1);
}

/** The user's daily study reminder settings. Port of StudyReminderSettings. */
export class StudyReminderSettings {
  static readonly defaultMinuteOfDay = DEFAULT_MINUTE_OF_DAY;
  static readonly off = new StudyReminderSettings(false, DEFAULT_MINUTE_OF_DAY);

  readonly isEnabled: boolean;
  /** Local time of day in minutes after midnight, clamped to 0..<1440. */
  readonly minuteOfDay: number;

  constructor(isEnabled: boolean, minuteOfDay: number = DEFAULT_MINUTE_OF_DAY) {
    this.isEnabled = isEnabled;
    this.minuteOfDay = clampMinute(minuteOfDay);
  }

  static at(isEnabled: boolean, hour: number, minute: number): StudyReminderSettings {
    return new StudyReminderSettings(isEnabled, hour * 60 + minute);
  }

  /** A copy at another time of day, clamped like the Mac's `didSet`. */
  withMinuteOfDay(minuteOfDay: number): StudyReminderSettings {
    return new StudyReminderSettings(this.isEnabled, minuteOfDay);
  }

  withEnabled(isEnabled: boolean): StudyReminderSettings {
    return new StudyReminderSettings(isEnabled, this.minuteOfDay);
  }

  get hour(): number {
    return Math.trunc(this.minuteOfDay / 60);
  }

  get minute(): number {
    return this.minuteOfDay % 60;
  }

  equals(other: StudyReminderSettings): boolean {
    return this.isEnabled === other.isEnabled && this.minuteOfDay === other.minuteOfDay;
  }

  toJSON(): { isEnabled: boolean; minuteOfDay: number } {
    return { isEnabled: this.isEnabled, minuteOfDay: this.minuteOfDay };
  }

  /** Reads leniently: a missing or damaged value keeps the default or is clamped, and never turns the reminder on. */
  static fromJSON(raw: unknown): StudyReminderSettings {
    const object = typeof raw === "object" && raw !== null ? (raw as Record<string, unknown>) : {};
    const isEnabled = typeof object.isEnabled === "boolean" ? object.isEnabled : false;
    const minute =
      typeof object.minuteOfDay === "number" && Number.isInteger(object.minuteOfDay)
        ? object.minuteOfDay
        : DEFAULT_MINUTE_OF_DAY;
    return new StudyReminderSettings(isEnabled, minute);
  }
}

/** The notification's text. */
export interface StudyReminderMessage {
  readonly title: string;
  readonly body: string;
}

/** A short, guilt-free nudge in the pet's voice, with a word about a running streak. */
export function reminderMessage(petName: string | undefined, streakLength: number): StudyReminderMessage {
  const name = petName?.trim() ?? "";
  const speaker = name === "" ? "Tabbi" : name;
  return {
    title: tr("%@ misses you", speaker),
    body: streakLength > 0 ? tr("10 minutes? That keeps your %lld-day streak going.", streakLength) : tr("10 minutes?"),
  };
}

/** The chosen time on `day`; a time a daylight saving change skips moves to the next valid moment. */
export function reminderFireDate(day: DayKey, settings: StudyReminderSettings, calendar: DayCalendar): Instant {
  const start = startOfDay(day, calendar);
  if (settings.minuteOfDay === 0) return start;
  return nextDateMatching(start, settings.hour, settings.minute, calendar);
}

/**
 * The moment the reminder should fire next, or undefined when it is off.
 * Today's is skipped once studied, met or delivered; tomorrow's is always
 * planned, because tomorrow has no study yet.
 */
export function nextReminderFireDate(options: {
  settings: StudyReminderSettings;
  now: Instant;
  studiedToday: boolean;
  goalMetToday: boolean;
  lastDelivered?: Instant;
  calendar: DayCalendar;
}): Instant | undefined {
  const { settings, now, calendar } = options;
  if (!settings.isEnabled) return undefined;
  const today = dayKey(now, calendar);
  const deliveredToday = options.lastDelivered !== undefined && dayKey(options.lastDelivered, calendar) === today;
  if (!options.studiedToday && !options.goalMetToday && !deliveredToday) {
    const fire = reminderFireDate(today, settings, calendar);
    if (fire > now) return fire;
  }
  return reminderFireDate(addDays(today, 1), settings, calendar);
}

/** The pet a reminder speaks for: its name and breed. */
export interface ReminderPet {
  readonly name: string;
  readonly breed: PetBreed;
}

/** Who the reminder speaks for: the pet's name, or "Your cat" while a cat still goes by its breed. */
export function reminderSpeaker(pet: ReminderPet): string {
  if (pet.name !== breedDisplayName(pet.breed)) return pet.name;
  return breedSpecies(pet.breed) === "cat" ? tr("Your cat") : tr("Your dog");
}

/** A shared progress item, as far as the reminder reads it (the providers port owns the full shape). */
export interface ReminderProgressItem {
  readonly id: string;
  readonly completed: number;
  readonly target: number;
}

/** The Study timer's daily focus goal id (StudyDailyGoal.progressID). */
export const STUDY_DAILY_GOAL_PROGRESS_ID = "minutes";

/** Whether the day's study goal is met in the shared progress; false when no module shares it. */
export function reminderGoalMet(progress: readonly ReminderProgressItem[]): boolean {
  return progress.some(
    (item) => item.id === STUDY_DAILY_GOAL_PROGRESS_ID && item.target > 0 && item.completed >= item.target,
  );
}

/**
 * The reminder's saved state: the settings plus what was planned and
 * delivered, so a relaunch never sends a second reminder the same day.
 * Port of StudyReminderSave.
 */
export class StudyReminderSave {
  /** The current format version, written as `schemaVersion`. */
  static readonly schemaVersion = 1;

  settings: StudyReminderSettings;
  /** The moment the pending reminder is set for, if one is. */
  scheduledFor: Instant | undefined;
  /** When a reminder last fired. */
  lastDelivered: Instant | undefined;

  constructor(settings: StudyReminderSettings = StudyReminderSettings.off, scheduledFor?: Instant, lastDelivered?: Instant) {
    this.settings = settings;
    this.scheduledFor = scheduledFor;
    this.lastDelivered = lastDelivered;
  }

  /** Counts a planned reminder whose moment has passed as delivered. */
  settle(now: Instant): void {
    const scheduledFor = this.scheduledFor;
    if (scheduledFor === undefined || scheduledFor > now) return;
    this.lastDelivered = Math.max(this.lastDelivered ?? scheduledFor, scheduledFor);
    this.scheduledFor = undefined;
  }

  /** Settles the past and plans the next reminder, returning its moment. */
  plan(now: Instant, studiedToday: boolean, goalMetToday: boolean, calendar: DayCalendar): Instant | undefined {
    this.settle(now);
    this.scheduledFor = nextReminderFireDate({
      settings: this.settings,
      now,
      studiedToday,
      goalMetToday,
      ...(this.lastDelivered === undefined ? {} : { lastDelivered: this.lastDelivered }),
      calendar,
    });
    return this.scheduledFor;
  }

  /** The Mac's JSON form: dates as seconds since 2001, plus `schemaVersion`. */
  toJSON(): Record<string, unknown> {
    return {
      settings: this.settings.toJSON(),
      ...(this.scheduledFor === undefined ? {} : { scheduledFor: this.scheduledFor - REFERENCE_DATE_OFFSET }),
      ...(this.lastDelivered === undefined ? {} : { lastDelivered: this.lastDelivered - REFERENCE_DATE_OFFSET }),
      schemaVersion: StudyReminderSave.schemaVersion,
    };
  }

  /** Reads leniently: a damaged field falls back to its default. Throws when the value is not an object. */
  static fromJSON(raw: unknown): StudyReminderSave {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("Not a reminder save");
    const object = raw as Record<string, unknown>;
    const date = (value: unknown) =>
      typeof value === "number" && Number.isFinite(value) ? value + REFERENCE_DATE_OFFSET : undefined;
    const settings =
      typeof object.settings === "object" && object.settings !== null
        ? StudyReminderSettings.fromJSON(object.settings)
        : StudyReminderSettings.off;
    return new StudyReminderSave(settings, date(object.scheduledFor), date(object.lastDelivered));
  }
}
