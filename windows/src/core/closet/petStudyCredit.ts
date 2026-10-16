import {
  ACTIVITY_KINDS,
  ACTIVITY_UNITS,
  activityOutcome,
  type ActivityRecord,
} from "../activity/activityRecord";
import { MODULE_IDS } from "../modules/moduleId";
import { tr } from "../localization/tr";
import type { ProvidedFocus } from "../providers/providedFocus";
import { itemDisplayName, type PetItem } from "../pets/petItem";
import type { Instant } from "../time";
import { PetCloset } from "./petCloset";

/*
 * Port of PetStudyCredit.swift: points the pet earned from study sessions
 * that just ended, for the celebration, and the rules that credit them.
 */

/** Points from sessions that just ended. Port of PetStudyAward. */
export interface PetStudyAward {
  /** Focus phases that ran to their end. */
  readonly completedSessions: number;
  /** Minutes studied across the credited sessions. */
  readonly minutes: number;
  readonly points: number;
  /** Items out of reach before this award and affordable now, cheapest first. */
  readonly unlocked: readonly PetItem[];
}

/** Whether this award is a level-up moment: something new to buy. */
export function awardIsLevelUp(award: PetStudyAward): boolean {
  return award.unlocked.length > 0;
}

/** A finished or cut short stay in a Party shared session, as Party reports it. */
export interface PartySessionCompletion {
  readonly minutes: number;
  readonly friendCount: number;
  readonly finished: boolean;
}

function affordable(closet: PetCloset): Set<PetItem> {
  return new Set(PetCloset.wardrobe.filter((item) => closet.state(item).kind === "affordable"));
}

function newlyAffordable(closet: PetCloset, before: Set<PetItem>): PetItem[] {
  return PetCloset.wardrobe.filter((item) => closet.state(item).kind === "affordable" && !before.has(item));
}

/** A focus phase under way in `old` that `next` left without completing it. */
function focusWasCutShort(old: ProvidedFocus, next: ProvidedFocus): boolean {
  if (old.phase !== "focus" || !old.isActive) return false;
  return next.phase !== "focus" || !next.isActive;
}

/**
 * Credits study points for what changed between two observations of the
 * shared focus clock at `now`, and returns the award to celebrate, or
 * undefined when nothing earned points. Completions count against the
 * save's credited count of the same clock, so sessions that ended while the
 * app was closed are paid once and another clock only sets a new baseline.
 */
export function creditFocus(
  closet: PetCloset,
  old: ProvidedFocus | undefined,
  next: ProvidedFocus | undefined,
  now: Instant,
): PetStudyAward | undefined {
  if (!next) return undefined;
  const save = closet.save;
  const count = next.completedFocusCount;
  const sameClock = save.creditedFocusSource === undefined || save.creditedFocusSource === next.source;
  save.creditedFocusSource = next.source;
  const credited = save.creditedFocusCount;
  if (!sameClock || credited === undefined || credited > count) {
    /* First sight of a timer, another clock, or its history was reset: start over. */
    save.creditedFocusCount = count;
    return undefined;
  }
  save.creditedFocusCount = count;
  const before = affordable(closet);
  let points = 0;
  let minutes = 0;
  let completedSessions = 0;
  if (count > credited) {
    const length = Math.trunc((next.focusLength ?? 0) / 60);
    for (let i = credited; i < count; i++) points += closet.recordStudy(length, true);
    completedSessions = count - credited;
    minutes = length * completedSessions;
  } else if (old && !old.logsEarlyEnds && old.source === next.source && focusWasCutShort(old, next)) {
    minutes = Math.trunc(old.elapsed(now) / 60);
    points = closet.recordStudy(minutes, false);
  }
  if (!(points > 0)) return undefined;
  return { completedSessions, minutes, points, unlocked: newlyAffordable(closet, before) };
}

/**
 * Credits a focus phase cut short (stopped, skipped, or ended by sleep or
 * quit) from its activity record: the minutes studied, without the bonus.
 * Undefined for anything else and when nothing was earned.
 */
export function creditRecord(closet: PetCloset, record: ActivityRecord): PetStudyAward | undefined {
  const quantity = record.quantity;
  if (record.kind !== ACTIVITY_KINDS.focusCompleted || record.source === MODULE_IDS.party || record.unit !== ACTIVITY_UNITS.minutes) return undefined;
  if (quantity === undefined || !Number.isFinite(quantity)) return undefined;
  const outcome = activityOutcome(record);
  if (outcome !== "skipped" && outcome !== "abandoned") return undefined;
  const before = affordable(closet);
  const minutes = Math.trunc(Math.max(quantity, 0));
  const points = closet.recordStudy(minutes, false);
  if (!(points > 0)) return undefined;
  return { completedSessions: 0, minutes, points, unlocked: newlyAffordable(closet, before) };
}

/** Credits a stay in a Party shared session, finished or cut short; undefined when too short. */
export function creditPartySession(closet: PetCloset, session: PartySessionCompletion): PetStudyAward | undefined {
  const before = affordable(closet);
  const points = closet.save.ledger.recordSharedSession(session.minutes, session.friendCount, session.finished);
  if (!(points > 0)) return undefined;
  return {
    completedSessions: session.finished ? 1 : 0,
    minutes: session.minutes,
    points,
    unlocked: newlyAffordable(closet, before),
  };
}

/** The celebration bubble's first line. Kind and plain, and it never names a subject. */
export function awardHeadline(award: PetStudyAward): string {
  switch (award.completedSessions) {
    case 0:
      return tr("%lld minutes in the bank.", award.minutes);
    case 1: {
      const cheers = [tr("Session done. Nice work!"), tr("That's a wrap. Well done!"), tr("Done! You stuck with it.")];
      return cheers[award.minutes % cheers.length] ?? cheers[0] ?? "";
    }
    default:
      return tr("%lld sessions done. Wow!", award.completedSessions);
  }
}

/** The second line on a level-up, such as "Enough for the Beanie now."; undefined otherwise. */
export function awardUnlockLine(award: PetStudyAward): string | undefined {
  const [first, second] = award.unlocked;
  if (!first) return undefined;
  if (!second) return tr("Enough for the %@ now.", itemDisplayName(first));
  return tr("Enough for the %@ and the %@ now.", itemDisplayName(first), itemDisplayName(second));
}

/** The points pill, such as "+35". */
export function awardPointsText(award: PetStudyAward): string {
  return `+${award.points}`;
}
