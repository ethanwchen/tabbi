import { PetProfile } from "./petProfile";
import { PetPointsLedger } from "./petUnlocks";

/*
 * Port of PetSave: the pet's whole persisted state in one versioned JSON
 * document. The profile and the ledger travel together, so a profile is
 * always checked against the items the user actually owns. File I/O is the
 * host's; this reads and writes the JSON value.
 */
export class PetSave {
  /** Bump when the format changes in a way old builds cannot read. */
  static readonly currentVersion = 1;

  version: number;
  ledger: PetPointsLedger;
  private profileValue: PetProfile;
  /** The shared focus timer's completed count already paid out in points, undefined until the pet first sees a timer. */
  creditedFocusCount: number | undefined;
  /** The module whose clock `creditedFocusCount` counts. */
  creditedFocusSource: string | undefined;

  constructor(profile: PetProfile, ledger: PetPointsLedger = new PetPointsLedger()) {
    this.version = PetSave.currentVersion;
    this.ledger = ledger;
    this.profileValue = profile.restricted(ledger);
  }

  get profile(): PetProfile {
    return this.profileValue;
  }

  /** Replaces the profile as is; callers that change what is worn keep ownership in mind (the Closet does). */
  set profile(profile: PetProfile) {
    this.profileValue = profile;
  }

  copy(): PetSave {
    const copy = new PetSave(this.profileValue.copy(), this.ledger.copy());
    copy.profileValue = this.profileValue.copy();
    copy.version = this.version;
    copy.creditedFocusCount = this.creditedFocusCount;
    copy.creditedFocusSource = this.creditedFocusSource;
    return copy;
  }

  /** The JSON value the Mac writes (keys sorted when serialized by the host). */
  toJSON(): Record<string, unknown> {
    return {
      version: this.version,
      profile: this.profileValue.toJSON(),
      ledger: this.ledger.toJSON(),
      ...(this.creditedFocusCount === undefined ? {} : { creditedFocusCount: this.creditedFocusCount }),
      ...(this.creditedFocusSource === undefined ? {} : { creditedFocusSource: this.creditedFocusSource }),
    };
  }

  /** Pretty-printed with sorted keys, like the Mac's encoder. */
  encoded(): string {
    return JSON.stringify(sortKeys(this.toJSON()), null, 2);
  }

  /**
   * Decodes a save and re-applies the ownership rule, so a hand-edited file
   * cannot dress the pet in items it never bought. Throws on a broken file,
   * so the caller can decide not to overwrite it.
   */
  static decode(raw: unknown): PetSave {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("A pet save must be an object");
    const object = raw as Record<string, unknown>;
    if (typeof object.version !== "number" || !Number.isInteger(object.version)) throw new Error("A pet save needs a version");
    if (typeof object.ledger !== "object" || object.ledger === null) throw new Error("A pet save needs a ledger");
    const save = new PetSave(PetProfile.fromJSON(object.profile), PetPointsLedger.fromJSON(object.ledger));
    save.version = object.version;
    if (typeof object.creditedFocusCount === "number" && Number.isInteger(object.creditedFocusCount)) {
      save.creditedFocusCount = object.creditedFocusCount;
    }
    if (typeof object.creditedFocusSource === "string") save.creditedFocusSource = object.creditedFocusSource;
    return save;
  }
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortKeys((value as Record<string, unknown>)[key])]),
  );
}
