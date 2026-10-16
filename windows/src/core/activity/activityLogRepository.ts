import { documentName, type DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import { activityDay, decodeActivityRecord, encodeActivityRecord, type ActivityRecord } from "./activityRecord";
import { isPlannerDayKey as isDayKey, type PlannerDayKey as DayKey } from "../planner/plannerDayKey";

/**
 * Port of ActivityLogRepository: the activity log as one JSON document per
 * local day (`yyyy-MM-dd.json`) in the edition's `Activity` folder.
 *
 * Day files keep reads cheap (today, or the last week, never the whole
 * history) and stay readable and easy to delete by hand. A day file that
 * can't be read is never overwritten, so a bad file costs new records for
 * that day rather than the old ones. Days are local to the IANA zone the
 * repository is given.
 */
export class ActivityLogRepository {
  /** The folder in an edition's storage. */
  static readonly folderName = "Activity";

  /** The day file format: `{"records": [...], "schemaVersion": 1}`. */
  static readonly schema = new VersionedJSON(1);

  constructor(
    private readonly store: DocumentStore,
    private readonly timeZone: string,
    readonly folder: string = ActivityLogRepository.folderName,
  ) {}

  documentName(day: DayKey): string {
    return documentName(this.folder, `${day}.json`);
  }

  /**
   * The records of `day`, oldest first; empty when there is no file.
   * Rejects when the file can't be read, so a caller never mistakes it for
   * an empty day.
   */
  async records(day: DayKey): Promise<ActivityRecord[]> {
    const text = await this.store.read(this.documentName(day));
    if (text === undefined) return [];
    return ActivityLogRepository.schema.decode(text, (document) => {
      const records = document.records;
      if (!Array.isArray(records)) throw new TypeError("A day file needs a records list");
      return records.map(decodeActivityRecord);
    });
  }

  /** The records of every saved day from `first` through `last` that can be read. */
  async recordsBetween(first: DayKey, last: DayKey): Promise<ActivityRecord[]> {
    const days = (await this.savedDays()).filter((day) => day >= first && day <= last);
    const result: ActivityRecord[] = [];
    for (const day of days) {
      try {
        result.push(...(await this.records(day)));
      } catch {
        /* An unreadable day is skipped, as on the Mac. */
      }
    }
    return result;
  }

  /**
   * Adds records to their days' files, skipping any whose id is already
   * there. Rejects on the first day it can't read or write; earlier days are kept.
   */
  async append(newRecords: readonly ActivityRecord[]): Promise<void> {
    const byDay = new Map<DayKey, ActivityRecord[]>();
    for (const record of newRecords) {
      const day = activityDay(record, this.timeZone);
      byDay.set(day, [...(byDay.get(day) ?? []), record]);
    }
    for (const day of [...byDay.keys()].sort()) {
      const stored = await this.records(day);
      const known = new Set(stored.map((record) => record.id));
      const added: ActivityRecord[] = [];
      for (const record of byDay.get(day) ?? []) {
        if (known.has(record.id)) continue;
        added.push(record);
      }
      if (added.length === 0) continue;
      /* Stable, like Swift's sort, so records that end together keep their order. */
      const sorted = [...stored, ...added].sort((a, b) => a.end - b.end);
      const text = ActivityLogRepository.schema.encode(
        { records: sorted.map(encodeActivityRecord) },
        { pretty: true, sortedKeys: true },
      );
      await this.store.write(this.documentName(day), text);
    }
  }

  /** Every day with a file, oldest first. Unrelated files are ignored. */
  async savedDays(): Promise<DayKey[]> {
    let names: string[];
    try {
      names = await this.store.list(this.folder);
    } catch {
      return [];
    }
    return names
      .filter((name) => name.endsWith(".json"))
      .map((name) => name.slice(0, -5))
      .filter(isDayKey)
      .sort();
  }
}
