/*
 * Port of AppearanceSettingsPane, plus what Windows keeps here instead of
 * General: the theme (every choice a live miniature of the panel drawn with
 * the user's own tab accents, picked at once), the panel size, the closed
 * island's mode (Auto, the pill always, or only on hover or hotkey), the
 * motion pace and Reduce Motion.
 */

import type { CSSProperties } from "react";
import { useStore } from "../../../app/useStore";
import { tr } from "../../../core/localization/tr";
import { motionPaceCaption, motionPaceTitle, MOTION_PACES } from "../../../core/motion/motionPace";
import { PANEL_SIZES, panelSizeTitle } from "../../../core/settings/panelSize";
import { themeDisplayName, themeDisplaySummary, type AppTheme, type ThemeFamily } from "../../../core/themes/appTheme";
import { allThemes, resolveTheme } from "../../../core/themes/themeCatalog";
import type { ModuleAccent } from "../../../core/themes/themeColor";
import { useKit, useTransition } from "../../kit/context";
import { Picker } from "../../kit/Picker";
import { SegmentedControl } from "../../kit/SegmentedControl";
import { SettingsGroup, SettingsRow } from "../../kit/SettingsGroup";
import { useTactile } from "../../kit/tactile";
import { ThemePreview } from "../../kit/ThemePreview";
import { Toggle } from "../../kit/Toggle";
import { Tooltip } from "../../kit/Tooltip";
import { NOTCH_MODES, type NotchMode } from "../machine";
import { ResetToDefaultsRow } from "./parts";
import type { SettingsSectionProps } from "./sections";
import { SettingsPage } from "./SettingsWindow";

/** The name Settings shows for a closed-island mode. */
export function islandModeTitle(mode: NotchMode): string {
  switch (mode) {
    case "auto":
      return tr("Auto");
    case "alwaysVisible":
      return tr("Always show the pill");
    case "showOnHover":
      return tr("Only on hover or hotkey");
  }
}

/** What the mode does, in one line. */
export function islandModeCaption(mode: NotchMode): string {
  switch (mode) {
    case "auto":
      return tr("The pill shows while a timer, music or a meeting is live.");
    case "alwaysVisible":
      return tr("The pill is always at the top edge.");
    case "showOnHover":
      return tr("Nothing is drawn until the pointer rests at the top center or you press the shortcut.");
  }
}

export function LookSection({ app }: SettingsSectionProps) {
  const store = app.settings;
  const settings = useStore(store.settings);
  const islandMode = useStore(store.islandMode);
  const reduceMotion = useStore(store.reduceMotion);
  const { reduceMotion: effectiveReduceMotion } = useKit();
  const catalog = store.catalog;
  const selected = resolveTheme(settings.themeID);
  /* The enabled tabs' accents, in tab order, so previews look like this user's island. */
  const accents: ModuleAccent[] = settings.modules.enabled.map((id) => catalog.descriptor(id).accent);
  const defaultTheme = resolveTheme(store.defaultTheme);

  const family = (id: ThemeFamily, title: string, footer?: string) => (
    <SettingsGroup key={id} title={title} footer={footer} className="settings-theme-family">
      {/* Five cards to a row in every family, so the cozy row's three line up with the others and the sweet ten pair up by column. */}
      <div className="settings-theme-row">
        {allThemes
          .filter((theme) => theme.family === id)
          .map((theme) => (
            <ThemeChoice key={theme.id} theme={theme} accents={accents} isSelected={theme.id === selected.id} onPick={() => store.update((value) => ({ ...value, themeID: theme.id }))} />
          ))}
      </div>
    </SettingsGroup>
  );

  const motionCaption = effectiveReduceMotion && settings.motionPace !== "instant" ? tr("Reduce Motion is on, so changes fade instead of moving.") : motionPaceCaption(settings.motionPace);

  return (
    <SettingsPage>
      {family("classic", tr("Classic"))}
      {family("cozy", tr("Cozy"))}
      {family("sweet", tr("Sweet"), tr("%@ Themes style the open panel; the closed pill stays black.", themeDisplaySummary(selected)))}

      <SettingsGroup>
        <SettingsRow label={tr("Panel size")} help={tr("Every tab uses the same size.")}>
          <SegmentedControl
            label={tr("Panel size")}
            segments={PANEL_SIZES.map((size) => ({ id: size, title: panelSizeTitle(size), help: tr("Choose how big the open panel is. Every tab uses the same size.") }))}
            selected={settings.panelSize}
            onSelect={(size) => store.update((value) => ({ ...value, panelSize: size }))}
          />
        </SettingsRow>
        <SettingsRow label={tr("Closed island")} help={islandModeCaption(islandMode)}>
          <Picker<NotchMode>
            label={tr("Closed island")}
            help={tr("Choose when the pill is drawn. The shortcut always opens the island.")}
            items={NOTCH_MODES.map((mode) => ({ id: mode, title: islandModeTitle(mode) }))}
            selected={islandMode}
            onSelect={(mode) => store.setIslandMode(mode)}
            width={200}
          />
        </SettingsRow>
        <SettingsRow label={tr("Animations")} help={motionCaption}>
          <SegmentedControl
            label={tr("Animations")}
            segments={MOTION_PACES.map((pace) => ({ id: pace, title: motionPaceTitle(pace), help: motionPaceCaption(pace) }))}
            selected={settings.motionPace}
            onSelect={(pace) => store.update((value) => ({ ...value, motionPace: pace }))}
          />
        </SettingsRow>
        <SettingsRow label={tr("Reduce Motion")} help={tr("Changes fade instead of moving. Follows Windows' own setting unless you turn it on here.")}>
          <Toggle isOn={reduceMotion} onChange={(on) => store.setReduceMotion(on)} label={tr("Reduce Motion")} help={tr("Turn movement into fades everywhere in Tabbi")} />
        </SettingsRow>
      </SettingsGroup>

      <ResetToDefaultsRow
        isAtDefaults={settings.themeID === store.defaultTheme}
        title={tr("Reset to Default")}
        help={tr("Go back to %@, the theme %@ starts with", themeDisplayName(defaultTheme), store.activeKit?.name ?? app.environment.edition.name)}
        reset={() => store.update((value) => ({ ...value, themeID: store.defaultTheme }))}
      />
    </SettingsPage>
  );
}

/** One theme in the picker: its miniature, name, and a selection ring. */
function ThemeChoice({ theme, accents, isSelected, onPick }: { theme: AppTheme; accents: readonly ModuleAccent[]; isSelected: boolean; onPick: () => void }) {
  const tactile = useTactile();
  const transition = useTransition("snappy", ["box-shadow", "transform", "color"]);
  const style: CSSProperties = { ...tactile.style, transition: [tactile.style.transition, transition].filter(Boolean).join(", ") };
  const name = themeDisplayName(theme);
  return (
    <Tooltip text={`${name}: ${themeDisplaySummary(theme)}`}>
      <button
        type="button"
        className="settings-theme-choice"
        data-selected={isSelected}
        aria-label={name}
        aria-pressed={isSelected}
        {...tactile.data}
        {...tactile.handlers}
        style={style}
        onClick={onPick}
      >
        <span className="settings-theme-preview">
          <ThemePreview theme={theme} accents={accents} width="100%" height={54} />
        </span>
        <span className="settings-theme-name kit-caption">{name}</span>
      </button>
    </Tooltip>
  );
}
