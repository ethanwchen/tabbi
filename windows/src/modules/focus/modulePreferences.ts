/*
 * A module's own preferences: the values the Mac keeps in `UserDefaults`
 * under the module's keys (the focus timer, the focus settings, the Study
 * session), as one JSON document in the module's folder of the edition's
 * data. It loads once (the core's `Defaults` is synchronous, so stores read
 * it the way the Swift does once `ready` resolves), saves one write at a
 * time with the last carrying every change, and posts each save to the
 * module's twin in the other windows, so an option changed in Settings
 * reaches the island. Demo and snapshot runs keep it in memory.
 */

import type { WindowChannel } from "../../app/windowChannel";
import { InMemoryDefaults, loadDefaults, saveDefaults, type Defaults } from "../../core/persistence/defaults";
import type { DocumentStore } from "../../core/persistence/documentStore";
import { isJSONObject, type JSONObject } from "../../core/persistence/json";

const DOCUMENT = "preferences.json";

export class ModulePreferences {
  private values: InMemoryDefaults = new InMemoryDefaults();
  /** Resolves once the saved values are in; a store applies them then. */
  readonly ready: Promise<void>;
  private saving: Promise<void> = Promise.resolve();
  private saveQueued = false;
  private readonly listeners = new Set<() => void>();

  /**
   * - store: the module's folder, or undefined to keep the values in memory.
   * - channel: where saves are posted and other windows' saves arrive.
   */
  constructor(
    private readonly store: DocumentStore | undefined,
    private readonly channel?: WindowChannel,
  ) {
    this.ready =
      store === undefined
        ? Promise.resolve()
        : loadDefaults(store, DOCUMENT).then((loaded) => {
            this.values = loaded;
          });
    channel?.on((message) => this.receive(message));
  }

  /** The values, the Mac's `UserDefaults` for this module. Read them after `ready`. */
  get defaults(): Defaults {
    return this.values;
  }

  /** Called after another window saved its values, so a store can reload what it keeps there. */
  changed(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /** Writes the document (one write at a time) and tells the other windows. */
  save(): void {
    const entries = this.values.entries();
    this.channel?.post({ type: "preferences", entries });
    const store = this.store;
    if (store === undefined || this.saveQueued) return;
    this.saveQueued = true;
    this.saving = this.saving
      .then(() => {
        this.saveQueued = false;
        return saveDefaults(store, DOCUMENT, this.values);
      })
      .catch((error: unknown) => console.error("tabbi preferences: could not save", error));
  }

  private receive(raw: unknown): void {
    if (!isJSONObject(raw) || raw.type !== "preferences" || !isJSONObject(raw.entries)) return;
    this.values = new InMemoryDefaults(raw.entries as JSONObject);
    for (const listener of [...this.listeners]) listener();
  }
}
