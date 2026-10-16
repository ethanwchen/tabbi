import type { DocumentStore } from "../persistence/documentStore";
import { VersionedJSON } from "../persistence/versionedJson";
import type { Instant } from "../time";
import { occurrenceID, type SeasonalEventOccurrence } from "./seasonalEvent";
import { SeasonalEventCatalog } from "./seasonalEventCatalog";

/*
 * Port of SeasonalEventGreeting: remembers which seasonal event runs the
 * pet has already greeted, so each run gets one quiet moment beside the
 * closed island (a little dance) and never another, even across
 * relaunches. Saved as `Pet/events.json` in the edition's storage, in the
 * Mac's format.
 */
export class SeasonalEventGreeting {
  /** Version 1 is the first format. */
  static readonly schema = new VersionedJSON(1);
  /** Where the app keeps it in the edition's storage. */
  static readonly documentName = "Pet/events.json";

  /** Run ids (`occurrenceID`) already greeted. */
  greetedRuns: Set<string>;

  constructor(greetedRuns: Iterable<string> = []) {
    this.greetedRuns = new Set(greetedRuns);
  }

  /** The runs going on at `now` that have not been greeted yet, the one ending soonest first. */
  due(now: Instant, timeZone: string, catalog: SeasonalEventCatalog = SeasonalEventCatalog.bundled): SeasonalEventOccurrence[] {
    return catalog.active(now, timeZone).filter((run) => !this.greetedRuns.has(occurrenceID(run, timeZone)));
  }

  /**
   * Greets every run due at `now` at once, so two overlapping events share
   * one moment, and returns them. Ids of runs that are over are dropped: a
   * run id carries its year, so it can never come back.
   */
  greet(now: Instant, timeZone: string, catalog: SeasonalEventCatalog = SeasonalEventCatalog.bundled): SeasonalEventOccurrence[] {
    const due = this.due(now, timeZone, catalog);
    const active = new Set(catalog.active(now, timeZone).map((run) => occurrenceID(run, timeZone)));
    const kept = [...this.greetedRuns].filter((id) => active.has(id));
    this.greetedRuns = new Set([...kept, ...due.map((run) => occurrenceID(run, timeZone))]);
    return due;
  }

  /** When a greeting can next become due: the start of the next run, so Tabbi left open over an event's first midnight still greets it. */
  static nextCheck(now: Instant, timeZone: string, catalog: SeasonalEventCatalog = SeasonalEventCatalog.bundled): Instant | undefined {
    return catalog.next(now, timeZone)?.start;
  }

  /** The document's text, with the runs sorted as the Mac writes them. */
  encode(): string {
    return SeasonalEventGreeting.schema.encode({ greetedRuns: [...this.greetedRuns].sort() });
  }

  /** Reads leniently: a damaged list greets again rather than fail. Throws only when `text` is not a JSON object. */
  static decode(text: string): SeasonalEventGreeting {
    return SeasonalEventGreeting.schema.decode(text, (document) => {
      const list = document.greetedRuns;
      const runs = Array.isArray(list) && list.every((id) => typeof id === "string") ? (list as string[]) : [];
      return new SeasonalEventGreeting(runs);
    });
  }

  static async load(store: DocumentStore, name: string = SeasonalEventGreeting.documentName): Promise<SeasonalEventGreeting | undefined> {
    const text = await store.read(name);
    return text === undefined ? undefined : SeasonalEventGreeting.decode(text);
  }

  async write(store: DocumentStore, name: string = SeasonalEventGreeting.documentName): Promise<void> {
    await store.write(name, this.encode());
  }
}
