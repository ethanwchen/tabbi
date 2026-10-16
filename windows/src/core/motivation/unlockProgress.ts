import { PetEconomy } from "../closet/petEconomy";
import type { PetCloset } from "../closet/petCloset";
import type { PetStudyAward } from "../closet/petStudyCredit";
import { tr } from "../localization/tr";
import { itemDisplayName, type PetItem } from "../pets/petItem";
import { itemCost, SHOP_ITEMS, type PetPointsLedger } from "../pets/petUnlocks";

/**
 * Port of UnlockProgress: how close the pet is to the next shop item, before
 * and after the points a session just earned. It is what the end-of-session
 * bar fills toward ("1 more session to Ninja Headband") and what the closed
 * island hints at when an unlock is near (the goal-gradient effect).
 *
 * The goal is the cheapest shop item not owned that the points before the
 * session could not buy yet, so a session that makes an item affordable
 * fills the bar to the end instead of jumping to the next goal.
 */
export class UnlockProgress {
  /** Sessions left at or under which an unlock counts as near. */
  static readonly nearSessions = 2;

  constructor(
    readonly item: PetItem,
    /** Spendable points before the session. */
    readonly balanceBefore: number,
    /** Spendable points now. */
    readonly balance: number,
    /** Points one more session like this one earns, for `sessionsLeft`. */
    readonly pointsPerSession: number,
  ) {}

  /**
   * The progress at `balance` after a session that `earned` points, toward
   * what `ledger` does not own yet; undefined when every shop item is owned.
   * `pointsPerSession` paces it, a typical focus block when undefined or not
   * positive.
   */
  static make(balance: number, ledger: PetPointsLedger, earned = 0, pointsPerSession?: number): UnlockProgress | undefined {
    const before = Math.max(0, balance - earned);
    let goal: PetItem | undefined;
    for (const item of SHOP_ITEMS) {
      if (ledger.owns(item) || !(itemCost(item) > before)) continue;
      /* The first cheapest wins a tie, like Swift's min(by:). */
      if (goal === undefined || itemCost(item) < itemCost(goal)) goal = item;
    }
    if (goal === undefined) return undefined;
    const perSession = pointsPerSession ?? 0;
    return new UnlockProgress(goal, before, balance, perSession > 0 ? perSession : PetEconomy.pointsPerTypicalBlock());
  }

  /** The progress right after `award` was credited to `closet`, paced by the award's own sessions. */
  static after(award: PetStudyAward, closet: PetCloset): UnlockProgress | undefined {
    const pace = award.completedSessions > 0 ? Math.trunc(award.points / award.completedSessions) : undefined;
    return UnlockProgress.make(closet.balance, closet.save.ledger, award.points, pace);
  }

  /** The pet's progress for its closet now, with no session just earned. */
  static of(closet: PetCloset): UnlockProgress | undefined {
    return UnlockProgress.make(closet.balance, closet.save.ledger);
  }

  get cost(): number {
    return itemCost(this.item);
  }

  /** Points still missing; 0 once the item is affordable. */
  get missing(): number {
    return Math.max(0, this.cost - this.balance);
  }

  get isReady(): boolean {
    return this.missing === 0;
  }

  /** How full the bar was before the session, from 0 to 1. */
  get fractionBefore(): number {
    return UnlockProgress.fraction(this.balanceBefore, this.cost);
  }

  /** How full the bar is now, from 0 to 1. */
  get fraction(): number {
    return UnlockProgress.fraction(this.balance, this.cost);
  }

  /** Sessions like the last one still needed; 0 once ready. */
  get sessionsLeft(): number {
    return this.missing === 0 ? 0 : Math.trunc((this.missing + this.pointsPerSession - 1) / this.pointsPerSession);
  }

  /** Whether the unlock is close enough for the closed island to hint at it. */
  get isNear(): boolean {
    return this.sessionsLeft <= UnlockProgress.nearSessions;
  }

  /** The line under the bar, e.g. "1 more session to Ninja Headband". */
  get line(): string {
    const name = itemDisplayName(this.item);
    return this.sessionsLeft === 0 ? tr("Enough for the %@ now", name) : tr("%lld more sessions to %@", this.sessionsLeft, name);
  }

  private static fraction(points: number, cost: number): number {
    if (!(cost > 0)) return 1;
    return Math.min(1, Math.max(0, points / cost));
  }
}
