import { documentName } from "../persistence/documentStore";
import type { Edition } from "./edition";

/**
 * Port of EditionStorage: where one edition keeps its files, a folder named
 * after the edition inside the user's app data folder (the Mac's
 * Application Support). Every persisted document goes through `folder` or
 * `file`, so no store hardcodes an app name. Paths are DocumentStore names,
 * relative to the app data folder the host's store is rooted at.
 */
export class EditionStorage {
  constructor(readonly root: string) {}

  /** The edition's folder, named after the edition. */
  static forEdition(edition: Edition): EditionStorage {
    return new EditionStorage(edition.name);
  }

  /** A named folder inside the edition's folder, such as `Planner`. */
  folder(name: string): string {
    return documentName(this.root, name);
  }

  /** A document inside one of the edition's folders, such as `Pet/pet.json`. */
  file(name: string, folder: string): string {
    return documentName(this.folder(folder), name);
  }
}
