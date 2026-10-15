/*
 * The open island's header, laid out like the Mac's NotchHeaderLayout: the
 * tabs from the left edge, and from the right edge the header shortcuts (the
 * Closet's paw) with the selected tab's title beside them. Windows has no
 * camera housing, so nothing is reserved in the middle.
 */

import type { CSSProperties } from "react";
import { Icon } from "./icons";
import { accentColor, type ModuleStub } from "./modules";

interface HeaderProps {
  readonly tabs: readonly ModuleStub[];
  readonly shortcuts: readonly ModuleStub[];
  readonly selected: ModuleStub;
  readonly onSelect: (id: string) => void;
}

export function Header({ tabs, shortcuts, selected, onSelect }: HeaderProps) {
  return (
    <div className="header">
      <div className="tabs" role="tablist" aria-label="Tabs">
        {tabs.map((tab, index) => {
          const isSelected = tab.id === selected.id;
          return (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={isSelected}
              aria-label={tab.title}
              title={`${tab.title} (${index + 1})`}
              className="tab"
              data-selected={isSelected}
              style={{ "--accent": accentColor(tab), "--accent-soft": accentColor(tab, 0.16) } as CSSProperties}
              onClick={() => onSelect(tab.id)}
            >
              <Icon symbol={tab.symbol} size={16} />
            </button>
          );
        })}
      </div>
      <div className="trailing">
        <span className="title">{selected.title}</span>
        {shortcuts.map((shortcut) => (
          <button
            key={shortcut.id}
            type="button"
            aria-label={shortcut.title}
            title={`${shortcut.title} (${shortcut.headerShortcut?.toUpperCase()})`}
            className="tab shortcut"
            data-selected={shortcut.id === selected.id}
            style={{ "--accent": accentColor(shortcut), "--accent-soft": accentColor(shortcut, 0.16) } as CSSProperties}
            onClick={() => onSelect(shortcut.id)}
          >
            <Icon symbol={shortcut.symbol} size={16} />
          </button>
        ))}
      </div>
    </div>
  );
}
