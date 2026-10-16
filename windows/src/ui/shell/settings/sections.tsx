/*
 * Port of AppSettingsPane: the Settings window's five sections, in the
 * Mac's order. Keep it at five; rare settings go under More options inside
 * a section (`SettingsPage`'s `moreOptions`). A section's content is its
 * `Content` component; until one is written the section shows a calm empty
 * state. Fill one by pointing its `Content` at a component in
 * `src/ui/settings/<section>/`.
 */

import type { ComponentType } from "react";
import type { AppServices } from "../../../app/appServices";
import { tr } from "../../../core/localization/tr";

export type SettingsSectionID = "general" | "tabs" | "look" | "connections" | "about";

/** What a section's content gets: the window's services (settings, modules, the host). */
export interface SettingsSectionProps {
  readonly app: AppServices;
}

export interface SettingsSection {
  readonly id: SettingsSectionID;
  readonly title: () => string;
  /** An SF Symbol name, mapped to an icon by the kit. */
  readonly symbol: string;
  readonly Content?: ComponentType<SettingsSectionProps>;
}

export const SETTINGS_SECTIONS: readonly SettingsSection[] = [
  { id: "general", title: () => tr("General"), symbol: "gearshape" },
  { id: "tabs", title: () => tr("Tabs"), symbol: "square.grid.2x2" },
  { id: "look", title: () => tr("Look"), symbol: "paintpalette.fill" },
  { id: "connections", title: () => tr("Connections"), symbol: "link" },
  { id: "about", title: () => tr("About"), symbol: "info.circle" },
];

export function settingsSection(id: string | null | undefined): SettingsSection {
  return SETTINGS_SECTIONS.find((section) => section.id === id) ?? (SETTINGS_SECTIONS[0] as SettingsSection);
}
