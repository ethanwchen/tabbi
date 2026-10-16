import type { DocumentStore } from "../core/persistence/documentStore";
import type { Host, StorageArea } from "../host/host";

/*
 * The core's DocumentStore over the Rust host's storage commands, so stores
 * only ever see DocumentStore and the app hands them this adapter (demo and
 * snapshot runs hand them an InMemoryDocumentStore instead).
 *
 * The core names a document by its path inside the edition's folder, file
 * extension included (`Activity/2026-10-02.json`); the host stores JSON
 * documents only, up to two folders deep, and adds the `.json` itself
 * (`Activity/2026-10-02`). The text passes through untouched both ways, so a
 * document keeps the Mac's exact format and every digit of a 64-bit integer.
 */

const EXTENSION = ".json";

/** Folders a document may nest, the host's limit (storage.rs `MAX_FOLDERS`). */
const MAX_FOLDERS = 2;

/** A core document name the host cannot store: not JSON, or more than two folders deep. */
export class UnsupportedDocumentName extends Error {
  constructor(readonly documentName: string) {
    super(`"${documentName}" is not a JSON document at most two folders deep`);
    this.name = "UnsupportedDocumentName";
  }
}

/** The host's name for a core document name: the extension dropped, at most two folders. */
function hostName(name: string): string {
  const parts = name.split("/");
  if (!name.endsWith(EXTENSION) || name.length === EXTENSION.length || parts.length > MAX_FOLDERS + 1 || parts.some((part) => part === "")) {
    throw new UnsupportedDocumentName(name);
  }
  return name.slice(0, -EXTENSION.length);
}

/** The host's folder for a core folder: null for the area's root, which is the edition's folder. */
function hostFolder(folder: string): string | null {
  const trimmed = folder.replace(/\/+$/, "");
  if (trimmed === "") return null;
  if (trimmed.split("/").length > MAX_FOLDERS) throw new UnsupportedDocumentName(folder);
  return trimmed;
}

export class HostDocumentStore implements DocumentStore {
  constructor(
    private readonly host: Pick<Host, "storageRead" | "storageWrite" | "storageList" | "storageDelete">,
    /** Durable for what the user made (settings, tasks, the pet), cache for anything that can be fetched again. */
    readonly area: StorageArea = "durable",
  ) {}

  async read(name: string): Promise<string | undefined> {
    return (await this.host.storageRead(this.area, hostName(name))) ?? undefined;
  }

  async write(name: string, text: string): Promise<void> {
    await this.host.storageWrite(this.area, hostName(name), text);
  }

  async remove(name: string): Promise<void> {
    await this.host.storageDelete(this.area, hostName(name));
  }

  async list(folder: string): Promise<string[]> {
    const names = await this.host.storageList(this.area, hostFolder(folder));
    /* The host lists full names without the extension; the core wants file names with it. */
    return names.map((full) => `${full.split("/").pop() ?? full}${EXTENSION}`);
  }
}
