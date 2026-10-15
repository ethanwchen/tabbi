import { focusSoundDisplayName, focusSoundSymbolName } from "../focus/focusSound";
import type { FocusSettings } from "../focus/focusSettings";
import { tr } from "../localization/tr";

/**
 * Port of StudySoundLabel: what the Study tab's one sound button says about
 * the shared focus settings (the same sound the Focus timer plays).
 */
export interface StudySoundLabel {
  /** "Sound" when nothing plays, the sound's name, "2 sounds" for a blend, or "Playlist" for a playlist alone. */
  readonly title: string;
  /** The Mac's SF Symbol name, which the icon table maps to a Windows icon. */
  readonly symbolName: string;
  /** True when a sound or a playlist plays with focus, so the button shows in the accent. */
  readonly isOn: boolean;
  /** True when a playlist starts alongside a sound. */
  readonly addsPlaylist: boolean;
}

export function studySoundLabel(settings: FocusSettings): StudySoundLabel {
  const layers = settings.mix.layers;
  const hasPlaylist = settings.playlist !== undefined;
  let title: string;
  let symbolName: string;
  const first = layers[0];
  if (layers.length === 0) {
    title = hasPlaylist ? tr("Playlist") : tr("Sound");
    symbolName = hasPlaylist ? "music.note.list" : "speaker.slash";
  } else if (layers.length === 1 && first !== undefined) {
    title = focusSoundDisplayName(first.sound);
    symbolName = focusSoundSymbolName(first.sound);
  } else {
    title = tr("%lld sounds", layers.length);
    symbolName = "slider.horizontal.3";
  }
  return { title, symbolName, isOn: layers.length > 0 || hasPlaylist, addsPlaylist: layers.length > 0 && hasPlaylist };
}

const andList = (parts: string[]): string => new Intl.ListFormat("en", { type: "conjunction" }).format(parts);

/**
 * The tooltip: what plays with focus, and that a click opens the mixer.
 * `formatList` joins the parts in the user's language ("A and B"); it
 * defaults to English, like the fixtures.
 */
export function studySoundHelp(
  settings: FocusSettings,
  playlistName: string | undefined,
  formatList: (parts: string[]) => string = andList,
): string {
  const parts: string[] = [];
  if (!settings.mix.isOff) parts.push(settings.mix.summary);
  if (settings.playlist !== undefined) parts.push(playlistName ?? tr("your playlist"));
  if (parts.length === 0) return tr("Pick a focus sound or a playlist");
  return tr("Plays %@ with focus. Click to change it", formatList(parts));
}
