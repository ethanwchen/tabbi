/*
 * Port of FocusController: runs focus mode. It follows the focus timer (and
 * the Study timer when its deep focus is on) and performs what the core's
 * `FocusSession` decides: the focus sound starts with a focus phase and
 * fades out at a break, pause or stop. One per app (`focusMode(context)`),
 * because the focus timer, Study, the Focus settings pane and kit defaults
 * all need it and none of them owns the others. It also owns the persisted
 * `FocusSettings`, so a change from Settings applies at once: volume and
 * sounds update live while focusing (crossfading), the rest on the next
 * focus phase.
 *
 * Windows differences, each shown plainly in the views: no app may switch
 * Do not disturb, so the switch is not offered and the saved value is never
 * acted on (the shortcut actions are dropped); and no app may start or
 * pause Spotify or Music, so a playlist is remembered and opened in the
 * browser when the user picks it, never started or paused with a phase.
 *
 * Inert in demo and snapshot runs: it shows sample settings and never plays
 * sound, opens a link or saves.
 */

import { Store } from "../../app/store";
import { FocusMix } from "../../core/focus/focusMix";
import { FocusMixPreset, FocusMixPresets } from "../../core/focus/focusMixPreset";
import { playlistSource, type FocusPlaylist } from "../../core/focus/focusPlaylist";
import { combinedFocusActivity, FocusSession, timerFocusActivity, type FocusActivity, type FocusSessionAction } from "../../core/focus/focusSession";
import { FocusSettings } from "../../core/focus/focusSettings";
import { FocusSettingsRepository } from "../../core/focus/focusSettingsRepository";
import type { FocusTimer } from "../../core/focus/focusTimer";
import type { KitDefaults } from "../../core/kits/kitManifest";
import type { FocusSoundEngine } from "../../ui/audio/focusSoundEngine";
import type { ModulePreferences } from "./modulePreferences";

/** Port of FocusActivitySource: a timer that can turn focus mode on. */
export type FocusActivitySource = "focusTimer" | "study";

export interface FocusModeState {
  readonly settings: FocusSettings;
  /** True during a focus phase (the sound is playing). */
  readonly isFocusing: boolean;
  /** True while the mixer or Settings previews the sound outside a focus phase. */
  readonly isPreviewing: boolean;
}

export interface FocusControllerOptions {
  /** False in demo and snapshot runs, where focus mode only shows sample settings. */
  readonly isLive: boolean;
  readonly preferences: ModulePreferences;
  /** The sound engine, made on first use; undefined in a snapshot run. */
  readonly soundEngine: () => FocusSoundEngine | undefined;
  /** Opens a web link in the user's browser (or Spotify, which claims its links). */
  readonly openLink: (url: string) => void;
}

/** The web link that opens a playlist: Spotify's `open.spotify.com` page for a URI, the catalog page for Apple Music; undefined for a library name, which only the Mac can play. */
export function playlistLink(playlist: FocusPlaylist): string | undefined {
  switch (playlist.kind) {
    case "spotify": {
      const [, kind, id] = playlist.uri.split(":");
      return kind === undefined || id === undefined ? undefined : `https://open.spotify.com/${kind}/${id}`;
    }
    case "appleMusicLink":
      return playlist.url;
    case "musicLibrary":
      return undefined;
  }
}

export class FocusController extends Store<FocusModeState> {
  /** False in demo and snapshot runs. */
  readonly isLive: boolean;
  /** Windows has no supported way for an app to switch Do not disturb, so the switch is never offered. */
  readonly offersDoNotDisturb = false;

  private readonly repository: FocusSettingsRepository;
  private readonly preferences: ModulePreferences;
  private readonly soundEngine: () => FocusSoundEngine | undefined;
  private readonly openLink: (url: string) => void;
  private readonly session = new FocusSession();
  /** What each timer last asked for; focus mode follows the strongest. */
  private readonly activities = new Map<FocusActivitySource, FocusActivity>();
  private requestedActivity: FocusActivity = "idle";

  constructor(options: FocusControllerOptions) {
    super({ settings: options.isLive ? FocusSettings.default : FocusController.sampleSettings, isFocusing: false, isPreviewing: false });
    this.isLive = options.isLive;
    this.preferences = options.preferences;
    this.repository = new FocusSettingsRepository(options.preferences.defaults);
    this.soundEngine = options.soundEngine;
    this.openLink = options.openLink;
    if (!this.isLive) return;
    void options.preferences.ready.then(() => this.reload());
    options.preferences.changed(() => this.reload());
  }

  /* Takes on the saved settings (at launch, or after another window saved them) without saving them again. */
  private reload(): void {
    const loaded = new FocusSettingsRepository(this.preferences.defaults).load();
    const old = this.state.settings;
    if (loaded.equals(old)) return;
    this.setState({ settings: loaded });
    this.applyLiveSound(old, loaded);
  }

  get settings(): FocusSettings {
    return this.state.settings;
  }

  get isFocusing(): boolean {
    return this.state.isFocusing;
  }

  get isPreviewing(): boolean {
    return this.state.isPreviewing;
  }

  /** Whether focus phases turn on Do Not Disturb, as views should show it: never on Windows. */
  get doNotDisturb(): boolean {
    return false;
  }

  /** True while a focus phase has Do Not Disturb on; never on Windows, where Tabbi cannot switch it. */
  get holdsDoNotDisturb(): boolean {
    return false;
  }

  // MARK: - Timer

  /** Call whenever the focus timer changes. Starts focus mode when a focus phase starts running, and ends it on a break, pause or reset. */
  timerChanged(timer: FocusTimer): void {
    this.activityChanged(timerFocusActivity(timer), "focusTimer");
  }

  /** Call whenever another timer that drives focus mode changes (Study with deep focus on). Focus mode stays on while any timer is focusing. */
  activityChanged(activity: FocusActivity, source: FocusActivitySource): void {
    if (!this.isLive) return;
    this.activities.set(source, activity);
    const combined = combinedFocusActivity(this.activities.values());
    if (combined === this.requestedActivity) return;
    this.requestedActivity = combined;
    this.transition(combined);
  }

  private transition(activity: FocusActivity): void {
    /* Do Not Disturb is never acted on here, so the session never asks for a shortcut. */
    const settings = this.state.settings.with({ doNotDisturb: false });
    const actions = this.session.transition(activity, settings, () => false);
    this.setState({ isFocusing: this.session.isFocusing });
    for (const action of actions) this.perform(action);
    /* A sound picked mid-phase wasn't in the captured settings, so the session doesn't know to stop it; make sure it stops with the phase. */
    if (!this.state.isFocusing && !this.state.isPreviewing) this.soundEngine()?.stop();
  }

  private perform(action: FocusSessionAction): void {
    switch (action.kind) {
      case "startSound":
        this.setState({ isPreviewing: false });
        this.playSound(action.mix, action.volume);
        break;
      case "stopSound":
        if (!this.state.isPreviewing) this.soundEngine()?.stop();
        break;
      case "runShortcut":
      case "playPlaylist":
      case "resumePlaylist":
      case "pausePlaylist":
        /* Windows has no shortcuts that switch Do not disturb and no way to script a music app. */
        break;
    }
  }

  // MARK: - Settings

  /** Replaces the settings with `change`'s result, saves them, and applies a sound or volume change live while focusing or previewing. */
  updateSettings(change: (settings: FocusSettings) => FocusSettings): void {
    const old = this.state.settings;
    const next = change(old);
    if (next.equals(old)) return;
    this.setState({ settings: next });
    if (!this.isLive) return;
    this.repository.save(next);
    this.preferences.save();
    this.applyLiveSound(old, next);
  }

  private applyLiveSound(old: FocusSettings, next: FocusSettings): void {
    if (!this.state.isFocusing && !this.state.isPreviewing) return;
    if (!next.mix.equals(old.mix) || next.volume !== old.volume) this.playSound(next.mix, next.volume);
  }

  /** Adds or removes a sound from the blend; nothing happens past three. */
  toggleSound(sound: FocusMix["layers"][number]["sound"]): void {
    this.updateSettings((settings) => settings.with({ mix: settings.mix.toggled(sound).mix }));
  }

  setLevel(level: number, sound: FocusMix["layers"][number]["sound"]): void {
    this.updateSettings((settings) => settings.with({ mix: settings.mix.withLevel(level, sound) }));
  }

  setVolume(volume: number): void {
    this.updateSettings((settings) => settings.with({ volume }));
  }

  setPlaylistText(text: string): void {
    this.updateSettings((settings) => settings.with({ playlistText: text }));
  }

  /** Switches to the saved blend in `slot`. */
  applyPreset(slot: number): void {
    this.updateSettings((settings) => settings.applyingPreset(slot));
  }

  /** Saves the current blend into the empty `slot`. */
  savePreset(slot: number): void {
    this.updateSettings((settings) => settings.with({ presets: settings.presets.saving(settings.mix, slot) ?? settings.presets }));
  }

  renamePreset(slot: number, name: string): void {
    this.updateSettings((settings) => settings.with({ presets: settings.presets.renaming(slot, name) }));
  }

  deletePreset(slot: number): void {
    this.updateSettings((settings) => settings.with({ presets: settings.presets.deleting(slot) }));
  }

  /** A kit's focus sound, applied when the user switches to or resets the kit. */
  applyKit(kit: KitDefaults): void {
    this.updateSettings((settings) => settings.applyingKit(kit));
  }

  /** Puts back settings saved before a kit switch, for undo. */
  restore(settings: FocusSettings): void {
    this.updateSettings(() => settings);
  }

  // MARK: - Playlist

  /**
   * The user picked a playlist in the mixer (`text` is its link, or empty to
   * forget it). The pick is saved like any setting and, since Windows cannot
   * start it for them, opened in the browser right away so the click still
   * does something. Inert in demo and snapshot runs, which only show the pick.
   */
  choosePlaylist(text: string): void {
    this.setPlaylistText(text);
    if (!this.isLive) return;
    const playlist = this.state.settings.playlist;
    const link = playlist === undefined ? undefined : playlistLink(playlist);
    if (link !== undefined) this.openLink(link);
  }

  /** Opens Windows' notification settings, where the user can turn on Do not disturb themselves. */
  openNotificationSettings(): void {
    this.openLink("ms-settings:notifications");
  }

  /** Opens the saved playlist again. */
  openPlaylist(): void {
    this.choosePlaylist(this.state.settings.playlistText);
  }

  /** The app the saved playlist belongs to, for a label. */
  get playlistSourceName(): string | undefined {
    const playlist = this.state.settings.playlist;
    if (playlist === undefined) return undefined;
    return playlistSource(playlist) === "spotify" ? "Spotify" : "Apple Music";
  }

  // MARK: - Preview

  /** Plays the current sound so the user can hear it from the mixer or Settings. Ignored while focusing, since the sound is already playing. */
  setPreviewing(previewing: boolean): void {
    if (!this.isLive || this.state.isFocusing || previewing === this.state.isPreviewing) return;
    this.setState({ isPreviewing: previewing });
    if (previewing) this.playSound(this.state.settings.mix, this.state.settings.volume);
    else this.soundEngine()?.stop();
  }

  private playSound(mix: FocusMix, volume: number): void {
    /* An Off mix never needs the engine; don't build one just to stay silent. */
    const engine = this.soundEngine();
    if (engine === undefined || mix.isOff) {
      engine?.setMix(mix);
      return;
    }
    engine.setVolume(volume);
    engine.setMix(mix);
    engine.play();
  }

  /** What demo mode and snapshots show: a cozy blend saved as a preset (with a second preset and a free slot beside it) and a playlist. */
  static readonly sampleMix = new FocusMix([{ sound: "rain" }, { sound: "fireplace", level: 0.6 }]);

  static readonly sampleSettings = new FocusSettings({
    mix: FocusController.sampleMix,
    presets: new FocusMixPresets([new FocusMixPreset("Cozy", FocusController.sampleMix), new FocusMixPreset("Deep work", FocusMix.single("brown"))]),
    volume: 0.45,
    playlistText: "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM",
    doNotDisturb: true,
  });
}
