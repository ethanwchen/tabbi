import type { Seconds } from "../time";
import type { PartyError } from "./partyError";
import type { PartyHeartbeatReply } from "./partyModels";

/*
 * Port of PartyHeartbeatSchedule: when to send the next request after a
 * reply or a failure, following the polling guidance: the server's
 * `heartbeatSeconds` after a success, `Retry-After` on `429`, and
 * exponential backoff (5 s, 10 s, 20 s, ... capped at 5 minutes) on outages
 * and network errors. It never retries faster, and stops after `offline`.
 */
export class PartyHeartbeatSchedule {
  static readonly initialBackoff: Seconds = 5;
  static readonly maxBackoff: Seconds = 300;
  /** Used when a reply carries no interval but is not `offline`. */
  static readonly fallbackInterval: Seconds = 120;

  private failureCount = 0;

  /** Consecutive transient failures since the last success. */
  get failures(): number {
    return this.failureCount;
  }

  /** After a heartbeat reply: the server's interval, or undefined to stop (the reply to `offline`). */
  delayAfterSuccess(reply: PartyHeartbeatReply): Seconds | undefined {
    this.failureCount = 0;
    if (reply.presence.status === "offline") return undefined;
    return Math.max(1, reply.nextHeartbeat ?? PartyHeartbeatSchedule.fallbackInterval);
  }

  /**
   * After a failed request: how long to wait before retrying, or undefined
   * when retrying the same request cannot help (e.g. `unauthorized`).
   */
  delayAfterFailure(error: PartyError): Seconds | undefined {
    if (!error.isTransient) return undefined;
    if (error.kind === "rateLimited") return error.retryAfter ?? 60;
    const delay = Math.min(PartyHeartbeatSchedule.maxBackoff, PartyHeartbeatSchedule.initialBackoff * 2 ** this.failureCount);
    this.failureCount += 1;
    return delay;
  }

  /** Forgets past failures, e.g. after the network comes back. */
  reset(): void {
    this.failureCount = 0;
  }
}
