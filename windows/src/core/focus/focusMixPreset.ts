import { tr } from "../localization/tr";
import { FocusMix } from "./focusMix";
import { focusSoundDisplayName } from "./focusSound";

/** Long enough for a word or two, short enough for a small chip. */
export const MAX_PRESET_NAME_LENGTH = 18;

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });

/** `name` trimmed and cut to `MAX_PRESET_NAME_LENGTH` characters, or undefined when nothing is left. */
export function cleanedPresetName(name: string): string | undefined {
  const trimmed = name.trim();
  if (trimmed.length === 0) return undefined;
  const kept = Array.from(graphemes.segment(trimmed), (part) => part.segment).slice(0, MAX_PRESET_NAME_LENGTH);
  return kept.join("").trim();
}

/**
 * The name a fresh preset gets: its loudest sound, plus how many others play
 * with it ("Rain +1"), so three presets still read apart at a glance.
 */
export function defaultPresetName(mix: FocusMix): string {
  let main = mix.layers[0];
  if (main === undefined) return tr("Off");
  /* Like Swift's max(by:), the first of equally loud layers wins. */
  for (const layer of mix.layers) if (layer.level > main.level) main = layer;
  const others = mix.layers.length - 1;
  const name = focusSoundDisplayName(main.sound);
  return others > 0 ? `${name} +${others}` : name;
}

/** Port of FocusMixPreset: a focus sound blend saved under a name. */
export class FocusMixPreset {
  readonly name: string;
  readonly mix: FocusMix;

  /** A blank name falls back to the default name; a long one is cut. */
  constructor(name: string, mix: FocusMix) {
    this.mix = mix;
    this.name = cleanedPresetName(name) ?? defaultPresetName(mix);
  }

  equals(other: FocusMixPreset): boolean {
    return this.name === other.name && this.mix.equals(other.mix);
  }

  toJSON(): { name: string; mix: ReturnType<FocusMix["toJSON"]> } {
    return { name: this.name, mix: this.mix.toJSON() };
  }

  static fromJSON(value: unknown): FocusMixPreset | undefined {
    if (typeof value !== "object" || value === null) return undefined;
    const entry = value as Record<string, unknown>;
    const mix = FocusMix.fromJSON(entry.mix);
    if (mix === undefined) return undefined;
    return new FocusMixPreset(typeof entry.name === "string" ? entry.name : "", mix);
  }
}

/**
 * Port of FocusMixPresets: `SLOT_COUNT` fixed slots, each empty or holding a
 * preset. Slots keep their place, so deleting the first preset leaves a gap
 * rather than moving the others under the pointer. A preset never holds an
 * Off mix. Immutable: changes return new slots.
 */
export class FocusMixPresets {
  static readonly slotCount = 3;

  /** Always `slotCount` long. */
  readonly slots: readonly (FocusMixPreset | undefined)[];

  /** Pads or cuts `slots` to `slotCount` and empties any slot whose mix is Off. */
  constructor(slots: readonly (FocusMixPreset | undefined)[] = []) {
    const kept = slots.slice(0, FocusMixPresets.slotCount).map((slot) => (slot !== undefined && !slot.mix.isOff ? slot : undefined));
    while (kept.length < FocusMixPresets.slotCount) kept.push(undefined);
    this.slots = kept;
  }

  static readonly empty = new FocusMixPresets();

  get isEmpty(): boolean {
    return this.slots.every((slot) => slot === undefined);
  }

  /** The first slot holding `mix` exactly, for marking the preset in use. */
  slotMatching(mix: FocusMix): number | undefined {
    if (mix.isOff) return undefined;
    const index = this.slots.findIndex((slot) => slot?.mix.equals(mix) === true);
    return index < 0 ? undefined : index;
  }

  /**
   * Saves `mix` into the empty `slot` under its default name. Undefined when
   * the slot is taken or out of range, or the mix is Off.
   */
  saving(mix: FocusMix, slot: number): FocusMixPresets | undefined {
    if (slot < 0 || slot >= this.slots.length || this.slots[slot] !== undefined || mix.isOff) return undefined;
    return this.replacing(slot, new FocusMixPreset("", mix));
  }

  /** Renames the preset in `slot`; a blank name restores the default. */
  renaming(slot: number, name: string): FocusMixPresets {
    const preset = this.slots[slot];
    if (preset === undefined) return this;
    return this.replacing(slot, new FocusMixPreset(name, preset.mix));
  }

  /** Empties `slot`. */
  deleting(slot: number): FocusMixPresets {
    if (slot < 0 || slot >= this.slots.length) return this;
    return this.replacing(slot, undefined);
  }

  private replacing(slot: number, preset: FocusMixPreset | undefined): FocusMixPresets {
    return new FocusMixPresets(this.slots.map((current, index) => (index === slot ? preset : current)));
  }

  equals(other: FocusMixPresets): boolean {
    return this.slots.every((slot, index) => {
      const theirs = other.slots[index];
      return slot === undefined || theirs === undefined ? slot === theirs : slot.equals(theirs);
    });
  }

  toJSON(): { slots: (ReturnType<FocusMixPreset["toJSON"]> | null)[] } {
    return { slots: this.slots.map((slot) => slot?.toJSON() ?? null) };
  }

  /** Lenient: a slot that can't be read comes back empty and the others survive. */
  static fromJSON(value: unknown): FocusMixPresets | undefined {
    if (typeof value !== "object" || value === null) return undefined;
    const slots = (value as Record<string, unknown>).slots;
    if (slots === undefined) return FocusMixPresets.empty;
    if (!Array.isArray(slots)) return undefined;
    return new FocusMixPresets(slots.map((slot) => FocusMixPreset.fromJSON(slot)));
  }
}
