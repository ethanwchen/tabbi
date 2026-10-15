import type { FocusTimer } from "./focusTimer";
import type { FocusMix } from "./focusMix";
import {
  playlistSource,
  playlistStartsPlayback,
  playlistsEqual,
  type FocusPlaylist,
  type MediaSource,
  type PlayerState,
} from "./focusPlaylist";
import type { FocusSettings } from "./focusSettings";

/**
 * Port of FocusActivity: what a timer means for focus mode right now.
 * `focusing`: a focus phase is counting down, sound and Do Not Disturb on.
 * `interrupted`: mid-session but not focusing (a break, or paused).
 * `idle`: no session.
 */
export type FocusActivity = "focusing" | "interrupted" | "idle";

/** Port of FocusActivity(_ timer:): reads the activity off the Pomodoro. */
export function timerFocusActivity(timer: FocusTimer): FocusActivity {
  switch (timer.runState.kind) {
    case "running":
      return timer.phase === "focus" ? "focusing" : "interrupted";
    case "paused":
      return "interrupted";
    case "idle":
      return "idle";
  }
}

/**
 * Port of FocusActivity.combined: one activity for several timers that can
 * drive focus mode at once. Focusing if any is, else interrupted if any is
 * mid-session, else idle, so ending one timer never turns off what another
 * still needs.
 */
export function combinedFocusActivity(activities: Iterable<FocusActivity>): FocusActivity {
  let result: FocusActivity = "idle";
  for (const activity of activities) {
    if (activity === "focusing") return "focusing";
    if (activity === "interrupted") result = "interrupted";
  }
  return result;
}

/** Port of FocusSessionAction: a side effect the app layer performs for focus mode. */
export type FocusSessionAction =
  /** Fade the generated sound in with this mix and volume. */
  | { readonly kind: "startSound"; readonly mix: FocusMix; readonly volume: number }
  /** Fade the generated sound out. */
  | { readonly kind: "stopSound" }
  | { readonly kind: "runShortcut"; readonly name: string }
  | { readonly kind: "playPlaylist"; readonly playlist: FocusPlaylist }
  /** Continue the playlist paused at the break, where it left off. */
  | { readonly kind: "resumePlaylist"; readonly source: MediaSource }
  | { readonly kind: "pausePlaylist"; readonly source: MediaSource };

/** Who controls the playlist's app during a session. */
type PlaylistControl =
  /** Not started by focus mode. */
  | { readonly kind: "none" }
  /** Asked to play, not yet seen playing; `autoPlays` is false when the link only opens the playlist. */
  | { readonly kind: "requested"; readonly source: MediaSource; readonly autoPlays: boolean }
  /** Seen playing what we started; paused when focus ends. */
  | { readonly kind: "playing"; readonly source: MediaSource }
  /** Paused at a break; the next focus phase resumes it. */
  | { readonly kind: "paused"; readonly playlist: FocusPlaylist }
  /** The user paused it. Hands off until the session ends. */
  | { readonly kind: "declined" };

/**
 * Port of FocusSession: decides what focus mode does as the timer moves
 * between phases. Pure: the app feeds it timer changes and what the music app
 * is doing, and performs the returned actions. Its rules:
 *
 * - Settings are captured when a focus phase starts, so editing them
 *   mid-phase cannot leave Do Not Disturb on or a playlist unpaused.
 * - The "off" shortcut only runs if the "on" shortcut ran.
 * - Never fight the user: a playlist starts only if that app is not already
 *   playing, and once our playlist was seen playing a manual pause hands it to
 *   the user until the session ends.
 * - A playlist paused at a break resumes where it left off in the next focus
 *   phase, unless the user played something there meanwhile.
 * - Picking a playlist in the mixer plays it right away (`choosePlaylist`).
 */
export class FocusSession {
  private activityValue: FocusActivity = "idle";
  private activeValue: FocusSettings | undefined;
  private playlist: PlaylistControl = { kind: "none" };
  private shortcutRan = false;

  get activity(): FocusActivity {
    return this.activityValue;
  }

  /** Settings captured when the current focus phase started. */
  get active(): FocusSettings | undefined {
    return this.activeValue;
  }

  /** True while a focus phase is applying its settings. */
  get isFocusing(): boolean {
    return this.activityValue === "focusing";
  }

  /**
   * Moves to `activity`. `settings` are the current settings, used only when
   * a focus phase starts. `isPlaying(source)` reports whether that music app
   * is playing right now.
   */
  transition(activity: FocusActivity, settings: FocusSettings, isPlaying: (source: MediaSource) => boolean): FocusSessionAction[] {
    if (activity === this.activityValue) return [];
    const wasFocusing = this.isFocusing;
    this.activityValue = activity;
    const actions: FocusSessionAction[] = [];
    if (wasFocusing) actions.push(...this.endFocus());
    if (activity === "focusing") actions.push(...this.startFocus(settings, isPlaying));
    if (activity === "idle") this.playlist = { kind: "none" };
    return actions;
  }

  /** Feeds an observed player state for `source`. A pause after we saw our playlist play is the user's choice. */
  observe(state: PlayerState, source: MediaSource): void {
    const control = this.playlist;
    if (control.kind === "requested" && control.source === source && state === "playing") {
      this.playlist = { kind: "playing", source };
    } else if (control.kind === "playing" && control.source === source && state !== "playing") {
      this.playlist = this.isFocusing ? { kind: "declined" } : { kind: "none" };
    } else if (control.kind === "paused" && playlistSource(control.playlist) === source && state !== "paused") {
      this.playlist = { kind: "none" };
    }
  }

  /**
   * The user picked the playlist in `settings` (or turned it off) from the
   * mixer. A pick plays now, even outside a focus phase; turning it off pauses
   * it only if focus mode started it.
   */
  choosePlaylist(settings: FocusSettings): FocusSessionAction[] {
    if (this.isFocusing && this.activeValue !== undefined) {
      this.activeValue = this.activeValue.with({ playlistText: settings.playlistText });
    }
    const actions: FocusSessionAction[] = [];
    const owned = this.ownedSource;
    const item = settings.playlist;
    if (item === undefined) {
      if (owned !== undefined) actions.push({ kind: "pausePlaylist", source: owned });
      this.playlist = { kind: "none" };
      return actions;
    }
    const source = playlistSource(item);
    if (owned !== undefined && owned !== source) actions.push({ kind: "pausePlaylist", source: owned });
    actions.push(this.startPlaylist(item));
    return actions;
  }

  private startPlaylist(item: FocusPlaylist): FocusSessionAction {
    const source = playlistSource(item);
    if (this.playlist.kind === "paused" && playlistsEqual(this.playlist.playlist, item)) {
      this.playlist = { kind: "requested", source, autoPlays: true };
      return { kind: "resumePlaylist", source };
    }
    this.playlist = { kind: "requested", source, autoPlays: playlistStartsPlayback(item) };
    return { kind: "playPlaylist", playlist: item };
  }

  /* The app focus mode started playing in, and so may pause. */
  private get ownedSource(): MediaSource | undefined {
    const control = this.playlist;
    if (control.kind === "requested" && control.autoPlays) return control.source;
    if (control.kind === "playing") return control.source;
    return undefined;
  }

  private startFocus(settings: FocusSettings, isPlaying: (source: MediaSource) => boolean): FocusSessionAction[] {
    this.activeValue = settings;
    const actions: FocusSessionAction[] = [];
    if (!settings.mix.isOff) actions.push({ kind: "startSound", mix: settings.mix, volume: settings.volume });
    const item = settings.playlist;
    if (item !== undefined && this.playlist.kind !== "declined") {
      const source = playlistSource(item);
      const requested = this.playlist.kind === "requested" && this.playlist.source === source;
      if (!isPlaying(source) && !requested) actions.push(this.startPlaylist(item));
    }
    const on = settings.activeOnShortcut;
    if (on !== undefined) {
      this.shortcutRan = true;
      actions.push({ kind: "runShortcut", name: on });
    }
    return actions;
  }

  private endFocus(): FocusSessionAction[] {
    const settings = this.activeValue;
    if (settings === undefined) return [];
    this.activeValue = undefined;
    const actions: FocusSessionAction[] = [];
    if (!settings.mix.isOff) actions.push({ kind: "stopSound" });
    const control = this.playlist;
    if (control.kind === "playing") {
      actions.push({ kind: "pausePlaylist", source: control.source });
      const item = settings.playlist;
      if (item !== undefined) this.playlist = { kind: "paused", playlist: item };
    } else if (control.kind === "requested") {
      /*
       * Never seen playing: if it auto-plays, pause it but start it fresh next
       * time; if it only opened, never pause music we did not see start.
       */
      if (control.autoPlays) actions.push({ kind: "pausePlaylist", source: control.source });
      this.playlist = { kind: "none" };
    }
    if (this.shortcutRan) {
      this.shortcutRan = false;
      const off = settings.activeOffShortcut;
      if (off !== undefined) actions.push({ kind: "runShortcut", name: off });
    }
    return actions;
  }
}
