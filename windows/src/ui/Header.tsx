/*
 * The open island's header, placed by the core's NotchHeaderLayout as on a
 * notchless Mac: the tabs from the leading edge (tightening, then
 * overflowing behind a "more" button), and from the trailing edge the
 * header shortcuts (the Closet's paw), the Settings gear and the selected
 * tab's title, which shrinks a little before it is dropped and never shows
 * cut. A capsule in the selected tab's accent slides between tabs on the
 * snappy spring. Frames are logical pixels from the leading edge, so the
 * whole row mirrors in Arabic.
 */

import { useMemo, type CSSProperties } from "react";
import { tr } from "../core/localization/tr";
import type { ModuleCatalog } from "../core/modules/moduleCatalog";
import type { ModuleID } from "../core/modules/moduleId";
import type { ModuleLayout } from "../core/modules/moduleLayout";
import { NotchHeaderLayout } from "../core/modules/notchHeaderLayout";
import type { Rect } from "../core/modules/rect";
import { useTheme } from "./kit/context";
import { Icon } from "./kit/Icon";
import { IconButton } from "./kit/IconButton";
import { useTactile } from "./kit/tactile";
import { accentVariables } from "./kit/tokens";
import { Tooltip } from "./kit/Tooltip";
import { textWidth } from "./shell/measure";

/** The header row's height: the pill's 32 px (NotchTabBar: max(notch height, 32)). */
export const HEADER_HEIGHT = 32;
const TITLE_SIZE = 13;
const TITLE_WEIGHT = 600;

export interface HeaderProps {
  readonly catalog: ModuleCatalog;
  readonly layout: ModuleLayout;
  readonly selected: ModuleID;
  readonly onSelect: (id: ModuleID) => void;
  readonly canvasWidth: number;
  /** The count each tab wears (Party's friend requests). */
  readonly badges: ReadonlyMap<ModuleID, number>;
  readonly onOpenSettings: () => void;
  readonly showsMore: boolean;
  readonly onShowMore: (shows: boolean) => void;
}

/** The header's layout for a title, measured in the title type. */
export function headerLayout(layout: ModuleLayout, title: string, canvasWidth: number): NotchHeaderLayout {
  return new NotchHeaderLayout({
    canvasWidth,
    headerHeight: HEADER_HEIGHT,
    tabCount: layout.tabs.length,
    shortcutCount: layout.headerShortcuts.length,
    titleWidth: Math.ceil(textWidth(title, TITLE_SIZE, TITLE_WEIGHT)),
  });
}

function place(frame: Rect): CSSProperties {
  return { insetInlineStart: frame.x, top: frame.y, width: frame.width, height: frame.height };
}

export function Header({ catalog, layout, selected, onSelect, canvasWidth, badges, onOpenSettings, showsMore, onShowMore }: HeaderProps) {
  const theme = useTheme();
  const title = catalog.descriptor(selected).title;
  const header = useMemo(() => headerLayout(layout, title, canvasWidth), [layout, title, canvasWidth]);
  const tabs = layout.tabs;
  const visible = tabs.slice(0, header.visibleTabCount);
  const overflowSelected = header.overflowSelection(tabs, selected);
  /* The capsule sits under the selected tab, or under "more" while the open tab is hidden behind it. */
  const capsuleFrame = overflowSelected !== undefined ? header.moreFrame : header.tabFrames[visible.indexOf(selected)];
  const capsuleAccent = catalog.descriptor(selected).accent;

  return (
    <div className="header" style={{ height: HEADER_HEIGHT }}>
      {capsuleFrame !== undefined && (
        <span
          className="tab-capsule"
          aria-hidden="true"
          style={{ ...place(capsuleFrame), ...(accentVariables(theme, capsuleAccent) as CSSProperties) }}
        />
      )}
      <div role="tablist" aria-label={tr("Tabs")}>
        {visible.map((id, index) => {
          const frame = header.tabFrames[index];
          if (frame === undefined) return null;
          return (
            <TabButton
              key={id}
              id={id}
              catalog={catalog}
              frame={frame}
              shortcut={layout.shortcut(id)}
              isSelected={id === selected}
              badge={badges.get(id) ?? 0}
              onSelect={onSelect}
            />
          );
        })}
      </div>
      {header.moreFrame !== undefined && (
        <MoreButton
          frame={header.moreFrame}
          isOpen={showsMore}
          selectedAccent={overflowSelected === undefined ? undefined : catalog.descriptor(overflowSelected).accent}
          hasBadge={header.overflowTabs(tabs).some((id) => (badges.get(id) ?? 0) > 0)}
          onToggle={() => onShowMore(!showsMore)}
        />
      )}
      {header.titleFrame !== undefined && (
        <span
          className="header-title"
          style={{ ...place(header.titleFrame), fontSize: TITLE_SIZE * header.titleScale }}
          title={title}
        >
          {title}
        </span>
      )}
      <span className="header-gear" style={place(header.gearFrame)}>
        <IconButton symbol="gearshape" size={header.gearFrame.width} help={tr("Tabbi Settings")} onClick={onOpenSettings} />
      </span>
      {layout.headerShortcuts.map((id, index) => {
        const frame = header.shortcutFrames[index];
        if (frame === undefined) return null;
        return <ShortcutButton key={id} id={id} catalog={catalog} frame={frame} isSelected={id === selected} onSelect={onSelect} />;
      })}
      {showsMore && header.moreFrame !== undefined && header.moreListTop !== undefined && (
        <>
          <div className="more-backdrop" onClick={() => onShowMore(false)} />
          <MoreTabsMenu
            catalog={catalog}
            layout={layout}
            tabs={header.overflowTabs(tabs)}
            selected={selected}
            badges={badges}
            style={{ insetInlineStart: header.moreFrame.x, top: header.moreListTop }}
            onSelect={onSelect}
          />
        </>
      )}
    </div>
  );
}

interface TabButtonProps {
  readonly id: ModuleID;
  readonly catalog: ModuleCatalog;
  readonly frame: Rect;
  readonly shortcut: number | undefined;
  readonly isSelected: boolean;
  readonly badge: number;
  readonly onSelect: (id: ModuleID) => void;
}

function TabButton({ id, catalog, frame, shortcut, isSelected, badge, onSelect }: TabButtonProps) {
  const theme = useTheme();
  const descriptor = catalog.descriptor(id);
  const tactile = useTactile();
  const help = shortcut === undefined ? descriptor.title : `${descriptor.title} (${shortcut})`;
  return (
    <Tooltip text={help}>
      <button
        type="button"
        role="tab"
        aria-selected={isSelected}
        aria-label={descriptor.title}
        className="tab"
        data-selected={isSelected}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...place(frame), ...tactile.style, ...(accentVariables(theme, descriptor.accent) as CSSProperties) }}
        onClick={() => onSelect(id)}
      >
        <Icon id={descriptor.symbol} size={14} />
        {badge > 0 && <TabBadge count={badge} />}
      </button>
    </Tooltip>
  );
}

function TabBadge({ count }: { count: number }) {
  return (
    <span className="tab-badge" aria-hidden="true">
      {count > 9 ? "9+" : count}
    </span>
  );
}

interface MoreButtonProps {
  readonly frame: Rect;
  readonly isOpen: boolean;
  readonly selectedAccent: { red: number; green: number; blue: number } | undefined;
  readonly hasBadge: boolean;
  readonly onToggle: () => void;
}

function MoreButton({ frame, isOpen, selectedAccent, hasBadge, onToggle }: MoreButtonProps) {
  const theme = useTheme();
  const tactile = useTactile();
  const accent = selectedAccent === undefined ? {} : (accentVariables(theme, selectedAccent) as CSSProperties);
  return (
    <Tooltip text={tr("More tabs")}>
      <button
        type="button"
        aria-label={tr("More tabs")}
        aria-expanded={isOpen}
        className="tab more"
        data-open={isOpen}
        data-selected={selectedAccent !== undefined}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...place(frame), ...tactile.style, ...accent }}
        onClick={onToggle}
      >
        <Icon id="chevron.down" size={10} />
        {hasBadge && <span className="more-dot" aria-hidden="true" />}
      </button>
    </Tooltip>
  );
}

interface MoreTabsMenuProps {
  readonly catalog: ModuleCatalog;
  readonly layout: ModuleLayout;
  readonly tabs: readonly ModuleID[];
  readonly selected: ModuleID;
  readonly badges: ReadonlyMap<ModuleID, number>;
  readonly style: CSSProperties;
  readonly onSelect: (id: ModuleID) => void;
}

/** The tabs that didn't fit, listed under the "more" button with their number keys. */
function MoreTabsMenu({ catalog, layout, tabs, selected, badges, style, onSelect }: MoreTabsMenuProps) {
  const theme = useTheme();
  return (
    <div className="more-menu" role="menu" style={style}>
      {tabs.map((id) => {
        const descriptor = catalog.descriptor(id);
        const shortcut = layout.shortcut(id);
        const badge = badges.get(id) ?? 0;
        return (
          <button
            key={id}
            type="button"
            role="menuitem"
            className="more-row"
            data-selected={id === selected}
            title={shortcut === undefined ? descriptor.title : `${descriptor.title} (${shortcut})`}
            style={accentVariables(theme, descriptor.accent) as CSSProperties}
            onClick={() => onSelect(id)}
          >
            <Icon id={descriptor.symbol} size={13} />
            <span className="more-row-title">{descriptor.title}</span>
            {badge > 0 && <TabBadge count={badge} />}
            {shortcut !== undefined && <span className="more-row-key">{shortcut}</span>}
          </button>
        );
      })}
    </div>
  );
}

interface ShortcutButtonProps {
  readonly id: ModuleID;
  readonly catalog: ModuleCatalog;
  readonly frame: Rect;
  readonly isSelected: boolean;
  readonly onSelect: (id: ModuleID) => void;
}

/** A header shortcut sized like a tab: the paw takes the pet's accent on hover and while its page is open, and wiggles once on hover. */
function ShortcutButton({ id, catalog, frame, isSelected, onSelect }: ShortcutButtonProps) {
  const theme = useTheme();
  const descriptor = catalog.descriptor(id);
  const tactile = useTactile();
  const label = descriptor.headerShortcut?.label ?? descriptor.title;
  const key = descriptor.headerShortcut?.key;
  const help = key === undefined ? label : `${label} (${key.toUpperCase()})`;
  return (
    <Tooltip text={help}>
      <button
        type="button"
        aria-label={label}
        className="tab shortcut"
        data-selected={isSelected}
        {...tactile.data}
        {...tactile.handlers}
        style={{ ...place(frame), ...tactile.style, ...(accentVariables(theme, descriptor.accent) as CSSProperties) }}
        onClick={() => onSelect(id)}
      >
        <Icon id={descriptor.symbol} size={14} />
      </button>
    </Tooltip>
  );
}
