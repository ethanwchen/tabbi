import type { JSONObject } from "../persistence/json";
import { documentName, type DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import { isPlannerDayKey, dayKeyStart } from "../planner/plannerDayKey";
import type { Instant } from "../time";
import { addingWeeks, latestReadyWeek, RECAP_READY_HOUR, type RecapWeek } from "./recapWeek";
import { decodeWeeklyRecap, encodeWeeklyRecap, type RecapCheer, type WeeklyRecap } from "./weeklyRecap";

/*
 * Port of RecapArchive: every weekly recap built so far, plus what the user
 * has already been shown, saved as one small versioned JSON document in the
 * edition's storage.
 *
 * The archive decides which weeks still need building and which recap is
 * new to the user, so the app's store only reads the activity log, builds
 * what `weeksToBuild` asks for and saves. Weeks with nothing logged are
 * never kept: a fresh install or a week off shows no card at all.
 */

export interface RecapArchiveFields {
  readonly recaps?: readonly WeeklyRecap[];
  readonly settledWeek?: RecapWeek;
  readonly seenWeek?: RecapWeek;
  readonly notifiedWeek?: RecapWeek;
}

/* The later of two optional weeks. */
function newer(lhs: RecapWeek | undefined, rhs: RecapWeek | undefined): RecapWeek | undefined {
  if (lhs === undefined || rhs === undefined) return lhs ?? rhs;
  return lhs > rhs ? lhs : rhs;
}

export class RecapArchive {
  /** Two years of weeks; the oldest fall off first. */
  static readonly capacity = 104;
  /** How many weeks back a check catches up on, so a few weeks away from the PC still leave their recaps in the list. */
  static readonly catchUpWeeks = 4;

  /** The folder in an edition's storage. */
  static readonly folderName = "Recaps";
  static readonly fileName = "recaps.json";
  /** The document's name in the edition's DocumentStore. */
  static readonly documentName = documentName(RecapArchive.folderName, RecapArchive.fileName);
  /** The archive file format. Version 1 is the first. */
  static readonly schema = new VersionedJSON(1);

  private recapList: WeeklyRecap[];
  /** The newest week built after it was over, so its numbers are final. Weeks up to it are never built again. */
  private settled: RecapWeek | undefined;
  /** The newest week whose recap the user has seen. */
  private seen: RecapWeek | undefined;
  /** The newest week a notification went out for. */
  private notified: RecapWeek | undefined;

  constructor(fields: RecapArchiveFields = {}) {
    const byWeek = new Map<RecapWeek, WeeklyRecap>();
    for (const recap of fields.recaps ?? []) {
      if (!recap.isEmpty && !byWeek.has(recap.week)) byWeek.set(recap.week, recap);
    }
    this.recapList = [...byWeek.values()].sort((a, b) => (a.week > b.week ? -1 : a.week < b.week ? 1 : 0)).slice(0, RecapArchive.capacity);
    this.settled = fields.settledWeek;
    this.seen = fields.seenWeek;
    this.notified = fields.notifiedWeek;
  }

  /** Newest first, one per week, never empty weeks. */
  get recaps(): readonly WeeklyRecap[] {
    return this.recapList;
  }

  get settledWeek(): RecapWeek | undefined {
    return this.settled;
  }

  get seenWeek(): RecapWeek | undefined {
    return this.seen;
  }

  get notifiedWeek(): RecapWeek | undefined {
    return this.notified;
  }

  /**
   * The weeks to build from the activity log at `now`, oldest first: the
   * newest ready week and up to `catchUpWeeks - 1` before it, skipping weeks
   * already settled. The newest ready week stays on the list until a build
   * after its Sunday ends, so activity on Sunday night still makes it in.
   */
  weeksToBuild(now: Instant, timeZone: string, readyHour = RECAP_READY_HOUR): RecapWeek[] {
    const latest = latestReadyWeek(now, timeZone, readyHour);
    const weeks: RecapWeek[] = [];
    for (let back = RecapArchive.catchUpWeeks - 1; back >= 0; back--) {
      const week = addingWeeks(latest, -back);
      if (this.settled === undefined || week > this.settled) weeks.push(week);
    }
    return weeks;
  }

  /**
   * Saves `recap` (replacing an earlier build of its week) unless the week
   * was empty, and settles its week when `now` is past its Sunday. Returns
   * whether anything changed, so the caller saves only then.
   */
  record(recap: WeeklyRecap, now: Instant, timeZone: string): boolean {
    const before = this.copy();
    this.recapList = this.recapList.filter((saved) => saved.week !== recap.week);
    if (!recap.isEmpty) {
      this.recapList.push(recap);
      this.recapList.sort((a, b) => (a.week > b.week ? -1 : a.week < b.week ? 1 : 0));
      this.recapList = this.recapList.slice(0, RecapArchive.capacity);
    }
    const over = dayKeyStart(addingWeeks(recap.week, 1), timeZone);
    if (now >= over && (this.settled === undefined || recap.week > this.settled)) this.settled = recap.week;
    return !this.equals(before);
  }

  /**
   * The newest recap, when the user hasn't seen it yet: the card the open
   * panel shows once. Only the newest counts, so catching up after weeks
   * away shows one card, not a pile, and `skipStaleWeeks` keeps an old week
   * from showing when the latest one had nothing logged.
   */
  get unseen(): WeeklyRecap | undefined {
    const newest = this.recapList[0];
    if (!newest || (this.seen !== undefined && !(newest.week > this.seen))) return undefined;
    return newest;
  }

  /** The newest recap, when no notification has gone out for it and the user hasn't already seen it. */
  get unnotified(): WeeklyRecap | undefined {
    const newest = this.unseen;
    if (!newest || (this.notified !== undefined && !(newest.week > this.notified))) return undefined;
    return newest;
  }

  /** Records that the user has seen `week`'s recap (and so every older one). */
  markSeen(week: RecapWeek): boolean {
    if (this.seen !== undefined && !(week > this.seen)) return false;
    this.seen = week;
    return true;
  }

  /**
   * Marks every week before the newest ready one at `now` as seen without
   * showing it, so after weeks away only the week that just ended can show,
   * never a recap from a month ago. They stay in the list.
   */
  skipStaleWeeks(now: Instant, timeZone: string, readyHour = RECAP_READY_HOUR): boolean {
    return this.markSeen(addingWeeks(latestReadyWeek(now, timeZone, readyHour), -1));
  }

  /**
   * Takes in `other`'s recaps and markers (another PC's, or a copy read back
   * from disk). Markers keep the newer week, so a merge never makes a week
   * the user has seen show again; a week both have keeps this archive's recap.
   */
  merge(other: RecapArchive): boolean {
    const before = this.copy();
    const mine = new Set(this.recapList.map((recap) => recap.week));
    const merged = new RecapArchive({
      recaps: [...this.recapList, ...other.recapList.filter((recap) => !mine.has(recap.week))],
      settledWeek: newer(this.settled, other.settled),
      seenWeek: newer(this.seen, other.seen),
      notifiedWeek: newer(this.notified, other.notified),
    });
    this.recapList = merged.recapList;
    this.settled = merged.settled;
    this.seen = merged.seen;
    this.notified = merged.notified;
    return !this.equals(before);
  }

  /** Records that a notification went out for `week`'s recap. */
  markNotified(week: RecapWeek): boolean {
    if (this.notified !== undefined && !(week > this.notified)) return false;
    this.notified = week;
    return true;
  }

  /** The saved recap for `week`, if that week had anything logged. */
  recap(week: RecapWeek): WeeklyRecap | undefined {
    return this.recapList.find((recap) => recap.week === week);
  }

  /** `recap`'s warm line, measured against the weeks saved before it. */
  cheer(recap: WeeklyRecap): RecapCheer {
    return recap.cheer(this.recapList);
  }

  copy(): RecapArchive {
    return new RecapArchive({ recaps: this.recapList, settledWeek: this.settled, seenWeek: this.seen, notifiedWeek: this.notified });
  }

  equals(other: RecapArchive): boolean {
    return (
      this.settled === other.settled &&
      this.seen === other.seen &&
      this.notified === other.notified &&
      this.recapList.length === other.recapList.length &&
      this.recapList.every((recap, index) => {
        const theirs = other.recapList[index];
        return theirs !== undefined && recap.equals(theirs);
      })
    );
  }

  /* Persistence */

  /** The archive in the Mac's Codable shape (nil markers left out). */
  toJSON(): JSONObject {
    const json: JSONObject = { recaps: this.recapList.map(encodeWeeklyRecap) };
    if (this.settled !== undefined) json.settledWeek = this.settled;
    if (this.seen !== undefined) json.seenWeek = this.seen;
    if (this.notified !== undefined) json.notifiedWeek = this.notified;
    return json;
  }

  /**
   * Reads an archive document. A recap it can't read throws, so the caller
   * doesn't overwrite a file it misread; a marker it can't read is dropped,
   * as the Mac's `try?` does.
   */
  static fromJSON(document: JSONObject): RecapArchive {
    const recaps = document.recaps;
    if (recaps !== undefined && recaps !== null && !Array.isArray(recaps)) throw new TypeError("Invalid recaps");
    const marker = (value: unknown): RecapWeek | undefined => (typeof value === "string" && isPlannerDayKey(value) ? value : undefined);
    return new RecapArchive({
      recaps: (recaps ?? []).map(decodeWeeklyRecap),
      settledWeek: marker(document.settledWeek),
      seenWeek: marker(document.seenWeek),
      notifiedWeek: marker(document.notifiedWeek),
    });
  }

  /** Decodes the archive file's text, running any migration steps first. */
  static decode(text: string): RecapArchive {
    return RecapArchive.schema.decode(text, RecapArchive.fromJSON);
  }

  /** The archive file's text, pretty-printed with sorted keys as the Mac writes it. */
  encode(): string {
    return RecapArchive.schema.encode(this.toJSON(), { pretty: true, sortedKeys: true });
  }

  /** Loads the archive from `store`, or undefined when there is none yet. A corrupt file rejects so the caller can decide not to overwrite it. */
  static async load(store: DocumentStore): Promise<RecapArchive | undefined> {
    const text = await store.read(RecapArchive.documentName);
    return text === undefined ? undefined : RecapArchive.decode(text);
  }

  /** Writes the archive to `store`. */
  async write(store: DocumentStore): Promise<void> {
    await store.write(RecapArchive.documentName, this.encode());
  }
}
