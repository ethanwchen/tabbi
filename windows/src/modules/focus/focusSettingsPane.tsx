/*
 * Port of FocusSettingsPane: Settings > Focus, which Today and the Focus
 * tab both offer, since either can run the timer. What plays while the
 * focus timer runs: the blend, each layer's level, the volume with a
 * preview, and the playlist with its presets. Edits go straight to
 * `FocusController`, which saves them and applies sound changes live.
 * Windows has no Focus shortcuts, so the Do not disturb group says so and
 * opens Windows' notification settings instead of taking shortcut names.
 */

import { useEffect } from "react";
import { useStore } from "../../app/useStore";
import { FocusMix } from "../../core/focus/focusMix";
import { FOCUS_PLAYLIST_PRESETS, matchingPlaylistPreset, parseFocusPlaylist, presetSource } from "../../core/focus/focusPlaylist";
import { focusSoundDisplayName, focusSoundSymbolName, FOCUS_SOUNDS, type FocusSound } from "../../core/focus/focusSound";
import { joinSentences } from "../../core/formatting/sentences";
import { tr } from "../../core/localization/tr";
import { Icon } from "../../ui/kit/Icon";
import { Picker } from "../../ui/kit/Picker";
import { Pill } from "../../ui/kit/Pill";
import { SettingsGroup, SettingsRow } from "../../ui/kit/SettingsGroup";
import { TextField } from "../../ui/kit/TextField";
import { Tooltip } from "../../ui/kit/Tooltip";
import { TrackSlider } from "../../ui/kit/TrackSlider";
import { percent } from "../study/studySoundViews";
import type { FocusController } from "./focusController";
import "./focus.css";

const NONE = "none";

export function FocusSettingsPane({ controller }: { controller: FocusController }) {
  const { settings, isPreviewing, isFocusing } = useStore(controller);
  const mix = settings.mix;
  useEffect(() => () => controller.setPreviewing(false), [controller]);
  useEffect(() => {
    if (mix.isOff) controller.setPreviewing(false);
  }, [controller, mix.isOff]);
  const previewHelp = isFocusing
    ? tr("Already playing: focus is running")
    : mix.isOff
      ? tr("Pick a sound to preview it")
      : isPreviewing
        ? tr("Stop the preview")
        : tr("Listen to %@", mix.summary);
  const status = playlistStatus(settings.playlistText);
  const presetItems = [
    ...FOCUS_PLAYLIST_PRESETS.map((preset) => ({ id: preset.link, title: preset.name, caption: `${preset.curator} · ${presetSource(preset) === "spotify" ? "Spotify" : "Apple Music"}` })),
    ...(settings.playlistText.length > 0 ? [{ id: NONE, title: tr("None") }] : []),
  ];
  return (
    <div className="settings-page">
      <SettingsGroup title={tr("Focus sound")} footer={tr("Blend up to three, or pick none for silence. Made on your PC; fades in with focus and out at your break.")}>
        <div className="focus-settings-chips" role="group" aria-label={tr("Focus sound")}>
          {FOCUS_SOUNDS.map((sound) => (
            <SoundChip key={sound} sound={sound} isOn={mix.contains(sound)} isEnabled={mix.contains(sound) || mix.canAddLayer} toggle={() => controller.toggleSound(sound)} />
          ))}
        </div>
        {mix.layers.length > 1 &&
          mix.layers.map((layer) => (
            <SettingsRow key={layer.sound} label={focusSoundDisplayName(layer.sound)}>
              <div className="focus-settings-slider">
                <Icon id={focusSoundSymbolName(layer.sound)} size={12} className="kit-secondary" />
                <TrackSlider
                  value={layer.level}
                  label={tr("%@ level", focusSoundDisplayName(layer.sound))}
                  help={tr("%@ level in the blend", focusSoundDisplayName(layer.sound))}
                  valueText={percent(layer.level)}
                  onChange={(level) => controller.setLevel(level, layer.sound)}
                />
              </div>
            </SettingsRow>
          ))}
        <SettingsRow label={tr("Volume")}>
          <div className="focus-settings-slider">
            <Icon id="speaker.wave.2.fill" size={12} className="kit-secondary" />
            <TrackSlider value={settings.volume} label={tr("Volume")} help={tr("Focus sound volume")} valueText={percent(settings.volume)} onChange={(volume) => controller.setVolume(volume)} />
          </div>
          <Pill
            title={isPreviewing ? tr("Stop") : tr("Preview")}
            symbol={isPreviewing ? "stop.fill" : "play.fill"}
            help={previewHelp}
            disabled={mix.isOff || isFocusing}
            onClick={() => controller.setPreviewing(!isPreviewing)}
          />
        </SettingsRow>
      </SettingsGroup>

      <SettingsGroup title={tr("Music")} footer={tr("Windows doesn't let Tabbi start or pause a playlist with focus. Picking one opens it, and Tabbi remembers your pick.")}>
        <SettingsRow label={tr("Playlist")} stacked>
          <div className="focus-settings-playlist">
            <TextField
              value={settings.playlistText}
              onChange={(text) => controller.setPlaylistText(text)}
              label={tr("Playlist")}
              placeholder={tr("Spotify or Apple Music link")}
              help={tr("A Spotify link or URI, or an Apple Music link")}
              width={240}
            />
            <Picker
              items={presetItems}
              selected={matchingPlaylistPreset(settings.playlistText)?.link ?? NONE}
              onSelect={(id) => controller.setPlaylistText(id === NONE ? "" : id)}
              label={tr("Presets")}
              help={tr("Pick a cozy focus playlist")}
            />
          </div>
        </SettingsRow>
        {status !== undefined && (
          <SettingsRow label="">
            <Tooltip text={status.text}>
              <span className="focus-settings-status" data-warning={status.isWarning || undefined}>
                <Icon id={status.symbol} size={12} />
                <span>{status.text}</span>
              </span>
            </Tooltip>
          </SettingsRow>
        )}
        {settings.playlist !== undefined && status !== undefined && !status.isWarning && (
          <SettingsRow label={tr("Open %@", controller.playlistSourceName ?? "")}>
            <Pill title={tr("Open")} symbol="arrow.up.forward.app" help={tr("Open %@ in your browser", settings.playlist.kind === "spotify" ? "Spotify" : "Apple Music")} onClick={() => controller.openPlaylist()} />
          </SettingsRow>
        )}
      </SettingsGroup>

      <SettingsGroup title={tr("Do not disturb")} footer={tr("Turn it on yourself while you focus.")}>
        <SettingsRow label={tr("Not available on Windows")} help={tr("Windows doesn't let apps turn on Do not disturb. Turn it on yourself in Settings when you focus.")}>
          <Pill title={tr("Open Windows Settings")} symbol="bell.slash" help={tr("Open Windows Settings")} onClick={() => controller.openNotificationSettings()} />
        </SettingsRow>
      </SettingsGroup>
    </div>
  );
}

/** One focus sound as a toggleable tile in the blend grid. Port of SoundChip. */
function SoundChip({ sound, isOn, isEnabled, toggle }: { sound: FocusSound; isOn: boolean; isEnabled: boolean; toggle: () => void }) {
  const help = isOn ? tr("Remove from the blend") : !isEnabled ? tr("Blend up to %lld sounds; remove one first", FocusMix.maxLayers) : tr("Add to the blend");
  return (
    <Tooltip text={help}>
      <button type="button" className="focus-settings-chip" role="switch" aria-checked={isOn} disabled={!isEnabled} onClick={toggle}>
        <Icon id={focusSoundSymbolName(sound)} size={12} />
        <span className="focus-settings-chip-name">{focusSoundDisplayName(sound)}</span>
        {isOn && <Icon id="checkmark" size={10} />}
      </button>
    </Tooltip>
  );
}

/** What the playlist field's text means, or undefined while it is blank. Port of FocusSettingsPane.playlistStatus, without the Mac's library names. */
export function playlistStatus(text: string): { text: string; symbol: string; isWarning: boolean } | undefined {
  if (text.trim().length === 0) return undefined;
  const playlist = parseFocusPlaylist(text);
  const preset = matchingPlaylistPreset(text);
  if (playlist === undefined || playlist.kind === "musicLibrary") {
    return { text: tr("Not a Spotify or Apple Music link."), symbol: "exclamationmark.triangle.fill", isWarning: true };
  }
  if (playlist.kind === "spotify") {
    return {
      text: joinSentences([preset === undefined ? tr("Plays in Spotify.") : tr("%@ by %@, plays in Spotify.", preset.name, preset.curator), tr("Opens in your browser; play and pause stay with you.")]),
      symbol: "checkmark.circle.fill",
      isWarning: false,
    };
  }
  return {
    text: joinSentences([preset === undefined ? tr("Opens in Apple Music.") : tr("%@ opens in Apple Music.", preset.name), tr("Opens in your browser; play and pause stay with you.")]),
    symbol: "info.circle.fill",
    isWarning: false,
  };
}
