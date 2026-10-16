/*
 * Port of GeneralSettingsPane for Windows: the app-wide name, Start with
 * Windows (the Mac's Launch at login, through the host's autostart, off by
 * default), the language (which follows Windows), how the island opens,
 * the global shortcut with the kit's recorder, and under More options the
 * feedback switches and the closed pill's live activity. The island's
 * mode and the panel size live in Look on Windows.
 */

import { useEffect, useState } from "react";
import { useStore } from "../../../app/useStore";
import { currentLanguage, tr } from "../../../core/localization/tr";
import { DISPLAY_NAME_MAX_LENGTH } from "../../../core/settings/displayName";
import { DEFAULT_HOTKEY, type Hotkey } from "../../../core/settings/hotkey";
import { previewKindEnabled, settingPreviewKind, TICKER_INTERVALS, tickerIntervalTitle, type TickerInterval } from "../../../core/settings/notchPreviewSettings";
import { allTickerKinds, tickerKindModule, tickerKindTitle } from "../../../core/ticker/tickerKind";
import { HotkeyRecorder } from "../../kit/HotkeyRecorder";
import { windowsLabel } from "../../kit/hotkeyRecording";
import { IconButton } from "../../kit/IconButton";
import { Picker } from "../../kit/Picker";
import { SettingsGroup, SettingsRow } from "../../kit/SettingsGroup";
import { TextField } from "../../kit/TextField";
import { Toggle } from "../../kit/Toggle";
import { ResetToDefaultsRow } from "./parts";
import type { SettingsSectionProps } from "./sections";
import { SettingsPage } from "./SettingsWindow";

export const GENERAL_SNAPSHOT_STATES = ["conflict", "more"] as const;

/** The language's own name ("Deutsch"), as Windows shows it. */
function languageName(language: string): string {
  try {
    return new Intl.DisplayNames([language], { type: "language" }).of(language) ?? language;
  } catch {
    return language;
  }
}

export function GeneralSection({ app, snapshotState }: SettingsSectionProps) {
  const store = app.settings;
  const settings = useStore(store.settings);
  const status = useStore(store.hotkeyStatus);
  const launchError = useStore(store.launchAtLoginError);
  const [recording, setRecording] = useState(false);
  const appName = app.environment.edition.name;
  const catalog = store.catalog;
  const offersParty = catalog.contains("party");

  /* Windows' own settings may have changed Start with Windows meanwhile. */
  useEffect(() => {
    void store.refreshLaunchAtLogin();
  }, [store]);

  const isDefaultHotkey = settings.hotkey.keyCode === DEFAULT_HOTKEY.keyCode && settings.hotkey.modifiers === DEFAULT_HOTKEY.modifiers;
  const taken = snapshotState === "conflict" || (status !== undefined && !status.registered && !recording);
  const conflict = taken ? tr("%@ is already used by another app. Record a different shortcut.", windowsLabel(settings.hotkey)) : undefined;
  const record = (hotkey: Hotkey) => void store.setHotkey(hotkey);

  const liveActivityKinds = allTickerKinds(catalog);
  const previewOn = settings.notchPreview.isEnabled;

  return (
    <SettingsPage
      moreOpen={snapshotState === "more"}
      moreOptions={
        <>
          <SettingsGroup title={tr("Feedback")}>
            <SettingsRow label={tr("Celebration sound")} help={tr("A soft sound when you unlock an item or reach a streak.")}>
              <Toggle
                isOn={settings.celebrationSoundEnabled}
                onChange={(on) => store.update((value) => ({ ...value, celebrationSoundEnabled: on }))}
                label={tr("Celebration sound")}
                help={tr("Play a soft sound with celebrations that have no sound of their own")}
              />
            </SettingsRow>
            <SettingsRow label={tr("Weekly recap")} help={tr("A card with your week in the notch every Sunday evening.")}>
              <Toggle
                isOn={settings.weeklyRecapEnabled}
                onChange={(on) => store.update((value) => ({ ...value, weeklyRecapEnabled: on }))}
                label={tr("Weekly recap")}
                help={tr("Show a recap of your week the first time you open the notch after Sunday 6 pm")}
              />
            </SettingsRow>
            <SettingsRow label={tr("Cat wisdom")} help={tr("Now and then, a short line from your pet after a focus session.")}>
              <Toggle
                isOn={settings.catWisdomEnabled}
                onChange={(on) => store.update((value) => ({ ...value, catWisdomEnabled: on }))}
                label={tr("Cat wisdom")}
                help={tr("Let your pet say a rare encouraging line right after a focus session ends, at most once a day")}
              />
            </SettingsRow>
          </SettingsGroup>
          <SettingsGroup title={tr("Live activity")} footer={tr("Items with nothing to show are skipped.")}>
            <SettingsRow label={tr("Switch every")}>
              <Picker<`${TickerInterval}`>
                label={tr("Switch every")}
                help={tr("How long each item stays before the next one")}
                items={TICKER_INTERVALS.map((interval) => ({ id: `${interval}` as const, title: tickerIntervalTitle(interval, currentLanguage()) }))}
                selected={`${settings.notchPreview.interval}`}
                onSelect={(id) => store.update((value) => ({ ...value, notchPreview: { ...value.notchPreview, interval: Number(id) as TickerInterval } }))}
                disabled={!previewOn}
              />
            </SettingsRow>
            {liveActivityKinds.map((kind) => {
              const module = tickerKindModule(kind);
              const moduleOn = module === undefined || settings.modules.isEnabled(module);
              const title = tickerKindTitle(kind, catalog);
              return (
                <SettingsRow key={kind} label={title}>
                  <Toggle
                    isOn={previewKindEnabled(settings.notchPreview, kind)}
                    onChange={(on) => store.update((value) => ({ ...value, notchPreview: settingPreviewKind(value.notchPreview, kind, on) }))}
                    label={title}
                    help={
                      moduleOn
                        ? tr("Show this in the live activity")
                        : tr("Add %@ in Tabs to include this", module === undefined ? tr("its module") : catalog.descriptor(module).title)
                    }
                    disabled={!previewOn || !moduleOn}
                  />
                </SettingsRow>
              );
            })}
          </SettingsGroup>
        </>
      }
    >
      <SettingsGroup>
        <SettingsRow label={tr("Your name")} help={offersParty ? tr("Shown to friends in Party and used to greet you.") : tr("Used to greet you.")}>
          <TextField
            value={settings.displayName}
            onChange={(value) => store.update((current) => ({ ...current, displayName: [...value].slice(0, DISPLAY_NAME_MAX_LENGTH).join("") }))}
            label={tr("Your name")}
            placeholder={tr("Your name")}
            help={tr("Your name, up to %lld characters", DISPLAY_NAME_MAX_LENGTH)}
            width={160}
          />
        </SettingsRow>
        <SettingsRow
          label={tr("Start with Windows")}
          help={launchError === undefined ? tr("Opens %@ when you sign in. Off until you turn it on.", appName) : tr("Windows didn't accept the change. Try again from Settings > General.")}
        >
          <Toggle
            isOn={settings.launchAtLogin}
            onChange={(on) => void store.setLaunchAtLogin(on)}
            label={tr("Start with Windows")}
            help={tr("Open %@ automatically when you sign in to Windows", appName)}
          />
        </SettingsRow>
        <SettingsRow label={tr("Language")} help={tr("Follows the language Windows is set to.")}>
          <span className="settings-value kit-body kit-secondary">{languageName(currentLanguage())}</span>
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup>
        <SettingsRow label={tr("Open on hover")} help={tr("Opens the island when the pointer rests at the top center.")}>
          <Toggle
            isOn={settings.openOnHover}
            onChange={(on) => store.update((value) => ({ ...value, openOnHover: on }))}
            label={tr("Open on hover")}
            help={tr("Open the island after resting the pointer at the top of the screen")}
          />
        </SettingsRow>
        <SettingsRow label={tr("Show live activity")} help={tr("Meetings, music and timers in the closed pill.")}>
          <Toggle
            isOn={settings.notchPreview.isEnabled}
            onChange={(on) => store.update((value) => ({ ...value, notchPreview: { ...value.notchPreview, isEnabled: on } }))}
            label={tr("Show live activity")}
            help={tr("Show a small live preview in the closed pill")}
          />
        </SettingsRow>
        <SettingsRow label={tr("Hide in fullscreen")} help={tr("Steps aside while a video, game or app is fullscreen.")}>
          <Toggle
            isOn={settings.hideInFullscreen}
            onChange={(on) => store.update((value) => ({ ...value, hideInFullscreen: on }))}
            label={tr("Hide in fullscreen")}
            help={tr("Hide the island while an app is fullscreen on its display. The shortcut still opens it.")}
          />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup
        title={tr("Shortcut")}
        footer={tr("In the open island, arrow keys switch tabs, 1-9 jump to a tab, and Esc closes. On the closed pill, middle-click to see the next live activity.")}
      >
        <SettingsRow label={tr("Open and close the island")} help={tr("Works from any app. On Today, type right away to add a task.")} stacked>
          <span className="settings-hotkey">
            {!isDefaultHotkey && !recording && (
              <IconButton symbol="arrow.counterclockwise" size={24} help={tr("Restore %@", windowsLabel(DEFAULT_HOTKEY))} onClick={() => record(DEFAULT_HOTKEY)} />
            )}
            <HotkeyRecorder
              hotkey={settings.hotkey}
              onRecord={record}
              onRecordingChange={(on) => {
                setRecording(on);
                void store.suspendHotkey(on);
              }}
              conflict={conflict}
            />
          </span>
        </SettingsRow>
      </SettingsGroup>

      <ResetToDefaultsRow
        isAtDefaults={store.usesGeneralDefaults}
        help={tr("Put General back the way a new install has it. Start with Windows stays as it is.")}
        reset={() => store.resetGeneral()}
      />
    </SettingsPage>
  );
}
