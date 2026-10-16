import type { DocumentStore } from "../persistence/documentStore";
import type { JSONObject } from "../persistence/json";
import { VersionedJSON } from "../persistence/versionedJson";
import type { ProvidedFocus } from "../providers/providedFocus";
import type { Instant, Seconds } from "../time";
import { CatWisdomSchedule } from "../motivation/catWisdom";
import { CoachAppList, type CoachAppCategory } from "./coachAppList";
import { asObject, optionalMacDate, PetCoach, toMacDate, type PetCoachInput, type PetCoachStudyState } from "./petCoach";

/*
 * Port of PetCoachSession.swift: how the coach reads the shared focus
 * clock, and the coach's save.
 */

/**
 * Reads the shared focus clock (`ProviderSnapshot.focus`) the way the coach
 * sees it: only a running focus phase counts as studying, so the pet stays
 * quiet on breaks, while paused, and with no timer at all.
 */
export function coachStudyState(timer: ProvidedFocus | undefined): PetCoachStudyState {
  if (timer === undefined) return "notStudying";
  if (timer.isPaused) return "paused";
  if (!timer.isRunning) return "notStudying";
  return timer.phase === "focus" ? "focusing" : "onBreak";
}

/** Focus phases at least this long count as deep focus, like a clock the user marked deep. */
export const DEEP_FOCUS_PHASE_LENGTH: Seconds = 45 * 60;

/** One reading built from the shared focus clock, so the app only supplies what the host reports (idle seconds, frontmost app). */
export function coachInput(now: Instant, idleSeconds: Seconds, frontmost: CoachAppCategory, timer: ProvidedFocus | undefined): PetCoachInput {
  return {
    now,
    idleSeconds,
    frontmost,
    study: coachStudyState(timer),
    deepFocus: timer?.isDeep === true || (timer?.focusLength ?? 0) >= DEEP_FOCUS_PHASE_LENGTH,
  };
}

/**
 * The coach's persisted state: its cooldowns and snooze (so a relaunch
 * can't reset the rate limits), the user's focus and distracting app lists,
 * the Settings switch, the Cat wisdom rotation and the last completion.
 * One JSON document next to the pet's save, in the Mac's shape (its own
 * `version` key) plus the `schemaVersion` every Windows document carries;
 * the Mac ignores the extra key.
 */
export class PetCoachSave {
  /** The Mac's format version: bump when the format changes in a way old builds cannot read. */
  static readonly currentVersion = 1;
  static readonly schema = new VersionedJSON(1);

  version = PetCoachSave.currentVersion;

  constructor(
    public coach: PetCoach = new PetCoach(),
    public apps: CoachAppList = new CoachAppList(),
    /** The user's Settings switch. Off means the app doesn't sample at all, so the pet never walks out. */
    public nudgesOn = true,
    /** The Cat wisdom rotation and caps, so a restart cannot repeat a line or show a second one the same day. */
    public wisdom: CatWisdomSchedule = new CatWisdomSchedule(),
    /** When the last focus session ran to its end, for the comeback and first-of-the-day lines. */
    public lastCompletion: Instant | undefined = undefined,
  ) {}

  toJSON(): JSONObject {
    const json: JSONObject = {
      version: this.version,
      coach: this.coach.toJSON(),
      apps: this.apps.toJSON(),
      nudgesOn: this.nudgesOn,
      wisdom: this.wisdom.toJSON(),
    };
    if (this.lastCompletion !== undefined) json.lastCompletion = toMacDate(this.lastCompletion);
    return json;
  }

  /** Saves written before the switch existed read as nudges on, and those from before Cat wisdom as a fresh rotation. */
  static fromJSON(json: unknown): PetCoachSave {
    const object = asObject(json, "coach save");
    if (!Number.isInteger(object.version)) throw new TypeError("Invalid version");
    const nudgesOn = object.nudgesOn;
    if (nudgesOn !== undefined && nudgesOn !== null && typeof nudgesOn !== "boolean") throw new TypeError("Invalid nudgesOn");
    const save = new PetCoachSave(
      PetCoach.fromJSON(object.coach),
      CoachAppList.fromJSON(object.apps),
      nudgesOn !== false,
      object.wisdom === undefined || object.wisdom === null ? new CatWisdomSchedule() : CatWisdomSchedule.fromJSON(object.wisdom),
      optionalMacDate(object.lastCompletion, "lastCompletion"),
    );
    save.version = object.version as number;
    return save;
  }

  /** The save as its document text. */
  encoded(): string {
    return PetCoachSave.schema.encode(this.toJSON(), { pretty: true, sortedKeys: true });
  }

  /** Reads a document; throws on a corrupt one, so the caller can decide not to overwrite it. */
  static decode(text: string): PetCoachSave {
    return PetCoachSave.schema.decode(text, (document) => PetCoachSave.fromJSON(document));
  }

  /** Loads the save named `name`, or undefined when there is none yet. A corrupt one throws so the caller can decide not to overwrite it. */
  static async load(store: DocumentStore, name: string): Promise<PetCoachSave | undefined> {
    const text = await store.read(name);
    return text === undefined ? undefined : PetCoachSave.decode(text);
  }

  /** Writes the save atomically. */
  async write(store: DocumentStore, name: string): Promise<void> {
    await store.write(name, this.encoded());
  }
}

