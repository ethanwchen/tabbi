/*
 * Port of ProviderHub: merges what the enabled modules provide (tasks,
 * events, progress, the focus clock, the pet, the party, highlights) into
 * one ProviderSnapshot, so the ticker, Today and the pet read shared data
 * without depending on the module that produced it.
 *
 * Only enabled modules contribute, in tab order; a disabled module's data
 * disappears with its tab. When two modules run a focus clock at once, the
 * hub notes when each one started or resumed running, so the snapshot shows
 * the one the user turned to last.
 */

import type { ModuleID } from "../core/modules/moduleId";
import type { ModuleProvision } from "../core/providers/moduleProvision";
import { ProviderSnapshot } from "../core/providers/providerSnapshot";
import type { Instant } from "../core/time";
import { Observable, type Readable } from "./store";

/** Where the hub finds a module's provision; the registry in the app. */
export type ProvisionLookup = (id: ModuleID) => Readable<ModuleProvision> | undefined;

export class ProviderHub {
  private readonly snapshotValue = new Observable<ProviderSnapshot>(ProviderSnapshot.empty);
  private lookup: ProvisionLookup | undefined;
  private enabled: ModuleID[] = [];
  private readonly latest = new Map<ModuleID, ModuleProvision>();
  private readonly subscriptions = new Map<ModuleID, () => void>();
  /**
   * When each module's focus clock went from stopped to running, as the hub
   * saw it. A clock already running when its module connects (one restored
   * at launch) has no entry and yields to any started later.
   */
  private readonly focusStarts = new Map<ModuleID, Instant>();

  constructor(private readonly now: () => Instant) {}

  /** The merged snapshot; it changes only when some enabled module's provision does. */
  readonly snapshot: Readable<ProviderSnapshot> = this.snapshotValue;

  /** Connects the modules whose provisions this hub merges, once they exist. */
  attach(lookup: ProvisionLookup): void {
    if (this.lookup !== undefined) throw new Error("ProviderHub is attached once");
    this.lookup = lookup;
  }

  /** Follows the enabled tabs: subscribes to newly enabled providers and drops disabled ones. Reordering only re-merges. */
  update(enabled: readonly ModuleID[]): void {
    const seen = new Set<ModuleID>();
    this.enabled = enabled.filter((id) => {
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    for (const [id, stop] of [...this.subscriptions]) {
      if (seen.has(id)) continue;
      stop();
      this.subscriptions.delete(id);
      this.latest.delete(id);
      this.focusStarts.delete(id);
    }
    for (const id of this.enabled) {
      if (this.subscriptions.has(id)) continue;
      const provision = this.lookup?.(id);
      if (provision === undefined) continue;
      /* The current value lands at once, so the first snapshot already includes it. */
      this.latest.set(id, provision.get());
      this.subscriptions.set(
        id,
        provision.subscribe(() => this.receive(id, provision.get())),
      );
    }
    this.merge();
  }

  /** Stops following every module, e.g. when the window closes. */
  detachAll(): void {
    this.update([]);
  }

  private receive(id: ModuleID, provision: ModuleProvision): void {
    const previous = this.latest.get(id);
    if (previous === provision) return;
    if (provision.focus?.isRunning !== true) {
      this.focusStarts.delete(id);
    } else if (previous !== undefined && previous.focus?.isRunning !== true) {
      this.focusStarts.set(id, this.now());
    }
    this.latest.set(id, provision);
    this.merge();
  }

  private merge(): void {
    const entries = this.enabled.flatMap((module) => {
      const provision = this.latest.get(module);
      return provision === undefined ? [] : [{ module, provision }];
    });
    /* Provisions are immutable values, so the same ones in the same order with the same starts merge to the same snapshot. */
    const inputs = { entries, starts: [...this.focusStarts] };
    const last = this.lastInputs;
    if (
      last !== undefined &&
      last.entries.length === entries.length &&
      last.entries.every((entry, i) => entry.module === entries[i]?.module && entry.provision === entries[i]?.provision) &&
      last.starts.length === inputs.starts.length &&
      last.starts.every(([id, at], i) => inputs.starts[i]?.[0] === id && inputs.starts[i]?.[1] === at)
    ) {
      return;
    }
    this.lastInputs = inputs;
    this.snapshotValue.set(new ProviderSnapshot(entries, new Map(this.focusStarts)));
  }

  private lastInputs:
    | { readonly entries: readonly { module: ModuleID; provision: ModuleProvision }[]; readonly starts: readonly [ModuleID, Instant][] }
    | undefined;
}
