/*
 * Port of AppSettingsPane: the Settings window's five sections, in the
 * Mac's order. Keep it at five; rare settings go under More options inside
 * a section (`SettingsPage`'s `moreOptions`). A section's content is its
 * `Content` component, which gets the window's services and, in a snapshot
 * run, the named state to draw (a sheet open, a message shown).
 */

import type { ComponentType } from "react";
import type { AppServices } from "../../../app/appServices";
import { tr } from "../../../core/localization/tr";
import type { Host } from "../../../host/host";
import { AboutSection, ABOUT_SNAPSHOT_STATES } from "./AboutSection";
import { ConnectionsSection, CONNECTIONS_SNAPSHOT_STATES } from "./connections/ConnectionsSection";
import { GeneralSection, GENERAL_SNAPSHOT_STATES } from "./GeneralSection";
import { LookSection } from "./LookSection";
import { TabsSection, TABS_SNAPSHOT_STATES } from "./TabsSection";

export type SettingsSectionID = "general" | "tabs" | "look" | "connections" | "about";

/** What a section's content gets: the window's services (settings, modules), the host, and a snapshot state to draw. */
export interface SettingsSectionProps {
  readonly app: AppServices;
  readonly host: Host;
  /** A state from the section's `snapshotStates`, in a snapshot run; undefined draws the section at rest. */
  readonly snapshotState?: string;
}

export interface SettingsSection {
  readonly id: SettingsSectionID;
  readonly title: () => string;
  /** An SF Symbol name, mapped to an icon by the kit. */
  readonly symbol: string;
  readonly Content: ComponentType<SettingsSectionProps>;
  /** Extra named states the snapshot harness renders besides the section at rest. */
  readonly snapshotStates?: readonly string[];
}

export const SETTINGS_SECTIONS: readonly SettingsSection[] = [
  { id: "general", title: () => tr("General"), symbol: "gearshape", Content: GeneralSection, snapshotStates: GENERAL_SNAPSHOT_STATES },
  { id: "tabs", title: () => tr("Tabs"), symbol: "square.grid.2x2", Content: TabsSection, snapshotStates: TABS_SNAPSHOT_STATES },
  { id: "look", title: () => tr("Look"), symbol: "paintpalette", Content: LookSection },
  { id: "connections", title: () => tr("Connections"), symbol: "link", Content: ConnectionsSection, snapshotStates: CONNECTIONS_SNAPSHOT_STATES },
  { id: "about", title: () => tr("About"), symbol: "info.circle", Content: AboutSection, snapshotStates: ABOUT_SNAPSHOT_STATES },
];

export function settingsSection(id: string | null | undefined): SettingsSection {
  return SETTINGS_SECTIONS.find((section) => section.id === id) ?? (SETTINGS_SECTIONS[0] as SettingsSection);
}
