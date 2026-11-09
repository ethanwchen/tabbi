import { formatISODate, parseISODate } from "../activity/isoDate";
import { isJSONObject, stringifyJSON, type JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import { monthKeyFromRaw, type MonthKey } from "./monthlyQuests";
import { PROGRESS_TRACKS, badgeFromID, badgeID, type ProgressTrack } from "./progressTrack";

/*
 * Port of ProgressionSave.swift: what the Goals section keeps beside the
 * pet's save as `Pet/progression.json`: each track's best count so far, the
 * badge tiers reached and when, the months whose quests were all done, and
 * which tiers were already seen. Never synced; reading is forgiving.
 */

export interface ProgressionSaveFields {
  readonly best?: ReadonlyMap<ProgressTrack, number>;
  /** Badge id to when it was first reached. */
  readonly reached?: ReadonlyMap<string, Instant>;
  readonly completedMonths?: Iterable<MonthKey>;
  /** Badge ids. */
  readonly seen?: Iterable<string>;
}

export class ProgressionSave {
  /** Version 1 is the first; a file without a version reads as the same fields. */
  static readonly schema = new VersionedJSON(1);

  readonly best: Map<ProgressTrack, number>;
  readonly reached: Map<string, Instant>;
  readonly completedMonths: Set<MonthKey>;
  readonly seen: Set<string>;

  constructor(fields: ProgressionSaveFields = {}) {
    this.best = new Map([...(fields.best ?? new Map<ProgressTrack, number>())].filter(([, value]) => value > 0));
    this.reached = new Map(fields.reached ?? []);
    this.completedMonths = new Set(fields.completedMonths ?? []);
    this.seen = new Set([...(fields.seen ?? [])].filter((id) => this.reached.has(id)));
  }

  copy(): ProgressionSave {
    return new ProgressionSave({ best: this.best, reached: this.reached, completedMonths: this.completedMonths, seen: this.seen });
  }

  equals(other: ProgressionSave): boolean {
    return this.encoded() === other.encoded();
  }

  /** Reads a stored file; throws when it is not a JSON object. */
  static decode(text: string): ProgressionSave {
    return ProgressionSave.schema.decode(text, readSave);
  }

  /** The file as the Mac writes it: pretty printed, sorted keys, ISO 8601 dates, with its version. */
  encoded(): string {
    const best: JSONObject = {};
    for (const [track, value] of this.best) best[track] = value;
    const reached: JSONObject = {};
    for (const [id, instant] of this.reached) reached[id] = formatISODate(instant);
    return stringifyJSON(
      {
        best,
        reached,
        completedMonths: [...this.completedMonths].sort(),
        seen: [...this.seen].sort(),
        [VersionedJSON.versionKey]: ProgressionSave.schema.current,
      },
      { pretty: true, sortedKeys: true },
    );
  }
}

/* Each field reads on its own and falls back to empty, like the Mac's `try?`. */
function readSave(document: JSONObject): ProgressionSave {
  const best = new Map<ProgressTrack, number>();
  const rawBest = document.best;
  if (isJSONObject(rawBest) && Object.values(rawBest).every((value) => typeof value === "number" && Number.isInteger(value))) {
    for (const [key, value] of Object.entries(rawBest)) {
      const track = PROGRESS_TRACKS.find((candidate) => candidate === key);
      if (track && typeof value === "number") best.set(track, Math.max(best.get(track) ?? value, value));
    }
  }
  const reached = new Map<string, Instant>();
  const rawReached = document.reached;
  if (isJSONObject(rawReached)) {
    const dates = Object.entries(rawReached).map(([key, value]) => [key, typeof value === "string" ? parseISODate(value) : undefined] as const);
    if (dates.every(([, date]) => date !== undefined)) {
      for (const [key, date] of dates) {
        const badge = badgeFromID(key);
        if (!badge || date === undefined) continue;
        const id = badgeID(badge);
        reached.set(id, Math.min(reached.get(id) ?? date, date));
      }
    }
  }
  const months = stringArray(document.completedMonths).flatMap((raw) => monthKeyFromRaw(raw) ?? []);
  const seen = stringArray(document.seen).flatMap((raw) => {
    const badge = badgeFromID(raw);
    return badge ? [badgeID(badge)] : [];
  });
  return new ProgressionSave({ best, reached, completedMonths: months, seen });
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string") ? (value as string[]) : [];
}
