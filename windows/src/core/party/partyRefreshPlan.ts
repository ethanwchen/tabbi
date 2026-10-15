import type { Instant, Seconds } from "../time";

/*
 * Port of PartyRefreshPlan: when to fetch the server data the Party panel
 * shows, following the polling table exactly (HANDOFF section 6 and the
 * API's polling guidance):
 *
 * - friends: when the panel opens, then every 60 s while it stays open;
 * - party: every 30 s only while I'm in a party and the panel is visible,
 *   once per opening otherwise;
 * - leaderboard: once each time its view opens, never on a timer;
 * - nothing at all while the panel is hidden.
 *
 * The presence heartbeat follows `PartyHeartbeatSchedule` instead. The
 * free plan's request budget is shared by every user, so this never polls
 * faster. The store calls `didFetch` after every attempt, failed or not,
 * so a down server is retried at the normal interval, never in a loop.
 */

export type PartyFeed = "friends" | "party" | "leaderboard";

/** The feeds in display order. */
export const PARTY_FEEDS: readonly PartyFeed[] = ["friends", "party", "leaderboard"];

export class PartyRefreshPlan {
  static readonly friendsInterval: Seconds = 60;
  static readonly partyInterval: Seconds = 30;

  private visible = false;
  private leaderboardShown = false;
  /** Whether I'm in a party; only then does the party refresh on a timer. */
  inParty = false;
  private readonly lastFetch = new Map<PartyFeed, Instant>();

  get isVisible(): boolean {
    return this.visible;
  }

  get isLeaderboardVisible(): boolean {
    return this.leaderboardShown;
  }

  /** Shows or hides the panel. Opening it makes friends and party due at once; hiding it stops everything. */
  setVisible(visible: boolean): void {
    if (visible === this.visible) return;
    this.visible = visible;
    if (visible) {
      this.lastFetch.delete("friends");
      this.lastFetch.delete("party");
    } else {
      this.setLeaderboardVisible(false);
    }
  }

  /** Shows or hides the leaderboard view; each opening makes it due once. */
  setLeaderboardVisible(visible: boolean): void {
    if (visible === this.leaderboardShown) return;
    this.leaderboardShown = visible;
    if (visible) this.lastFetch.delete("leaderboard");
  }

  /** Records a fetch attempt, successful or not. */
  didFetch(feed: PartyFeed, now: Instant): void {
    this.lastFetch.set(feed, now);
  }

  /** Makes a feed due right away, e.g. the party after joining or leaving, or friends after adding one. */
  invalidate(feed: PartyFeed): void {
    this.lastFetch.delete(feed);
  }

  /** The feeds to fetch now, in display order. */
  due(now: Instant): PartyFeed[] {
    return PARTY_FEEDS.filter((feed) => {
      const next = this.nextFetch(feed);
      return next !== undefined && next <= now;
    });
  }

  /** When the next feed falls due, or undefined when nothing will until something opens or is invalidated. */
  nextDue(): Instant | undefined {
    const times = PARTY_FEEDS.flatMap((feed) => this.nextFetch(feed) ?? []);
    return times.length === 0 ? undefined : Math.min(...times);
  }

  private nextFetch(feed: PartyFeed): Instant | undefined {
    if (!this.visible) return undefined;
    if (feed === "leaderboard" && !this.leaderboardShown) return undefined;
    const last = this.lastFetch.get(feed);
    if (last === undefined) return Number.NEGATIVE_INFINITY;
    switch (feed) {
      case "friends":
        return last + PartyRefreshPlan.friendsInterval;
      case "party":
        return this.inParty ? last + PartyRefreshPlan.partyInterval : undefined;
      case "leaderboard":
        return undefined;
    }
  }
}
