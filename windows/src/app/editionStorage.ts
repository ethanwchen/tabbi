/*
 * Where a module keeps its files: the Mac's `context.storage.folder("<Name>")`,
 * as a DocumentStore rooted at that folder of the edition's data. Live runs
 * read and write through the host (HostDocumentStore, whose root already is
 * the edition's folder, %APPDATA%\Tabbi for durable data and
 * %LOCALAPPDATA%\Tabbi for caches); demo and snapshot runs keep everything
 * in memory for the run, so they never touch the user's files.
 */

import { documentName, InMemoryDocumentStore, type DocumentStore } from "../core/persistence/documentStore";
import type { Host, StorageArea } from "../host/host";
import { HostDocumentStore } from "../platform/hostDocumentStore";

/** A store whose names are relative to `folder` inside `base`. */
export class FolderDocumentStore implements DocumentStore {
  constructor(
    private readonly base: DocumentStore,
    readonly folder: string,
  ) {}

  private name(name: string): string {
    return documentName(this.folder, name);
  }

  read(name: string): Promise<string | undefined> {
    return this.base.read(this.name(name));
  }

  write(name: string, text: string): Promise<void> {
    return this.base.write(this.name(name), text);
  }

  remove(name: string): Promise<void> {
    return this.base.remove(this.name(name));
  }

  list(folder: string): Promise<string[]> {
    return this.base.list(folder === "" ? this.folder : this.name(folder));
  }
}

/**
 * The edition's storage, the Mac's EditionStorage for modules. `root` is the
 * edition's own folder (where settings live); `folder("Planner")` is a
 * module's folder in it. Durable data (what the user made) and caches
 * (anything refetchable) are separate areas, as on Windows they live in
 * Roaming and Local app data.
 */
export class EditionFolders {
  constructor(
    private readonly durable: DocumentStore,
    private readonly cache: DocumentStore,
  ) {}

  /** Storage over the host's documents. */
  static live(host: Pick<Host, "storageRead" | "storageWrite" | "storageList" | "storageDelete">): EditionFolders {
    return new EditionFolders(new HostDocumentStore(host, "durable"), new HostDocumentStore(host, "cache"));
  }

  /** Storage that lives in this object for the run: demo data must not overwrite the user's files, and a snapshot run leaves no trace. */
  static ephemeral(): EditionFolders {
    return new EditionFolders(new InMemoryDocumentStore(), new InMemoryDocumentStore());
  }

  /** The edition's folder itself, for app-wide documents such as the settings. */
  root(area: StorageArea = "durable"): DocumentStore {
    return area === "durable" ? this.durable : this.cache;
  }

  /** A named folder of the edition's data, such as `Planner`; documents are named inside it (`tasks.json`). */
  folder(name: string, area: StorageArea = "durable"): DocumentStore {
    return new FolderDocumentStore(this.root(area), name);
  }
}
