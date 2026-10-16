import type { DocumentStore } from "../core/persistence/documentStore";
import type { Host, JsonValue, StorageArea } from "../host/host";

/*
 * The core's DocumentStore over the Rust host's storage commands, so stores
 * only ever see DocumentStore and the app hands them this adapter (demo and
 * snapshot runs hand them an InMemoryDocumentStore instead).
 *
 * The two sides name documents differently. The core names a document by
 * its path inside the edition's folder, file extension included
 * (`Activity/2026-10-02.json`); the host stores JSON documents only, at most
 * one folder deep, and adds the `.json` itself (`Activity/2026-10-02`). The
 * host keeps the parsed value, not the text: it writes the document back
 * pretty printed with sorted keys, so a read returns the same JSON value,
 * not the same characters.
 */

const EXTENSION = ".json";

/** A core document name the host cannot store: not JSON, or more than one folder deep. */
export class UnsupportedDocumentName extends Error {
  constructor(readonly documentName: string) {
    super(`"${documentName}" is not a JSON document at most one folder deep`);
    this.name = "UnsupportedDocumentName";
  }
}

/** A document whose text holds an integer JSON numbers on this side can't keep exactly. */
export class InexactNumberError extends Error {
  constructor(
    readonly documentName: string,
    readonly literal: string,
  ) {
    super(`"${documentName}" holds ${literal}, which a JSON number can't keep exactly`);
    this.name = "InexactNumberError";
  }
}

/* The reviver context engines that ship JSON.parse source text access pass as a third argument. */
type ReviverContext = { readonly source?: string } | undefined;

/*
 * Parses `text` as the host will keep it. An integer past 2^53 would come
 * back rounded (the webview only has doubles), so the write is refused
 * instead of quietly saving another number. Engines without source text
 * access skip the check.
 */
function parseDocument(name: string, text: string): JsonValue {
  return JSON.parse(text, function (this: unknown, _key: string, value: unknown, context?: ReviverContext) {
    const source = context?.source;
    if (typeof value === "number" && source !== undefined && /^-?\d+$/.test(source) && !Number.isSafeInteger(value)) {
      throw new InexactNumberError(name, source);
    }
    return value;
  }) as JsonValue;
}

/** The host's name for a core document name: the extension dropped, at most one folder. */
function hostName(name: string): string {
  const parts = name.split("/");
  if (!name.endsWith(EXTENSION) || name.length === EXTENSION.length || parts.length > 2 || parts.some((part) => part === "")) {
    throw new UnsupportedDocumentName(name);
  }
  return name.slice(0, -EXTENSION.length);
}

/** The host's folder for a core folder: null for the area's root, which is the edition's folder. */
function hostFolder(folder: string): string | null {
  const trimmed = folder.replace(/\/+$/, "");
  if (trimmed === "") return null;
  if (trimmed.includes("/")) throw new UnsupportedDocumentName(folder);
  return trimmed;
}

export class HostDocumentStore implements DocumentStore {
  constructor(
    private readonly host: Pick<Host, "storageRead" | "storageWrite" | "storageList" | "storageDelete">,
    /** Durable for what the user made (settings, tasks, the pet), cache for anything that can be fetched again. */
    readonly area: StorageArea = "durable",
  ) {}

  async read(name: string): Promise<string | undefined> {
    const value = await this.host.storageRead(this.area, hostName(name));
    return value === null ? undefined : JSON.stringify(value);
  }

  async write(name: string, text: string): Promise<void> {
    const target = hostName(name);
    await this.host.storageWrite(this.area, target, parseDocument(name, text));
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
