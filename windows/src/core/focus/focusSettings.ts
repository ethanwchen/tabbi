import { kitModuleSettings, type KitDefaults } from "../kits/kitManifest";
import { MODULE_IDS } from "../modules/moduleId";
import { FocusMix } from "./focusMix";
import { FocusMixPresets } from "./focusMixPreset";
import { parseFocusPlaylist, type FocusPlaylist } from "./focusPlaylist";
import { isFocusSound, type FocusSound } from "./focusSound";

/** Suggested shortcut names on the Mac, kept so a synced settings file round-trips. */
export const SUGGESTED_ON_SHORTCUT = "Tabbi Focus On";
export const SUGGESTED_OFF_SHORTCUT = "Tabbi Focus Off";

const DEFAULT_VOLUME = 0.5;
/** `Float.greatestFiniteMagnitude`. */
const FLOAT_GREATEST_FINITE = 3.4028234663852886e38;

function clampVolume(volume: number): number {
  return Number.isFinite(volume) ? Math.fround(Math.min(Math.max(volume, 0), 1)) : DEFAULT_VOLUME;
}

export interface FocusSettingsInit {
  mix?: FocusMix;
  presets?: FocusMixPresets;
  volume?: number;
  playlistText?: string;
  doNotDisturb?: boolean;
  onShortcut?: string;
  offShortcut?: string;
}

/**
 * Port of FocusSettings: what to play and whether to turn on Do Not Disturb
 * while a focus phase runs. Everything is opt-in: the defaults play nothing
 * and leave Do Not Disturb alone, so an update never makes a session louder.
 * Immutable: `with` returns changed settings.
 */
export class FocusSettings {
  /** The generated focus sound. Empty means Off. */
  readonly mix: FocusMix;
  /** Blends the user saved by name. Kits never touch them. */
  readonly presets: FocusMixPresets;
  /** Master volume for the generated sound, 0...1. */
  readonly volume: number;
  /** The playlist field's raw text, kept as typed so the field round-trips exactly. */
  readonly playlistText: string;
  readonly doNotDisturb: boolean;
  /** Shortcut names the Mac runs when focus starts and ends; blank skips that step. */
  readonly onShortcut: string;
  readonly offShortcut: string;

  constructor(init: FocusSettingsInit = {}) {
    this.mix = init.mix ?? FocusMix.off;
    this.presets = init.presets ?? FocusMixPresets.empty;
    this.volume = clampVolume(init.volume ?? DEFAULT_VOLUME);
    this.playlistText = init.playlistText ?? "";
    this.doNotDisturb = init.doNotDisturb ?? false;
    this.onShortcut = init.onShortcut ?? SUGGESTED_ON_SHORTCUT;
    this.offShortcut = init.offShortcut ?? SUGGESTED_OFF_SHORTCUT;
  }

  static readonly default = new FocusSettings();

  with(changes: FocusSettingsInit): FocusSettings {
    return new FocusSettings({ ...this.init(), ...changes });
  }

  private init(): Required<FocusSettingsInit> {
    return {
      mix: this.mix,
      presets: this.presets,
      volume: this.volume,
      playlistText: this.playlistText,
      doNotDisturb: this.doNotDisturb,
      onShortcut: this.onShortcut,
      offShortcut: this.offShortcut,
    };
  }

  /** The playlist to start with focus, or undefined when the field is blank or unrecognizable. */
  get playlist(): FocusPlaylist | undefined {
    return parseFocusPlaylist(this.playlistText);
  }

  /** The shortcut to run when focus starts, or undefined when Do Not Disturb is off or the name is blank. */
  get activeOnShortcut(): string | undefined {
    return this.activeShortcut(this.onShortcut);
  }

  /** The shortcut to run when focus ends, under the same rules. */
  get activeOffShortcut(): string | undefined {
    return this.activeShortcut(this.offShortcut);
  }

  /** True when starting focus would do anything at all. */
  get hasEffect(): boolean {
    return !this.mix.isOff || this.playlist !== undefined || this.activeOnShortcut !== undefined || this.activeOffShortcut !== undefined;
  }

  /** These settings with a kit's focus sound applied; a kit without one keeps the current mix. */
  applyingKit(kit: KitDefaults): FocusSettings {
    const mix = kitFocusMix(kit);
    return mix === undefined ? this : this.with({ mix });
  }

  /** True when applying the kit's Focus section would leave these settings unchanged. */
  usesKitDefaults(kit: KitDefaults): boolean {
    return this.applyingKit(kit).equals(this);
  }

  /** Switches to the preset in `slot`; an empty slot changes nothing. */
  applyingPreset(slot: number): FocusSettings {
    const preset = this.presets.slots[slot];
    return preset === undefined ? this : this.with({ mix: preset.mix });
  }

  equals(other: FocusSettings): boolean {
    return (
      this.mix.equals(other.mix) &&
      this.presets.equals(other.presets) &&
      this.volume === other.volume &&
      this.playlistText === other.playlistText &&
      this.doNotDisturb === other.doNotDisturb &&
      this.onShortcut === other.onShortcut &&
      this.offShortcut === other.offShortcut
    );
  }

  private activeShortcut(name: string): string | undefined {
    if (!this.doNotDisturb) return undefined;
    const trimmed = name.trim();
    return trimmed.length === 0 ? undefined : trimmed;
  }

  toJSON(): Record<string, unknown> {
    return {
      mix: this.mix.toJSON(),
      presets: this.presets.toJSON(),
      volume: this.volume,
      playlistText: this.playlistText,
      doNotDisturb: this.doNotDisturb,
      onShortcut: this.onShortcut,
      offShortcut: this.offShortcut,
    };
  }

  /** Decodes with a fallback per field, so one bad or missing value never resets the rest. */
  static fromJSON(value: unknown): FocusSettings {
    const entry = typeof value === "object" && value !== null ? (value as Record<string, unknown>) : {};
    const text = (key: string): string | undefined => (typeof entry[key] === "string" ? entry[key] : undefined);
    const init: FocusSettingsInit = {};
    const mix = FocusMix.fromJSON(entry.mix);
    if (mix !== undefined) init.mix = mix;
    const presets = FocusMixPresets.fromJSON(entry.presets);
    if (presets !== undefined) init.presets = presets;
    /* Swift refuses a number past Float's range, so the volume falls back instead of clamping to 1. */
    if (typeof entry.volume === "number" && Math.abs(entry.volume) <= FLOAT_GREATEST_FINITE) init.volume = entry.volume;
    const playlistText = text("playlistText");
    if (playlistText !== undefined) init.playlistText = playlistText;
    if (typeof entry.doNotDisturb === "boolean") init.doNotDisturb = entry.doNotDisturb;
    const onShortcut = text("onShortcut");
    if (onShortcut !== undefined) init.onShortcut = onShortcut;
    const offShortcut = text("offShortcut");
    if (offShortcut !== undefined) init.offShortcut = offShortcut;
    return new FocusSettings(init);
  }
}

/**
 * Port of FocusSettings.kitMix(of:): the focus sound a kit sets in its Focus
 * section (`moduleSettings.focus.sounds`: a list of `sound` and an optional
 * `level` from 0 to 1, default 1), with unknown sounds skipped. Undefined when
 * the kit sets no sound; an empty list turns the sound off. The section is
 * read leniently: anything malformed is skipped rather than refused.
 */
export function kitFocusMix(kit: KitDefaults): FocusMix | undefined {
  const focusSection = kitModuleSettings(kit, MODULE_IDS.focus);
  if (typeof focusSection !== "object" || focusSection === null) return undefined;
  const sounds = (focusSection as Record<string, unknown>).sounds;
  if (!Array.isArray(sounds)) return undefined;
  const layers: { sound: FocusSound; level: number }[] = [];
  for (const entry of sounds) {
    if (typeof entry !== "object" || entry === null) continue;
    const { sound, level } = entry as Record<string, unknown>;
    if (!isFocusSound(sound)) continue;
    const value = typeof level === "number" ? level : 1;
    layers.push({ sound, level: Number.isFinite(value) ? value : 1 });
  }
  return new FocusMix(layers);
}
