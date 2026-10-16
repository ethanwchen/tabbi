import {
  ACTIVITY_KINDS,
  ACTIVITY_UNITS,
  activityDay,
  activityOutcome,
  makeActivityRecord,
  type ActivityRecord,
} from "../activity/activityRecord";
import { MODULE_IDS } from "../modules/moduleId";
import { SeasonalEventCatalog } from "../events/seasonalEventCatalog";
import { HOUR_LABEL_MINUTES, type SeasonalEvent, type SeasonalEventReward } from "../events/seasonalEvent";
import { tr } from "../localization/tr";
import { accessoryItem, outfitItem, type PetItem } from "../pets/petItem";
import { PetPointsRules } from "../pets/petPointsRules";
import type { Instant } from "../time";
import {
  addDays,
  daysBetween,
  dayKey,
  startOfDay as startOf,
  type DayCalendar,
  type DayKey,
} from "../streaks/dayCalendar";

/*
 * Port of PetLimited.swift: the limited edition items (never sold, earned
 * from a milestone or granted for an event), their effects, and the
 * milestone progress read from the activity log.
 */

/** A subtle animated effect a costume item can carry. Port of PetItemEffect. */
export type PetItemEffect = "shimmer" | "flicker" | "sparkle" | "drift";

/** A study milestone that unlocks a limited edition item by itself. Port of PetMilestone. */
export const PET_MILESTONES = ["weekStreak", "fiftyHours", "firstParty"] as const;
export type PetMilestone = (typeof PET_MILESTONES)[number];

/** The goal in the milestone's own unit: days, minutes or sessions. */
export function milestoneGoal(milestone: PetMilestone): number {
  switch (milestone) {
    case "weekStreak":
      return 7;
    case "fiftyHours":
      return 50 * 60;
    case "firstParty":
      return 1;
  }
}

/** How a limited edition item is earned. Port of PetLimitedSource. */
export type PetLimitedSource =
  | { readonly kind: "milestone"; readonly milestone: PetMilestone }
  | { readonly kind: "event"; readonly id: string }
  | { readonly kind: "season"; readonly id: string };

/** The limited edition items, in shelf order. Port of PetLimitedEdition. */
export const PET_LIMITED_EDITIONS = [
  "launchWeekCap",
  "streakFlame",
  "focusLaurel",
  "partyMedal",
  "halloweenWitchHat",
  "halloweenPumpkin",
  "winterAntlers",
  "winterScarf",
  "valentinesGlasses",
  "summerShades",
  "lunarNewYearLion",
  "springSakura",
  "examHoodie",
  "foundingMember",
] as const;
export type PetLimitedEdition = (typeof PET_LIMITED_EDITIONS)[number];

const EDITIONS: Record<PetLimitedEdition, { item: PetItem; source: PetLimitedSource; effect?: PetItemEffect }> = {
  launchWeekCap: { item: accessoryItem("backwardsCap"), source: { kind: "event", id: "launch-week" }, effect: "sparkle" },
  streakFlame: { item: accessoryItem("flameHeadband"), source: { kind: "milestone", milestone: "weekStreak" }, effect: "flicker" },
  focusLaurel: { item: accessoryItem("goldenLaurel"), source: { kind: "milestone", milestone: "fiftyHours" }, effect: "shimmer" },
  partyMedal: { item: accessoryItem("teamMedal"), source: { kind: "milestone", milestone: "firstParty" }, effect: "sparkle" },
  halloweenWitchHat: { item: accessoryItem("moonlitWitchHat"), source: { kind: "season", id: "halloween" } },
  halloweenPumpkin: { item: accessoryItem("pumpkinHat"), source: { kind: "season", id: "halloween" }, effect: "flicker" },
  winterAntlers: { item: accessoryItem("reindeerAntlers"), source: { kind: "season", id: "winter-holidays" } },
  winterScarf: { item: accessoryItem("snowScarf"), source: { kind: "season", id: "winter-holidays" }, effect: "sparkle" },
  valentinesGlasses: { item: accessoryItem("heartGlasses"), source: { kind: "season", id: "valentines" }, effect: "sparkle" },
  summerShades: { item: accessoryItem("summerShades"), source: { kind: "season", id: "summer" }, effect: "sparkle" },
  lunarNewYearLion: { item: accessoryItem("lionDanceHat"), source: { kind: "season", id: "lunar-new-year" }, effect: "sparkle" },
  springSakura: { item: accessoryItem("sakuraSprig"), source: { kind: "season", id: "spring" }, effect: "drift" },
  examHoodie: { item: outfitItem("studyHoodie"), source: { kind: "season", id: "exam-season" }, effect: "shimmer" },
  foundingMember: { item: accessoryItem("foundersPin"), source: { kind: "event", id: "founding" }, effect: "sparkle" },
};

export function editionItem(edition: PetLimitedEdition): PetItem {
  return EDITIONS[edition].item;
}

export function editionSource(edition: PetLimitedEdition): PetLimitedSource {
  return EDITIONS[edition].source;
}

export function editionMilestone(edition: PetLimitedEdition): PetMilestone | undefined {
  const source = editionSource(edition);
  return source.kind === "milestone" ? source.milestone : undefined;
}

export function editionEffect(edition: PetLimitedEdition): PetItemEffect | undefined {
  return EDITIONS[edition].effect;
}

/** The limited edition an item belongs to, or undefined for a shop item. */
export function limitedEditionOf(item: PetItem): PetLimitedEdition | undefined {
  return PET_LIMITED_EDITIONS.find((edition) => EDITIONS[edition].item === item);
}

export function isLimited(item: PetItem): boolean {
  return limitedEditionOf(item) !== undefined;
}

/** The item's animated effect, if it has one. */
export function itemEffect(item: PetItem): PetItemEffect | undefined {
  const edition = limitedEditionOf(item);
  return edition ? editionEffect(edition) : undefined;
}

export type { SeasonalEventReward } from "../events/seasonalEvent";

/** The bundled event with `id`, from the events catalog. */
function catalogEvent(id: string): SeasonalEvent | undefined {
  return SeasonalEventCatalog.bundled.event(id);
}

/** The bundled event reward for a seasonal item, or undefined for any other. */
export function seasonalReward(edition: PetLimitedEdition): SeasonalEventReward | undefined {
  const source = editionSource(edition);
  if (source.kind !== "season") return undefined;
  const reward = catalogEvent(source.id)?.rewards.find((candidate) => candidate.item === editionItem(edition));
  return reward ? { item: editionItem(edition), focusMinutes: reward.focusMinutes } : undefined;
}

/** One line on how to earn the item, for the tile's tooltip and detail. */
export function howToEarn(edition: PetLimitedEdition): string {
  switch (edition) {
    case "launchWeekCap":
      return tr("For using Tabbi in its launch week.");
    case "streakFlame":
      return tr("Study 7 days in a row.");
    case "focusLaurel":
      return tr("Focus for 50 hours in total.");
    case "partyMedal":
      return tr("Finish a Party session with friends.");
    case "foundingMember":
      return tr("For signing in during Tabbi's first 100 days.");
    default:
      return seasonalHowToEarn(edition);
  }
}

/** "Focus for 90 minutes during Halloween.", with the event's name and goal from the catalog. */
function seasonalHowToEarn(edition: PetLimitedEdition): string {
  const source = editionSource(edition);
  const event = source.kind === "season" ? catalogEvent(source.id) : undefined;
  if (!event) return tr("Focus while its event runs.");
  /* Event names translate through the catalog, keyed by their English text. */
  const name = tr(event.name);
  const minutes = seasonalReward(edition)?.focusMinutes;
  if (minutes === undefined) return tr("Focus during %@.", name);
  return minutes < HOUR_LABEL_MINUTES
    ? tr("Focus for %lld minutes during %@.", minutes, name)
    : tr("Focus for %lld hours during %@.", Math.trunc(minutes / 60), name);
}

/** The tile's progress toward a limited item: a fraction and a short count. Port of PetLimitedProgress. */
export interface PetLimitedProgress {
  readonly value: number;
  readonly goal: number;
  /** The tile label, such as "4/7 days" or "31/50 h". */
  readonly label: string;
}

export function limitedProgressFraction(progress: PetLimitedProgress): number {
  return progress.goal > 0 ? Math.min(1, progress.value / progress.goal) : 0;
}

/** The progress label for `value` (capped at the goal). Hours round down. */
export function milestoneProgress(milestone: PetMilestone, valueIn: number): PetLimitedProgress {
  const goal = milestoneGoal(milestone);
  const value = Math.max(0, Math.min(valueIn, goal));
  let label: string;
  switch (milestone) {
    case "weekStreak":
      label = tr("%lld/%lld days", value, goal);
      break;
    case "fiftyHours":
      label = tr("%lld/%lld h", Math.trunc(value / 60), Math.trunc(goal / 60));
      break;
    case "firstParty":
      label = tr("%lld/%lld session", value, goal);
      break;
  }
  return { value, goal, label };
}

/**
 * The user's progress toward every milestone, from the activity log:
 * focused minutes, the days with some focused study and the Party sessions
 * finished. Adding a record twice counts it once. Port of PetMilestoneProgress.
 */
export class PetMilestoneProgress {
  /** A day counts toward a streak once it has this many focused minutes. */
  static readonly minutesForStudyDay = PetPointsRules.minimumMinutes;

  focusMinutes = 0;
  readonly minutesByDay = new Map<DayKey, number>();
  finishedPartySessions = 0;
  private readonly seen = new Set<string>();

  constructor(records: Iterable<ActivityRecord> = [], calendar?: DayCalendar) {
    if (calendar) for (const record of records) this.add(record, calendar);
  }

  add(record: ActivityRecord, calendar: DayCalendar): void {
    const quantity = record.quantity;
    if (record.kind !== ACTIVITY_KINDS.focusCompleted || record.unit !== ACTIVITY_UNITS.minutes || quantity === undefined) return;
    if (!Number.isFinite(quantity) || !(quantity > 0) || this.seen.has(record.id)) return;
    this.seen.add(record.id);
    this.focusMinutes += quantity;
    const day = activityDay(record, calendar.timeZone);
    this.minutesByDay.set(day, (this.minutesByDay.get(day) ?? 0) + quantity);
    if (record.source === MODULE_IDS.party && activityOutcome(record) === "completed") this.finishedPartySessions += 1;
  }

  /** The days with enough focused study, oldest first. */
  get studyDays(): DayKey[] {
    return [...this.minutesByDay.entries()]
      .filter(([, minutes]) => minutes >= PetMilestoneProgress.minutesForStudyDay)
      .map(([day]) => day)
      .sort();
  }

  /** The longest run of consecutive study days ever. */
  longestStreak(): number {
    let longest = 0;
    let run = 0;
    let previous: DayKey | undefined;
    for (const day of this.studyDays) {
      run = previous !== undefined && daysBetween(previous, day) === 1 ? run + 1 : 1;
      longest = Math.max(longest, run);
      previous = day;
    }
    return longest;
  }

  /** The run of study days ending today, or yesterday when today has no study yet. */
  currentStreak(today: Instant, calendar: DayCalendar): number {
    const days = new Set(this.studyDays);
    let day = dayKey(today, calendar);
    if (!days.has(day)) day = addDays(day, -1);
    let streak = 0;
    while (days.has(day)) {
      streak += 1;
      day = addDays(day, -1);
    }
    return streak;
  }

  /** How far along a milestone is, in its own unit, capped at its goal. */
  value(milestone: PetMilestone, today: Instant, calendar: DayCalendar): number {
    let value: number;
    switch (milestone) {
      case "weekStreak":
        value = this.currentStreak(today, calendar);
        break;
      case "fiftyHours":
        value = Math.trunc(this.focusMinutes);
        break;
      case "firstParty":
        value = this.finishedPartySessions;
        break;
    }
    return Math.min(value, milestoneGoal(milestone));
  }

  isReached(milestone: PetMilestone): boolean {
    switch (milestone) {
      case "weekStreak":
        return this.longestStreak() >= milestoneGoal(milestone);
      case "fiftyHours":
        return Math.trunc(this.focusMinutes) >= milestoneGoal(milestone);
      case "firstParty":
        return this.finishedPartySessions >= milestoneGoal(milestone);
    }
  }

  /** The Limited shelf's progress for `edition`, or undefined for an event item. */
  progress(edition: PetLimitedEdition, today: Instant, calendar: DayCalendar): PetLimitedProgress | undefined {
    const milestone = editionMilestone(edition);
    return milestone ? milestoneProgress(milestone, this.value(milestone, today, calendar)) : undefined;
  }

  /**
   * The demo progress: a 4 day streak and 40 hours focused, no Party
   * session yet, a frozen day 4 days ago, and about five months of history
   * that grows denser toward today.
   */
  static demo(today: Instant, calendar: DayCalendar): PetMilestoneProgress {
    const start = dayKey(today, calendar);
    let next = 0;
    const record = (daysAgo: number, minutes: number): ActivityRecord | undefined => {
      if (!(minutes > 0)) return undefined;
      const day = addDays(start, -daysAgo);
      /* Ten hours after local midnight, as the Mac adds 10 hours to the start of the day. */
      const end = startOf(day, calendar) + 10 * 3600;
      next += 1;
      return makeActivityRecord({
        id: `demo-${next}`,
        source: "focus",
        kind: ACTIVITY_KINDS.focusCompleted,
        start: end,
        quantity: minutes,
        unit: ACTIVITY_UNITS.minutes,
      });
    };
    const records: ActivityRecord[] = [];
    DEMO_EARLIER.forEach((minutes, offset) => {
      const made = record(14 + offset, minutes);
      if (made) records.push(made);
    });
    for (const [daysAgo, minutes] of [
      [5, 50],
      [6, 80],
    ] as const) {
      const made = record(daysAgo, minutes);
      if (made) records.push(made);
    }
    [35, 95, 60, 120].forEach((minutes, daysAgo) => {
      const made = record(daysAgo, minutes);
      if (made) records.push(made);
    });
    return new PetMilestoneProgress(records, calendar);
  }
}

/** Minutes studied 14, 15, 16 and so on days ago in the demo history. */
const DEMO_EARLIER: readonly number[] = [
  0, 0, 0, 5, 50, 0, 95, 95, 0, 25, 0, 60, 90, 0, 30, 0, 30, 70, 0, 0, 0, 25, 85, 30, 5, 0, 25, 0, 45, 10, 30, 30, 45,
  0, 25, 0, 0, 0, 65, 65, 20, 45, 45, 0, 0, 0, 45, 0, 0, 5, 30, 0, 0, 0, 10, 75, 0, 0, 0, 0, 75, 75, 40, 15, 0, 0, 0,
  0, 55, 40, 0, 10, 0, 0, 40, 70, 0, 0, 0, 0, 0, 0, 0, 20, 0, 0, 0, 45, 5, 30, 0, 0, 0, 0, 0, 50, 0, 5, 0, 0, 0, 5, 5,
  0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 40, 50, 5, 5,
];
