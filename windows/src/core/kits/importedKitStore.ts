import type { ModuleCatalog } from "../modules/moduleCatalog";
import type { DocumentStore } from "../persistence/documentStore";
import { authorKitID, importedKitID } from "./kitLibrary";
import type { KitManifest } from "./kitManifest";
import { decodeKit, missingKitRequirements, type KitError } from "./kitValidation";

/**
 * Port of ImportedKitStore: kits the user imported, kept as one
 * `<author id>.json` document each in the edition's `Kits` folder, byte for
 * byte, so the file stays human-editable and keeps fields a newer Tabbi
 * understands. In the app an imported kit goes by `importedKitID` of its
 * author's id (`imported.deep-work`), so a kit a later Tabbi ships under
 * the same author id never shadows the user's import. A file that stops
 * loading (edited by hand into invalid JSON) is skipped, never fatal.
 */
export const KITS_FOLDER = "Kits";

/** Port of KitImportCandidate: a kit file that passed validation but isn't saved yet. */
export interface KitImportCandidate {
  /** The kit as the app knows it, with its imported id. */
  readonly kit: KitManifest;
  /** The file's text, saved as it is. */
  readonly text: string;
  /** The name of the file it came from, for messages. */
  readonly fileName: string;
  /** The earlier import with the same id that saving this one replaces, so the user is asked first. */
  readonly replaces?: KitManifest;
  /** True when a file is saved under the kit's id already, even one that no longer loads. */
  readonly overwritesFile: boolean;
}

/** "Deep Work 1.2 to 1.3" when both files carry a version, else undefined. */
export function kitVersionChange(candidate: KitImportCandidate): string | undefined {
  const old = candidate.replaces?.version;
  const next = candidate.kit.version;
  if (old === undefined || next === undefined || old === next) return undefined;
  return `${candidate.kit.name} ${old} to ${next}`;
}

/** The kit as the app knows it once imported: with its imported id. */
export function importedCopy(kit: KitManifest): KitManifest {
  return { ...kit, id: importedKitID(kit.id) };
}

/** Reading a kit file: the candidate to review, or why the file can't be used. */
export type KitInspection = { readonly ok: true; readonly candidate: KitImportCandidate } | { readonly ok: false; readonly error: KitError };

export class ImportedKitStore {
  constructor(
    private readonly store: DocumentStore,
    private readonly folder: string = KITS_FOLDER,
  ) {}

  /** Every imported kit that still loads, by name. */
  async load(): Promise<KitManifest[]> {
    let names: string[];
    try {
      names = await this.store.list(this.folder);
    } catch {
      return [];
    }
    const kits: KitManifest[] = [];
    for (const name of names.filter((file) => file.endsWith(".json"))) {
      const text = await this.store.read(`${this.folder}/${name}`).catch(() => undefined);
      if (text === undefined) continue;
      const result = decodeKit(text);
      if (result.ok) kits.push(importedCopy(result.kit));
    }
    return kits.sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" }));
  }

  /**
   * Reads and validates a kit file's text without saving it, so the user
   * can see what it changes (and which earlier import it replaces) before
   * `install` keeps it. Ids in `reserved` (the bundled kits) are refused so
   * an import can never shadow a kit that ships with the app, and so is a
   * kit that `requires` a module `catalog` doesn't have.
   */
  async inspect(text: string, fileName: string, catalog: ModuleCatalog, reserved: ReadonlySet<string>): Promise<KitInspection> {
    const result = decodeKit(text);
    if (!result.ok) return result;
    const kit = result.kit;
    if (reserved.has(kit.id)) return { ok: false, error: { kind: "reservedID", id: kit.id } };
    const missing = missingKitRequirements(kit, catalog);
    if (missing.length > 0) return { ok: false, error: { kind: "missingRequiredModules", ids: missing } };
    const id = importedKitID(kit.id);
    const saved = await this.savedText(id);
    const earlier = saved === undefined ? undefined : decodeKit(saved);
    const candidate: { -readonly [Key in keyof KitImportCandidate]: KitImportCandidate[Key] } = {
      kit: importedCopy(kit),
      text,
      fileName,
      overwritesFile: saved !== undefined,
    };
    if (earlier?.ok) candidate.replaces = importedCopy(earlier.kit);
    return { ok: true, candidate };
  }

  /** Copies an inspected kit into the store, replacing an earlier import with the same id. */
  install(candidate: KitImportCandidate): Promise<void> {
    return this.restore(candidate.text, candidate.kit.id);
  }

  /** The stored file of the imported kit `id`, byte for byte, or undefined when there is none. Undo keeps it to put the file back. */
  async savedText(id: string): Promise<string | undefined> {
    try {
      return await this.store.read(this.name(id));
    } catch {
      return undefined;
    }
  }

  /** Puts back the file `savedText` returned: writes `text` as the kit imported as `id`, or removes that kit when `text` is undefined. */
  restore(text: string | undefined, id: string): Promise<void> {
    return text === undefined ? this.remove(id) : this.store.write(this.name(id), text);
  }

  /** Deletes an imported kit. Removing one that isn't there is not an error. */
  remove(id: string): Promise<void> {
    return this.store.remove(this.name(id));
  }

  /** The document of the imported kit `id`, named after its author's id (a validated slug, safe as a file name). */
  private name(id: string): string {
    return `${this.folder}/${authorKitID(id)}.json`;
  }
}
