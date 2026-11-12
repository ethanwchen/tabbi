import { ACTIVITY_KINDS, type ActivityRecord } from "../activity/activityRecord";
import type { DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import { CREW_LIMITS } from "./crewCatalog";
import type { CrewSession } from "./crewModels";

/*
 * Port of CrewSessionQueue and CrewSessionQueueFile: the finished focus
 * sessions waiting to be reported to the crew board.
 *
 * The server never trusts a total: it credits sessions, each a start, an
 * end and the minutes focused in it, and refuses one that overlaps another
 * it already has. A shared Party session and the user's own timer can log
 * the same stretch, so sessions are merged here first and one stretch of
 * time is sent once. The queue survives a quit (one small versioned JSON in
 * the Party folder), is sent in batches, and forgets a session once the
 * server answered for it.
 */

/** Sessions older than this are dropped unsent: their week has frozen. */
export const CREW_SESSION_MAX_AGE = 8 * 86_400;

/** The most minutes a stretch can hold: its length rounded up, and never more than the per-session cap. */
function maxMinutes(start: Instant, end: Instant): number {
  return Math.min(Math.ceil((end - start) / 60), CREW_LIMITS.maxSessionMinutes);
}

/** The session a finished focus record stands for, or undefined for anything else (a break, cards, under a minute). */
export function crewSessionFor(record: ActivityRecord): CrewSession | undefined {
  if (record.kind !== ACTIVITY_KINDS.focusCompleted || record.quantity === undefined || !(record.end > record.start)) return undefined;
  const minutes = Math.min(Math.floor(record.quantity), maxMinutes(record.start, record.end));
  if (minutes < 1) return undefined;
  return { start: record.start, end: record.end, minutes };
}

export class CrewSessionQueue {
  /** Sessions not yet answered for, oldest first, never overlapping. */
  private items: CrewSession[];

  constructor(pending: readonly CrewSession[] = []) {
    this.items = [...pending];
  }

  get pending(): readonly CrewSession[] {
    return this.items;
  }

  /** Adds a session, merged with any pending one it overlaps or touches. */
  add(session: CrewSession): void {
    let merged = session;
    const rest: CrewSession[] = [];
    for (const other of this.items) {
      if (other.start <= merged.end && merged.start <= other.end) {
        const start = Math.min(other.start, merged.start);
        const end = Math.max(other.end, merged.end);
        /* Overlapping logs count the shared time once: at most the merged stretch's length, and at least either one alone. */
        const minutes = Math.min(other.minutes + merged.minutes, maxMinutes(start, end));
        merged = {
          start,
          end,
          minutes: Math.max(minutes, Math.max(other.minutes, merged.minutes)),
        };
      } else {
        rest.push(other);
      }
    }
    rest.push(merged);
    this.items = rest.sort((a, b) => a.start - b.start);
  }

  /** Drops sessions too old to count anywhere. */
  prune(now: Instant): void {
    this.items = this.items.filter((session) => now - session.end <= CREW_SESSION_MAX_AGE);
  }

  /** The next batch to send: the oldest sessions, at most a request's worth. */
  get nextBatch(): readonly CrewSession[] {
    return this.items.slice(0, CREW_LIMITS.maxSessionsPerReport);
  }

  /** Forgets the sessions the server answered for. */
  didSend(batch: readonly CrewSession[]): void {
    this.items = this.items.filter((session) => !batch.some((sent) => sent.start === session.start && sent.end === session.end && sent.minutes === session.minutes));
  }
}

/* MARK: The file */

export const CREW_SESSIONS_FILE = "crew-sessions.json";
const SCHEMA = new VersionedJSON(1);

/** The queue as the Mac writes it: `{"pending":[{"end","minutes","start"}],"schemaVersion":1}` with unix seconds. */
export function encodeCrewSessionQueue(queue: CrewSessionQueue): string {
  const pending = queue.pending.map((session) => ({
    end: session.end,
    minutes: session.minutes,
    start: session.start,
  }));
  return JSON.stringify({
    pending,
    [VersionedJSON.versionKey]: SCHEMA.current,
  });
}

/** Reads a saved queue; a missing or broken file starts over. */
export function decodeCrewSessionQueue(text: string | undefined): CrewSessionQueue {
  if (text === undefined) return new CrewSessionQueue();
  try {
    return SCHEMA.decode(text, (document) => {
      const pending = Array.isArray(document.pending) ? document.pending : [];
      const sessions: CrewSession[] = [];
      for (const item of pending) {
        if (typeof item !== "object" || item === null || Array.isArray(item)) continue;
        const { start, end, minutes } = item as Record<string, unknown>;
        if (typeof start === "number" && typeof end === "number" && typeof minutes === "number") sessions.push({ start, end, minutes });
      }
      return new CrewSessionQueue(sessions);
    });
  } catch {
    return new CrewSessionQueue();
  }
}

export async function loadCrewSessionQueue(documents: DocumentStore): Promise<CrewSessionQueue> {
  try {
    return decodeCrewSessionQueue(await documents.read(CREW_SESSIONS_FILE));
  } catch {
    return new CrewSessionQueue();
  }
}

export async function saveCrewSessionQueue(documents: DocumentStore, queue: CrewSessionQueue): Promise<void> {
  await documents.write(CREW_SESSIONS_FILE, encodeCrewSessionQueue(queue));
}
