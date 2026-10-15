import type { ModuleCatalog } from "../modules/moduleCatalog";
import {
  MODULE_PERMISSIONS,
  isLocalNetworkAccess,
  type ModuleNetworkAccess,
  type ModulePermission,
} from "../modules/moduleDescriptor";
import type { ModuleID } from "../modules/moduleId";
import { applyKit, type AppSettings } from "../settings/appSettings";
import { samePreviewSettings } from "../settings/notchPreviewSettings";
import { kitStarterTasks, type KitAnswers } from "./kitApplication";
import type { KitManifest } from "./kitManifest";

/**
 * Port of KitChangePreview: what switching to a kit would change, so
 * Settings can show an imported kit's effect before it replaces the user's
 * setup: tabs that turn on or off, the permissions and off-machine hosts the
 * new tabs bring, the starter tasks, and whether the previews change.
 */
export interface KitChangePreview {
  /** The tabs after the switch, in order. */
  readonly tabs: readonly ModuleID[];
  /** Tabs that are off now and on after the switch, in their new order. */
  readonly turnsOn: readonly ModuleID[];
  /** Tabs that are on now and off after the switch, in their old order. */
  readonly turnsOff: readonly ModuleID[];
  /** Permissions the new tabs need that no tab on now already needs. */
  readonly newPermissions: readonly ModulePermission[];
  /** Hosts off this machine the new tabs connect to and no tab on now already does, in tab order. */
  readonly newNetworkAccess: readonly ModuleNetworkAccess[];
  /** The starter tasks the switch adds to Today. */
  readonly starterTasks: readonly string[];
  /** True when the kit sets closed-panel previews that differ from the current ones. */
  readonly changesNotchPreviews: boolean;
}

export function kitChangePreview(
  kit: KitManifest,
  current: AppSettings,
  catalog: ModuleCatalog,
  answers: KitAnswers = {},
): KitChangePreview {
  const next = applyKit(current, kit, catalog, answers);
  const wasOn = new Set(current.modules.enabled);
  const isOn = new Set(next.modules.enabled);
  const turnsOn = next.modules.enabled.filter((id) => !wasOn.has(id));
  const granted = new Set(current.modules.enabled.flatMap((id) => [...(catalog.get(id)?.permissions ?? [])]));
  const needed = new Set(turnsOn.flatMap((id) => [...(catalog.get(id)?.permissions ?? [])]));
  const reached = new Set(current.modules.enabled.flatMap((id) => catalog.get(id)?.network ?? []).map((a) => a.host));
  const listed = new Set<string>();
  const newNetworkAccess = turnsOn
    .flatMap((id) => catalog.get(id)?.network ?? [])
    .filter((access) => {
      if (isLocalNetworkAccess(access) || reached.has(access.host) || listed.has(access.host)) return false;
      listed.add(access.host);
      return true;
    });
  return {
    tabs: next.modules.enabled,
    turnsOn,
    turnsOff: current.modules.enabled.filter((id) => !isOn.has(id)),
    newPermissions: MODULE_PERMISSIONS.filter((permission) => needed.has(permission) && !granted.has(permission)),
    newNetworkAccess,
    starterTasks: kitStarterTasks(kit, answers),
    changesNotchPreviews: !samePreviewSettings(next.notchPreview, current.notchPreview),
  };
}

/** True when switching changes neither tabs nor previews nor Today. */
export function isEmptyKitChange(preview: KitChangePreview): boolean {
  return (
    preview.turnsOn.length === 0 &&
    preview.turnsOff.length === 0 &&
    preview.starterTasks.length === 0 &&
    !preview.changesNotchPreviews
  );
}
