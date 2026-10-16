import { decodeKit } from "./kitValidation";
import type { KitManifest } from "./kitManifest";

/** The kit used when the user (or edition) hasn't picked one. */
export const DEFAULT_KIT_ID = "essentials";

/**
 * Bundled kits that no longer ship, and the kit that replaced each. Settings
 * saved on one move to its replacement. Never reuse a retired id.
 */
export const RETIRED_KIT_IDS: Readonly<Record<string, string>> = {
  productivity: "essentials",
  student: "essentials",
};

/** Begins every imported kit's id in the app. A kit's own id is a slug with no dot, so no bundled kit can have it. */
export const IMPORTED_ID_PREFIX = "imported.";

/** The id the app gives a kit imported with `authorID`. */
export function importedKitID(authorID: string): string {
  return isImportedKitID(authorID) ? authorID : IMPORTED_ID_PREFIX + authorID;
}

/** True for an id from `importedKitID`. */
export function isImportedKitID(id: string): boolean {
  return id.startsWith(IMPORTED_ID_PREFIX);
}

/** The id the kit's author wrote, for an id from `importedKitID`. */
export function authorKitID(id: string): string {
  return isImportedKitID(id) ? id.slice(IMPORTED_ID_PREFIX.length) : id;
}

/** A bundled kit file: its name without `.json`, and its text. */
export interface KitFile {
  readonly name: string;
  readonly text: string;
}

/**
 * Port of KitLibrary: the kits a user can choose from, the bundled ones plus
 * any imported. A kit with a duplicate id is dropped; the first one wins.
 */
export class KitLibrary {
  private list: KitManifest[];

  constructor(kits: readonly KitManifest[]) {
    const seen = new Set<string>();
    this.list = [];
    for (const kit of kits) {
      if (seen.has(kit.id)) continue;
      seen.add(kit.id);
      this.list.push(kit);
    }
  }

  /**
   * The bundled kits in picker order (`pickerOrder`, then id) from their
   * files. A file that fails to load is a packaging bug, which the tests
   * catch; it is skipped rather than failing the app.
   */
  static fromBundledFiles(files: readonly KitFile[]): KitLibrary {
    const kits = files
      .map((file) => decodeKit(file.text))
      .flatMap((result) => (result.ok ? [result.kit] : []))
      .sort((a, b) => {
        const orderA = a.pickerOrder ?? Number.MAX_SAFE_INTEGER;
        const orderB = b.pickerOrder ?? Number.MAX_SAFE_INTEGER;
        if (orderA !== orderB) return orderA - orderB;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
      });
    return new KitLibrary(kits);
  }

  get kits(): readonly KitManifest[] {
    return this.list;
  }

  get ids(): string[] {
    return this.list.map((kit) => kit.id);
  }

  /** The kit with exactly `id`, if any. */
  get(id: string): KitManifest | undefined {
    return this.list.find((kit) => kit.id === id);
  }

  /** The kit with `id`, or the default kit if it's gone, or the first kit as a last resort. */
  kit(id: string | undefined): KitManifest | undefined {
    return (id === undefined ? undefined : this.get(id)) ?? this.get(DEFAULT_KIT_ID) ?? this.list[0];
  }

  /** Adds or replaces a kit (matched by id), keeping its position if it was present. */
  upsert(kit: KitManifest): void {
    const index = this.list.findIndex((existing) => existing.id === kit.id);
    if (index >= 0) this.list[index] = kit;
    else this.list.push(kit);
  }

  /** The bundled kits followed by imported ones (with their imported ids), so the two never share an id. */
  withImported(imported: readonly KitManifest[]): KitLibrary {
    return new KitLibrary([...this.list, ...imported]);
  }

  /**
   * Replaces the imported kits in place (the bundled ones stay), so a
   * repository holding this library sees an import or a removal at once.
   */
  setImported(imported: readonly KitManifest[]): void {
    const bundled = this.list.filter((kit) => !isImportedKitID(kit.id));
    this.list = new KitLibrary([...bundled, ...imported]).list;
  }

  /** The imported kits, in library order. */
  get imported(): KitManifest[] {
    return this.list.filter((kit) => isImportedKitID(kit.id));
  }
}
