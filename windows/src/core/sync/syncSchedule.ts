import type { PartyError } from "../party/partyError";
import type { Instant, Seconds } from "../time";

/*
 * When to run a sync round (`runSyncRound`), following the polling table:
 * on launch and on resume, about 30 s after progress changes (debounced,
 * so a burst of changes is one round) and once on quit, never on a timer
 * otherwise. A `409` is retried inside the round. After a failure the next
 * try waits: `Retry-After` on `429`, and 5 s, 10 s, 20 s, ... capped at
 * 5 minutes on `503` or network errors; a failure retrying can't fix waits
 * for the next trigger.
 *
 * The Mac's SyncStore debounces by 5 s; Windows uses the 30 s the handoff
 * asks for. A round always pulls before it pushes, as on the Mac.
 */
export class SyncSchedule {
  /** How long progress changes settle before a round. */
  static readonly debounce: Seconds = 30;
  /** The longest a stream of changes can hold a round back. */
  static readonly maxWait: Seconds = 120;
  static readonly initialBackoff: Seconds = 5;
  static readonly maxBackoff: Seconds = 300;

  private dueAt: Instant | undefined;
  private pendingSince: Instant | undefined;
  private failures = 0;
  private retryAt: Instant | undefined;

  /** Whether progress changed since the last successful round. */
  get hasPendingChanges(): boolean {
    return this.pendingSince !== undefined;
  }

  /** The app launched (and is signed in): sync now. */
  launched(now: Instant): void {
    this.dueAt = now;
  }

  /** The PC woke or the app resumed: sync now. */
  resumed(now: Instant): void {
    this.dueAt = now;
    this.retryAt = undefined;
    this.failures = 0;
  }

  /** Points, unlocks, the look or study days changed: sync once things settle. */
  progressChanged(now: Instant): void {
    this.pendingSince ??= now;
    this.dueAt = Math.min(now + SyncSchedule.debounce, this.pendingSince + SyncSchedule.maxWait);
  }

  /** The app is quitting: whether to run one last round, which it does when there is unsynced progress. */
  quitting(): boolean {
    const pending = this.pendingSince !== undefined;
    this.dueAt = undefined;
    return pending;
  }

  /** A round started at `now`; changes made from here on wait for the next one. */
  willSync(): void {
    this.dueAt = undefined;
    this.pendingSince = undefined;
  }

  /** A round succeeded. */
  didSync(): void {
    this.failures = 0;
    this.retryAt = undefined;
  }

  /** A round failed at `now`: when to try again, or undefined to wait for the next trigger. */
  didFail(error: PartyError, now: Instant): Instant | undefined {
    this.pendingSince ??= now;
    if (!error.isTransient) {
      this.retryAt = undefined;
      return undefined;
    }
    const delay =
      error.kind === "rateLimited"
        ? (error.retryAfter ?? 60)
        : Math.min(SyncSchedule.maxBackoff, SyncSchedule.initialBackoff * 2 ** this.failures);
    if (error.kind !== "rateLimited") this.failures += 1;
    this.retryAt = now + delay;
    return this.retryAt;
  }

  /** When the next round is due, or undefined when nothing waits. A retry wait holds every trigger back. */
  nextDue(): Instant | undefined {
    const candidates = [this.dueAt, this.retryAt].filter((value): value is Instant => value !== undefined);
    if (candidates.length === 0) return undefined;
    const due = Math.min(...candidates);
    return this.retryAt === undefined ? due : Math.max(due, this.retryAt);
  }

  /** Whether a round should start at `now`. */
  isDue(now: Instant): boolean {
    const next = this.nextDue();
    return next !== undefined && next <= now;
  }
}
