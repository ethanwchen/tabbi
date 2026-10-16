/*
 * Port of StudySoundViews: the one focus-sound button beside the deep focus
 * switch, and the in-island sound mixer it opens (blend up to three sounds
 * with their own levels, set the volume, keep saved blends, pick a study
 * playlist). Everything edits the shared focus settings, which crossfade
 * live while focusing. The Study tab and the Focus tab both open the mixer,
 * each in its own accent (the panel's `--accent`).
 *
 * Windows has no way for an app to script Spotify or Music, so the
 * playlist column says so in one line: a pick is remembered and opened in
 * the browser, and play and pause stay with the user. Do not disturb is
 * not a switch here either; the capsule opens Windows' notification
 * settings and its tooltip says why.
 */

import { useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from "react";
import { useStore } from "../../app/useStore";
import { FocusMix } from "../../core/focus/focusMix";
import { MAX_PRESET_NAME_LENGTH } from "../../core/focus/focusMixPreset";
import { FOCUS_PLAYLIST_PRESETS, matchingPlaylistPreset, type FocusPlaylistPreset } from "../../core/focus/focusPlaylist";
import { focusSoundDisplayName, focusSoundSymbolName, FOCUS_SOUNDS, type FocusSound } from "../../core/focus/focusSound";
import { currentLanguage, tr } from "../../core/localization/tr";
import { studySoundHelp, studySoundLabel } from "../../core/studyMethods/studySoundLabel";
import { CapsuleToggle } from "../../ui/kit/CapsuleToggle";
import { Card } from "../../ui/kit/Card";
import { Icon } from "../../ui/kit/Icon";
import { IconButton } from "../../ui/kit/IconButton";
import { MarqueeText } from "../../ui/kit/MarqueeText";
import { Tooltip } from "../../ui/kit/Tooltip";
import { TrackSlider } from "../../ui/kit/TrackSlider";
import { Spacing } from "../../ui/kit/tokens";
import type { FocusController } from "../focus/focusController";
import "./study.css";

/** `level` as a whole percent in the user's language, e.g. "45%". */
export function percent(level: number): string {
  return new Intl.NumberFormat(currentLanguage(), { style: "percent", maximumFractionDigits: 0 }).format(level);
}

/** The user's language's "A and B" for a list, the Mac's `.formatted(.list(type: .and))`. */
export function andList(parts: string[]): string {
  return new Intl.ListFormat(currentLanguage(), { type: "conjunction" }).format(parts);
}

/**
 * The one focus-sound button beside the deep focus switch: it names what
 * plays (a sound, a blend, a playlist) and opens the mixer, so the Timer
 * panel keeps a single control for sound. `isActive` is whether study blocks
 * play the sound; the button dims while it's off.
 */
export function StudySoundButton({ focus, isActive, openMixer }: { focus: FocusController; isActive: boolean; openMixer: () => void }) {
  const { settings } = useStore(focus);
  const label = studySoundLabel(settings);
  return (
    <CapsuleToggle
      className="study-sound-button"
      title={label.title}
      symbol={label.symbolName}
      trailingSymbol={label.addsPlaylist ? "music.note" : undefined}
      isOn={label.isOn}
      look="soft"
      muted={!isActive}
      help={studySoundHelp(settings, matchingPlaylistPreset(settings.playlistText)?.name, andList)}
      onClick={openMixer}
    />
  );
}

export interface StudySoundMixerProps {
  readonly focus: FocusController;
  readonly close: () => void;
}

/** The in-island sound mixer. Port of StudySoundMixer. */
export function StudySoundMixer({ focus, close }: StudySoundMixerProps) {
  const { settings, isPreviewing, isFocusing } = useStore(focus);
  const mix = settings.mix;
  /* A name too long for its tile in the user's language ("Braunrauschen") drops every tile's icon, as the Mac's ViewThatFits does. */
  const [showsIcons, setShowsIcons] = useState(true);
  useEffect(() => () => focus.setPreviewing(false), [focus]);
  const previewHelp = isFocusing
    ? tr("Already playing during focus")
    : mix.isOff
      ? tr("Pick a sound to preview it")
      : isPreviewing
        ? tr("Stop the preview")
        : tr("Listen to %@", mix.summary);
  return (
    <div className="study-mixer">
      <div className="study-mixer-header kit-caption">
        <span className="kit-tertiary">{tr("Focus sound")}</span>
        <MarqueeText className="study-mixer-summary kit-secondary" text={mix.summary} />
        <span className="study-spacer" />
        <CapsuleToggle
          title={tr("Do not disturb")}
          symbol="bell.slash"
          isOn={false}
          help={tr("Windows doesn't let apps turn on Do not disturb. Turn it on yourself in Settings when you focus.")}
          onClick={() => focus.openNotificationSettings()}
        />
        <IconButton
          symbol={isPreviewing ? "stop.fill" : "play.fill"}
          help={previewHelp}
          disabled={mix.isOff || isFocusing}
          onClick={() => focus.setPreviewing(!isPreviewing)}
        />
        <IconButton symbol="xmark" help={tr("Back to the timer")} onClick={close} />
      </div>
      <div className="study-mixer-body">
        <Card padding={Spacing.s} className="study-mixer-blend">
          <div className="study-mixer-blend-header">
            <span className="kit-caption kit-tertiary">{tr("Blend")}</span>
            <span className="study-spacer" />
            <StudyMixPresetRow focus={focus} />
          </div>
          <div className="study-mixer-tiles">
            {FOCUS_SOUNDS.map((sound) => (
              <StudyMixTile
                key={sound}
                sound={sound}
                level={mix.level(sound)}
                canAdd={mix.canAddLayer}
                showsIcon={showsIcons}
                onOverflow={() => setShowsIcons(false)}
                toggle={() => focus.toggleSound(sound)}
                setLevel={(level) => focus.setLevel(level, sound)}
              />
            ))}
          </div>
          <span className="study-spacer" />
          <div className="study-mixer-volume" data-disabled={mix.isOff || undefined}>
            <Icon id="speaker.wave.2.fill" size={9} className="kit-tertiary" />
            <StudyLevelSlider level={settings.volume} name={tr("Volume")} help={tr("Volume %@", percent(settings.volume))} disabled={mix.isOff} onChange={(level) => focus.setVolume(level)} />
            <span className="study-mixer-percent kit-caption kit-secondary">{percent(settings.volume)}</span>
          </div>
        </Card>
        <Card padding={Spacing.s} className="study-mixer-playlist">
          <StudyPlaylistList focus={focus} />
        </Card>
      </div>
    </div>
  );
}

/**
 * The saved blends: three tiny chips beside "Blend". An empty slot (+)
 * saves the current blend with one tap; a preset applies with a tap, and a
 * long press or right-click renames or deletes it. The chip of the preset
 * playing now is lit.
 */
function StudyMixPresetRow({ focus }: { focus: FocusController }) {
  const { settings } = useStore(focus);
  const [renaming, setRenaming] = useState<number | undefined>(undefined);
  const [draft, setDraft] = useState("");
  const presets = settings.presets;
  const active = presets.slotMatching(settings.mix);
  const commit = () => {
    if (renaming === undefined) return;
    focus.renamePreset(renaming, draft);
    setRenaming(undefined);
  };
  return (
    <div className="study-presets">
      {presets.slots.map((preset, slot) => {
        if (renaming === slot) {
          return (
            <StudyPresetRenameField
              key={slot}
              draft={draft}
              setDraft={(text) => setDraft(Array.from(text).slice(0, MAX_PRESET_NAME_LENGTH).join(""))}
              commit={commit}
              cancel={() => setRenaming(undefined)}
              remove={() => {
                setRenaming(undefined);
                focus.deletePreset(slot);
              }}
            />
          );
        }
        if (preset !== undefined) {
          return (
            <StudyMixPresetChip
              key={slot}
              name={preset.name}
              isOn={slot === active}
              help={tr("Play %@. Long-press or right-click to rename or delete", preset.mix.summary)}
              apply={() => focus.applyPreset(slot)}
              rename={() => {
                setDraft(preset.name);
                setRenaming(slot);
              }}
            />
          );
        }
        const canSave = !settings.mix.isOff;
        return (
          <Tooltip key={slot} text={canSave ? tr("Save this blend as a preset") : tr("Pick a sound, then save the blend here")}>
            <button type="button" className="study-preset-save" aria-label={tr("Save this blend as a preset")} disabled={!canSave} onClick={() => focus.savePreset(slot)}>
              <Icon id="plus" size={8} />
            </button>
          </Tooltip>
        );
      })}
    </div>
  );
}

function StudyPresetRenameField({
  draft,
  setDraft,
  commit,
  cancel,
  remove,
}: {
  draft: string;
  setDraft: (text: string) => void;
  commit: () => void;
  cancel: () => void;
  remove: () => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => input.current?.focus(), []);
  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") commit();
    else if (event.key === "Escape") cancel();
    else return;
    event.preventDefault();
  };
  return (
    <span className="study-preset-rename">
      <input ref={input} className="study-preset-rename-input" value={draft} aria-label={tr("Rename")} onChange={(event) => setDraft(event.target.value)} onBlur={commit} onKeyDown={onKeyDown} />
      <IconButton symbol="trash" size={16} help={tr("Delete this preset")} onClick={remove} onPointerDown={(event) => event.preventDefault()} />
    </span>
  );
}

/** How long a press holds before it means "rename", in milliseconds. */
const LONG_PRESS_MS = 500;

/** A saved blend: its name in a capsule, lit while it is the blend playing. */
function StudyMixPresetChip({ name, isOn, help, apply, rename }: { name: string; isOn: boolean; help: string; apply: () => void; rename: () => void }) {
  const timer = useRef<number | undefined>(undefined);
  const held = useRef(false);
  const press = (event: PointerEvent<HTMLButtonElement>) => {
    if (event.button !== 0) return;
    held.current = false;
    timer.current = window.setTimeout(() => {
      held.current = true;
      rename();
    }, LONG_PRESS_MS);
  };
  const release = () => {
    window.clearTimeout(timer.current);
  };
  return (
    <CapsuleToggle
      className="study-preset-chip"
      userText
      title={name}
      isOn={isOn}
      height={18}
      help={help}
      aria-label={tr("Preset %@", name)}
      onClick={() => {
        if (!held.current) apply();
      }}
      onPointerDown={press}
      onPointerUp={release}
      onPointerLeave={release}
      onPointerCancel={release}
      onContextMenu={(event) => {
        event.preventDefault();
        rename();
      }}
    />
  );
}

/** One sound in the blend: tap to add or remove it; while it's in the mix a level slider sits underneath. */
function StudyMixTile({
  sound,
  level,
  canAdd,
  showsIcon,
  onOverflow,
  toggle,
  setLevel,
}: {
  sound: FocusSound;
  level: number | undefined;
  canAdd: boolean;
  showsIcon: boolean;
  /** Called when the name does not fit beside its icon. */
  onOverflow: () => void;
  toggle: () => void;
  setLevel: (level: number) => void;
}) {
  const isOn = level !== undefined;
  const button = useRef<HTMLButtonElement>(null);
  useLayoutEffect(() => {
    if (!showsIcon) return;
    const measure = () => {
      const outer = button.current?.querySelector<HTMLElement>(".kit-marquee");
      const line = button.current?.querySelector<HTMLElement>(".kit-marquee-line");
      if (outer && line && line.scrollWidth > outer.clientWidth + 0.5) onOverflow();
    };
    measure();
    /* The web font may land after the first layout. */
    if (typeof document !== "undefined" && "fonts" in document) void document.fonts.ready.then(measure);
  }, [showsIcon, onOverflow, sound]);
  const isEnabled = isOn || canAdd;
  const name = focusSoundDisplayName(sound);
  const help = isOn ? tr("Remove %@ from the blend", name) : !isEnabled ? tr("Blend up to %lld sounds; remove one first", FocusMix.maxLayers) : tr("Add %@ to the blend", name);
  return (
    <div className="study-mix-tile" data-on={isOn} data-enabled={isEnabled}>
      <Tooltip text={help}>
        <button ref={button} type="button" className="study-mix-tile-name" role="switch" aria-checked={isOn} disabled={!isEnabled} onClick={toggle}>
          {showsIcon && <Icon id={focusSoundSymbolName(sound)} size={10} className="study-mix-tile-icon" />}
          <MarqueeText text={name} className="study-mix-tile-title" />
        </button>
      </Tooltip>
      <div className="study-mix-tile-level" data-shown={isOn}>
        <StudyLevelSlider level={level ?? 0} name={tr("%@ level", name)} help={tr("%@ level %@", name, percent(level ?? 0))} disabled={!isOn} onChange={setLevel} />
      </div>
    </div>
  );
}

/** A level in the mixer (the volume, or one sound's level): the shared `TrackSlider` in the panel's accent. */
function StudyLevelSlider({ level, name, help, disabled = false, onChange }: { level: number; name: string; help: string; disabled?: boolean; onChange: (level: number) => void }) {
  return <TrackSlider value={level} help={help} label={name} valueText={percent(level)} height={10} disabled={disabled} onChange={onChange} />;
}

/** Rows that fit under the header in the mixer's playlist column. */
const PLAYLIST_ROW_COUNT = 6;

/**
 * The study playlist presets. Picking one remembers it and opens it in the
 * browser; tapping the one in use forgets it. A link typed in Settings that
 * isn't a preset shows on top as "Your playlist". One row on top says what
 * Windows can't do: start or pause it with focus.
 */
function StudyPlaylistList({ focus }: { focus: FocusController }) {
  const { settings } = useStore(focus);
  const text = settings.playlistText;
  const current = matchingPlaylistPreset(text);
  const hasCustom = current === undefined && settings.playlist !== undefined;
  const presetCount = PLAYLIST_ROW_COUNT - 1 - (hasCustom ? 1 : 0);
  return (
    <div className="study-playlist">
      <span className="kit-caption kit-tertiary study-playlist-title">{tr("Playlist")}</span>
      <Tooltip text={tr("Windows doesn't let Tabbi start or pause a playlist with focus. Picking one opens it, and Tabbi remembers your pick.")}>
        <div className="study-playlist-note kit-caption" role="note">
          <Icon id="info.circle" size={9} className="study-playlist-note-icon" />
          <span>{tr("Opens in your browser; play and pause stay with you.")}</span>
        </div>
      </Tooltip>
      {hasCustom && (
        <StudyPlaylistRow
          name={tr("Your playlist")}
          detail={focus.playlistSourceName ?? ""}
          isOn
          help={tr("Play your playlist now. It's the link from the Focus options in Settings > Tabs; picking a preset replaces it")}
          action={() => focus.choosePlaylist(text)}
        />
      )}
      {FOCUS_PLAYLIST_PRESETS.slice(0, presetCount).map((preset: FocusPlaylistPreset) => {
        const isOn = preset === current;
        return (
          <StudyPlaylistRow
            key={preset.link}
            name={preset.name}
            detail={preset.curator}
            isOn={isOn}
            help={isOn ? tr("Forget %@; Tabbi won't open it again", preset.name) : tr("Open %@ (%@) now and remember it", preset.name, preset.curator)}
            action={() => focus.choosePlaylist(isOn ? "" : preset.link)}
          />
        );
      })}
    </div>
  );
}

function StudyPlaylistRow({ name, detail, isOn, help, action }: { name: string; detail: string; isOn: boolean; help: string; action: () => void }) {
  return (
    <Tooltip text={help}>
      <button type="button" className="study-playlist-row kit-caption" role="switch" aria-checked={isOn} onClick={action}>
        <Icon id={isOn ? "checkmark.circle.fill" : "circle"} size={9} className="study-playlist-check" />
        <MarqueeText text={name} className="study-playlist-name" userText />
        <span className="study-playlist-detail kit-tertiary">{detail}</span>
      </button>
    </Tooltip>
  );
}
