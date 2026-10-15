/*
 * Where persisted documents live. The core never touches the disk: a store
 * reads and writes named text documents, and the host implements it over
 * the edition's app data folder (the Mac's EditionStorage). Demo and
 * snapshot runs use the in-memory store, so they leave no trace.
 *
 * A name is a slash-separated path inside the edition's folder, such as
 * `Activity/2026-10-02.json`; `folder` in `list` is such a path without the
 * file name.
 */

export interface DocumentStore {
  /** The document's text, or undefined when there is none. Rejects when it exists but can't be read. */
  read(name: string): Promise<string | undefined>;
  /** Replaces the document atomically, creating its folder when needed. */
  write(name: string, text: string): Promise<void>;
  /** Removes the document; does nothing when there is none. */
  remove(name: string): Promise<void>;
  /** The file names (not paths) of the documents directly in `folder`, in any order. */
  list(folder: string): Promise<string[]>;
}

/** Joins a folder and a file name into a document name. */
export function documentName(folder: string, file: string): string {
  return folder === "" ? file : `${folder.replace(/\/+$/, "")}/${file}`;
}

/** A store that keeps its documents in this object only: for tests, demo data and snapshot runs. */
export class InMemoryDocumentStore implements DocumentStore {
  private readonly documents = new Map<string, string>();

  constructor(initial: Readonly<Record<string, string>> = {}) {
    for (const [name, text] of Object.entries(initial)) this.documents.set(name, text);
  }

  async read(name: string): Promise<string | undefined> {
    return this.documents.get(name);
  }

  async write(name: string, text: string): Promise<void> {
    this.documents.set(name, text);
  }

  async remove(name: string): Promise<void> {
    this.documents.delete(name);
  }

  async list(folder: string): Promise<string[]> {
    const prefix = folder === "" ? "" : `${folder.replace(/\/+$/, "")}/`;
    const names: string[] = [];
    for (const name of this.documents.keys()) {
      if (!name.startsWith(prefix)) continue;
      const rest = name.slice(prefix.length);
      if (rest !== "" && !rest.includes("/")) names.push(rest);
    }
    return names;
  }

  /** Every document, by name, for tests. */
  snapshot(): Record<string, string> {
    return Object.fromEntries(this.documents);
  }
}
