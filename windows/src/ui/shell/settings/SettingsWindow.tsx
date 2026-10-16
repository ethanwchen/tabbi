/*
 * The Settings window: a normal Windows window with a dark native title
 * bar, themed like the island, with the Mac's five sections in a sidebar
 * and the selected one beside it. It is its own webview with its own
 * AppServices (modules are created there but never started), and every
 * change it makes reaches the island through the settings store.
 */

import { useEffect, useState, type ReactNode } from "react";
import type { AppServices } from "../../../app/appServices";
import { tr } from "../../../core/localization/tr";
import type { Host } from "../../../host/host";
import { Icon } from "../../kit/Icon";
import { MoreOptions } from "../../kit/SettingsGroup";
import { StatusMessage } from "../../kit/StatusMessage";
import { settingsSection, SETTINGS_SECTIONS, type SettingsSectionID } from "./sections";

export interface SettingsWindowProps {
  readonly app: AppServices;
  readonly host: Host;
  readonly initialSection?: string | null;
}

export function SettingsWindow({ app, host, initialSection }: SettingsWindowProps) {
  const [selected, setSelected] = useState<SettingsSectionID>(settingsSection(initialSection).id);

  /* The gear or the tray asked for a section while the window was open. */
  useEffect(
    () =>
      host.subscribe((event) => {
        if (event.type === "settingsSection") setSelected(settingsSection(event.section).id);
      }),
    [host],
  );

  const section = settingsSection(selected);
  const Content = section.Content;
  return (
    <div className="settings-window">
      <nav className="settings-sidebar" aria-label={tr("Tabbi Settings")}>
        {SETTINGS_SECTIONS.map((entry) => (
          <button
            key={entry.id}
            type="button"
            className="settings-nav"
            data-selected={entry.id === selected}
            aria-current={entry.id === selected ? "page" : undefined}
            title={entry.title()}
            onClick={() => setSelected(entry.id)}
          >
            <Icon id={entry.symbol} size={16} />
            <span>{entry.title()}</span>
          </button>
        ))}
      </nav>
      <main className="settings-content">
        <h1 className="settings-title">{section.title()}</h1>
        {Content ? (
          <Content app={app} />
        ) : (
          <div className="settings-empty">
            <StatusMessage symbol={section.symbol} tint="var(--secondary-text)" title={section.title()} message={tr("This section arrives in a later Windows build.")} />
          </div>
        )}
      </main>
    </div>
  );
}

/** A section's page: its groups, then its rare settings folded under More options. */
export function SettingsPage({ children, moreOptions }: { children?: ReactNode; moreOptions?: ReactNode }) {
  return (
    <div className="settings-page">
      {children}
      {moreOptions !== undefined && moreOptions !== null && <MoreOptions>{moreOptions}</MoreOptions>}
    </div>
  );
}
