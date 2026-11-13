import type { ActivityRecord } from "../activity/activityRecord";
import type { PetLimitedProgress } from "../closet/petLimited";
import type { DayCalendar } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import { MonthlyQuests, monthAt, type MonthKey, type MonthlyQuestProgress } from "./monthlyQuests";
import { ProgressTally, longestGentleStreak } from "./progressTally";
import { ProgressionSave } from "./progressionSave";
import {
  levelFromMinutes,
  levelStartsRank,
  levelUnlocksNameplate,
  nameplateUnlockLevel,
  type Nameplate,
  type StudyStanding,
} from "./studyLevel";
import {
  ALL_BADGES,
  PROGRESS_TIERS,
  PROGRESS_TRACKS,
  badgeFromID,
  badgeGoal,
  badgeID,
  compareBadges,
  nextTier,
  progressLabel,
  trackGoal,
  type ProgressBadge,
  type ProgressTier,
  type ProgressTrack,
} from "./progressTrack";

/*
 * Port of PetProgression.swift: the Goals section's state, the tally read
 * from the activity log and the save that remembers it, joined into each
 * track's count, the tiers reached, this month's quests and what is new.
 * A count is the larger of the log and the save's best, so deleting day
 * files never takes progress back.
 */

/** What one `refresh` added: badge tiers reached, months finished and Study Levels gained (lowest first) for the first time. */
export interface ProgressionChange {
  readonly badges: ProgressBadge[];
  readonly months: MonthKey[];
  readonly levels: number[];
}

export function changeIsEmpty(change: ProgressionChange): boolean {
  return change.badges.length === 0 && change.months.length === 0 && change.levels.length === 0;
}

/** Whether a level gained unlocked a nameplate color or a rank, worth a sparkle over the panel. */
export function changeUnlocksSomething(change: ProgressionChange): boolean {
  return change.levels.some((level) => levelUnlocksNameplate(level) || levelStartsRank(level));
}

export class PetProgression {
  readonly tally: ProgressTally;
  readonly save: ProgressionSave;
  /** Each track's count at the last `refresh`. */
  readonly values = new Map<ProgressTrack, number>();

  constructor(save: ProgressionSave = new ProgressionSave(), tally: ProgressTally = new ProgressTally()) {
    this.save = save;
    this.tally = tally;
    for (const [track, value] of save.best) this.values.set(track, value);
  }

  add(record: ActivityRecord, calendar: DayCalendar): void {
    this.tally.add(record, calendar);
  }

  /** Recounts every track at `now` and records new bests, tiers and finished months in the save. */
  refresh(now: Instant, freezePurchases: readonly Instant[], calendar: DayCalendar): ProgressionChange {
    const change: ProgressionChange = { badges: [], months: [], levels: [] };
    for (const month of MonthlyQuests.completedMonths(this.tally, now, calendar)) {
      if (!this.save.completedMonths.has(month)) {
        this.save.completedMonths.add(month);
        change.months.push(month);
      }
    }
    for (const track of PROGRESS_TRACKS) {
      let live: number;
      switch (track) {
        case "gentleStreak":
          live = longestGentleStreak(this.tally.studyDays, freezePurchases, now, calendar);
          break;
        case "steadyWeeks":
          live = this.tally.steadyWeeks();
          break;
        case "monthlyQuests":
          live = this.save.completedMonths.size;
          break;
        default:
          live = this.tally.total(track);
      }
      const value = Math.max(live, this.save.best.get(track) ?? 0);
      this.values.set(track, value);
      if (value > 0) this.save.best.set(track, value);
      for (const tier of PROGRESS_TIERS) {
        if (value < trackGoal(track, tier)) continue;
        const id = badgeID({ track, tier });
        if (!this.save.reached.has(id)) {
          this.save.reached.set(id, now);
          change.badges.push({ track, tier });
        }
      }
    }
    const level = levelFromMinutes(this.value("focusHours"));
    if (level > this.save.level) {
      for (let gained = this.save.level + 1; gained <= level; gained++) change.levels.push(gained);
      this.save.level = level;
    }
    return change;
  }

  // Study Level

  /** From every focused minute so far, never below the highest the save remembers. */
  get studyLevel(): number {
    return Math.max(levelFromMinutes(this.value("focusHours")), this.save.level);
  }

  get focusMinutes(): number {
    return this.value("focusHours");
  }

  /** The nameplate shown: the one picked, if the level has it. */
  get nameplate(): Nameplate {
    const picked = this.save.nameplate;
    if (picked === undefined || nameplateUnlockLevel(picked) > this.studyLevel) return "plain";
    return picked;
  }

  get standing(): StudyStanding {
    return { level: this.studyLevel, nameplate: this.nameplate };
  }

  /** Picks a nameplate; false (and nothing changes) when still locked or already picked. */
  pick(nameplate: Nameplate): boolean {
    if (nameplateUnlockLevel(nameplate) > this.studyLevel || nameplate === this.nameplate) return false;
    this.save.nameplate = nameplate === "plain" ? undefined : nameplate;
    return true;
  }

  get hasUnseenLevel(): boolean {
    return this.studyLevel > this.save.levelSeen;
  }

  value(track: ProgressTrack): number {
    return this.values.get(track) ?? 0;
  }

  /** The highest tier reached on `track`, or undefined before Bronze. */
  tier(track: ProgressTrack): ProgressTier | undefined {
    let reached: ProgressTier | undefined;
    for (const tier of PROGRESS_TIERS) if (this.save.reached.has(badgeID({ track, tier }))) reached = tier;
    return reached;
  }

  isReached(badge: ProgressBadge): boolean {
    return this.save.reached.has(badgeID(badge));
  }

  /** The tier `track` is working toward, or undefined once Starlight is reached. */
  nextTier(track: ProgressTrack): ProgressTier | undefined {
    const tier = this.tier(track);
    return tier === undefined ? "bronze" : nextTier(tier);
  }

  progress(badge: ProgressBadge): PetLimitedProgress {
    const goal = badgeGoal(badge);
    const value = Math.min(this.value(badge.track), goal);
    return { value, goal, label: progressLabel(badge.track, value, goal) };
  }

  /** Badge tiers reached and not seen yet, in badge order. */
  get unseen(): ProgressBadge[] {
    return [...this.save.reached.keys()]
      .filter((id) => !this.save.seen.has(id))
      .flatMap((id) => badgeFromID(id) ?? [])
      .sort(compareBadges);
  }

  /** Marks every tier and the level reached so far as seen; returns whether anything changed. */
  markSeen(): boolean {
    const unseen = this.unseen;
    const level = this.studyLevel;
    if (unseen.length === 0 && level <= this.save.levelSeen) return false;
    for (const badge of unseen) this.save.seen.add(badgeID(badge));
    this.save.level = Math.max(this.save.level, level);
    this.save.levelSeen = Math.max(this.save.levelSeen, level);
    return true;
  }

  get reachedCount(): number {
    return this.save.reached.size;
  }

  quests(now: Instant, calendar: DayCalendar): MonthlyQuestProgress[] {
    return MonthlyQuests.progress(monthAt(now, calendar), this.tally);
  }
}

/** Every badge, for the count "16 of 48 badges". */
export const BADGE_COUNT = ALL_BADGES.length;
