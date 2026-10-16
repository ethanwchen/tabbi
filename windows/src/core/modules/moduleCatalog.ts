import { unknownModuleDescriptor, type ModuleDescriptor } from "./moduleDescriptor";
import type { ModuleID } from "./moduleId";
import type { ModuleLayout } from "./moduleLayout";

/**
 * Port of ModuleCatalog: the modules this build knows, in canonical tab
 * order. Ids are unique: a later duplicate is left out of `descriptors` and
 * recorded in `duplicateIDs`, so the app can fail loudly on a module list
 * mistake instead of hiding a module.
 */
export class ModuleCatalog {
  readonly descriptors: readonly ModuleDescriptor[];
  /** Ids that appeared more than once, once each, in the order their first repeat appeared. */
  readonly duplicateIDs: readonly ModuleID[];
  /**
   * Modules this edition leaves out on purpose (Edition.excludedModules).
   * They are not in `descriptors`, and kits that list them get no warning.
   */
  readonly unavailableIDs: ReadonlySet<ModuleID>;
  private readonly index: ReadonlyMap<ModuleID, ModuleDescriptor>;

  constructor(descriptors: readonly ModuleDescriptor[], unavailable: Iterable<ModuleID> = []) {
    const index = new Map<ModuleID, ModuleDescriptor>();
    const unique: ModuleDescriptor[] = [];
    const duplicates: ModuleID[] = [];
    for (const descriptor of descriptors) {
      if (!index.has(descriptor.id)) {
        index.set(descriptor.id, descriptor);
        unique.push(descriptor);
      } else if (!duplicates.includes(descriptor.id)) {
        duplicates.push(descriptor.id);
      }
    }
    this.descriptors = unique;
    this.duplicateIDs = duplicates;
    this.index = index;
    this.unavailableIDs = new Set([...unavailable].filter((id) => !index.has(id)));
  }

  /** This catalog without `ids`, which become unavailable. An edition uses it to leave modules out. */
  excluding(ids: Iterable<ModuleID>): ModuleCatalog {
    const excluded = new Set([...this.unavailableIDs, ...ids]);
    return new ModuleCatalog(
      this.descriptors.filter((descriptor) => !excluded.has(descriptor.id)),
      excluded,
    );
  }

  /** Whether `id` is a module this edition leaves out, as opposed to one no build knows. */
  isUnavailable(id: ModuleID): boolean {
    return this.unavailableIDs.has(id);
  }

  /** Every id, in canonical order. */
  get ids(): ModuleID[] {
    return this.descriptors.map((descriptor) => descriptor.id);
  }

  contains(id: ModuleID): boolean {
    return this.index.has(id);
  }

  /** The descriptor for `id`, or undefined when the catalog doesn't know it. */
  get(id: ModuleID): ModuleDescriptor | undefined {
    return this.index.get(id);
  }

  /** The descriptor for `id`, or a neutral placeholder if it is unknown. */
  descriptor(id: ModuleID): ModuleDescriptor {
    return this.index.get(id) ?? unknownModuleDescriptor(id);
  }

  /**
   * The first enabled module in `layout` that runs its own focus clock, or
   * undefined when the shared Pomodoro is the layout's only timer.
   */
  focusClockOwner(layout: ModuleLayout): ModuleID | undefined {
    return layout.enabled.find((id) => this.index.get(id)?.ownsFocusClock === true);
  }
}
