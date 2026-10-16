import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../activity/activityRecord";
import type { ModuleID } from "../modules/moduleId";
import { MINIMUM_LOGGED_DURATION } from "../studyMethods/studyPhaseRecord";
import type { Instant, Seconds } from "../time";

/*
 * Port of PartySessionCompletion and PartySessionTracker: each stay in a
 * Party shared session, for points, the activity log and the celebration.
 */

/**
 * The shared session the user is in, as `PartyState.session` reports it.
 * The Mac hands its `ProvidedPartySession` around; the module wiring maps
 * this onto the providers' type, which lives in core/providers.
 */
export interface PartySharedSession {
  /** The study method id the host picked, e.g. `pomodoro`. */
  readonly method: string;
  readonly startedAt: Instant;
  readonly endsAt: Instant;
  /** Friends studying along right now (online members other than me). */
  readonly friendCount: number;
  /** Who started it; undefined when I host. */
  readonly hostName: string | undefined;
}

export function sameSharedSession(a: PartySharedSession | undefined, b: PartySharedSession | undefined): boolean {
  if (a === undefined || b === undefined) return a === b;
  return a.method === b.method && a.startedAt === b.startedAt && a.endsAt === b.endsAt && a.friendCount === b.friendCount && a.hostName === b.hostName;
}

/** The activity metadata key for how many friends studied along. */
export const PARTY_FRIENDS_METADATA_KEY = "friends";

/**
 * One stay in a shared session: either it ran to the session's end with
 * the user in it, or it was cut short and pays the minutes studied.
 */
export class PartySessionCompletion {
  readonly method: string;
  /** When the user's stay began: the session's start, or later when they joined late. */
  readonly joinedAt: Instant;
  readonly endedAt: Instant;
  /** The most friends who studied along at once. */
  readonly friendCount: number;
  /** Who started it; undefined when the user did. */
  readonly hostName: string | undefined;
  /** Whether the session ran to its end with the user in it. */
  readonly finished: boolean;

  constructor(init: { method: string; joinedAt: Instant; endedAt: Instant; friendCount: number; hostName?: string; finished?: boolean }) {
    this.method = init.method;
    this.joinedAt = init.joinedAt;
    this.endedAt = Math.max(init.endedAt, init.joinedAt);
    this.friendCount = Math.max(init.friendCount, 0);
    this.hostName = init.hostName;
    this.finished = init.finished ?? true;
  }

  /** Whole minutes the user stayed for. */
  get minutes(): number {
    return Math.trunc((this.endedAt - this.joinedAt) / 60);
  }

  /**
   * The activity log entry: a focus stretch from Party, so streaks and
   * insights count shared study like any other. A stay cut short is logged
   * as skipped, so it adds minutes but not a finished session.
   */
  activityRecord(source: ModuleID): ActivityRecord | undefined {
    const length: Seconds = this.endedAt - this.joinedAt;
    if (length < MINIMUM_LOGGED_DURATION) return undefined;
    return makeActivityRecord({
      source,
      kind: ACTIVITY_KINDS.focusCompleted,
      start: this.joinedAt,
      end: this.endedAt,
      quantity: length / 60,
      unit: ACTIVITY_UNITS.minutes,
      metadata: {
        [ACTIVITY_METADATA.method]: this.method,
        [ACTIVITY_METADATA.outcome]: this.finished ? "completed" : "skipped",
        [PARTY_FRIENDS_METADATA_KEY]: String(this.friendCount),
      },
    });
  }
}

/**
 * Watches the shared session the user is in and reports each stay once it
 * ends. Every member's app runs its own tracker, so everyone is paid
 * alike. A user who joins late or rejoins is credited from then on.
 */
export class PartySessionTracker {
  /** How early the session may drop off and still count as finished, for timers that fire a moment early. */
  static readonly endTolerance: Seconds = 2;

  private stay: { session: PartySharedSession; joinedAt: Instant; friendCount: number } | undefined;

  /**
   * Observes the session the user is in at `now` (undefined when none) and
   * returns the stay in the one being watched when it just ended or the
   * user left it.
   */
  observe(session: PartySharedSession | undefined, now: Instant): PartySessionCompletion | undefined {
    const stay = this.stay;
    if (session !== undefined && stay !== undefined && stay.session.startedAt === session.startedAt) {
      this.stay = { session, joinedAt: stay.joinedAt, friendCount: Math.max(stay.friendCount, session.friendCount) };
      return undefined;
    }
    this.stay = session === undefined ? undefined : { session, joinedAt: Math.max(now, session.startedAt), friendCount: session.friendCount };
    if (stay === undefined) return undefined;
    const finished = stay.session.endsAt - now <= PartySessionTracker.endTolerance;
    return new PartySessionCompletion({
      method: stay.session.method,
      joinedAt: stay.joinedAt,
      endedAt: finished ? stay.session.endsAt : now,
      friendCount: stay.friendCount,
      ...(stay.session.hostName === undefined ? {} : { hostName: stay.session.hostName }),
      finished,
    });
  }
}
