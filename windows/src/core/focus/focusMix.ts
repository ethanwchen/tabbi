import { FOCUS_SOUNDS, focusSoundDisplayName, isFocusSound, type FocusSound } from "./focusSound";
import { tr } from "../localization/tr";

/** Port of FocusMix.Layer: one sound and its relative level within the mix, 0...1. */
export interface FocusMixLayer {
  readonly sound: FocusSound;
  readonly level: number;
}

/* Levels are single precision on the Mac; NaN and infinities become full level. */
function clampLevel(level: number): number {
  return Number.isFinite(level) ? Math.fround(Math.min(Math.max(level, 0), 1)) : 1;
}

/**
 * Port of FocusMix: the user's focus sound choice, up to `MAX_LAYERS` sounds
 * each with its own level. An empty mix means Off. Always sanitized (unique
 * sounds, levels clamped to 0...1, at most three layers), including when
 * decoded from settings someone edited by hand. Immutable: changes return a
 * new mix.
 */
export class FocusMix {
  /** Three layers is enough for a scene (rain, fireplace and cafe) without turning into mud. */
  static readonly maxLayers = 3;

  readonly layers: readonly FocusMixLayer[];

  constructor(layers: readonly { sound: FocusSound; level?: number }[] = []) {
    const seen = new Set<FocusSound>();
    this.layers = layers
      .filter((layer) => {
        if (seen.has(layer.sound)) return false;
        seen.add(layer.sound);
        return true;
      })
      .slice(0, FocusMix.maxLayers)
      .map((layer) => ({ sound: layer.sound, level: clampLevel(layer.level ?? 1) }));
  }

  static readonly off = new FocusMix();

  /** A mix of one sound at full level. */
  static single(sound: FocusSound): FocusMix {
    return new FocusMix([{ sound }]);
  }

  get isOff(): boolean {
    return this.layers.length === 0;
  }

  get canAddLayer(): boolean {
    return this.layers.length < FocusMix.maxLayers;
  }

  contains(sound: FocusSound): boolean {
    return this.layers.some((layer) => layer.sound === sound);
  }

  /** The level of `sound`, or undefined when it isn't in the mix. */
  level(sound: FocusSound): number | undefined {
    return this.layers.find((layer) => layer.sound === sound)?.level;
  }

  /**
   * Adds `sound` at full level, or removes it if present. Returns the same mix
   * (changed: false) when adding would exceed `maxLayers`.
   */
  toggled(sound: FocusSound): { mix: FocusMix; changed: boolean } {
    if (this.contains(sound)) return { mix: new FocusMix(this.layers.filter((layer) => layer.sound !== sound)), changed: true };
    if (!this.canAddLayer) return { mix: this, changed: false };
    return { mix: new FocusMix([...this.layers, { sound, level: 1 }]), changed: true };
  }

  /** The mix with the level of a sound already in it changed; unchanged otherwise. */
  withLevel(level: number, sound: FocusSound): FocusMix {
    if (!this.contains(sound)) return this;
    return new FocusMix(this.layers.map((layer) => (layer.sound === sound ? { sound, level: clampLevel(level) } : layer)));
  }

  /** Short label for pickers and tooltips, e.g. "Rain + Fireplace". */
  get summary(): string {
    return this.isOff ? tr("Off") : this.layers.map((layer) => focusSoundDisplayName(layer.sound)).join(" + ");
  }

  /**
   * Linear gain for each sound in the mix. Layers are uncorrelated, so their
   * powers add: when the summed power exceeds a single full layer, every gain
   * is scaled down so the blend stays at the level of one sound.
   */
  get gains(): Map<FocusSound, number> {
    let power = 0;
    for (const layer of this.layers) power = Math.fround(power + Math.fround(layer.level * layer.level));
    const scale = power > 1 ? Math.fround(1 / Math.fround(Math.sqrt(power))) : 1;
    return new Map(this.layers.map((layer) => [layer.sound, Math.fround(layer.level * scale)]));
  }

  equals(other: FocusMix): boolean {
    return (
      this.layers.length === other.layers.length &&
      this.layers.every((layer, index) => layer.sound === other.layers[index]?.sound && layer.level === other.layers[index]?.level)
    );
  }

  toJSON(): { layers: FocusMixLayer[] } {
    return { layers: this.layers.map((layer) => ({ sound: layer.sound, level: layer.level })) };
  }

  /** Decodes `{"layers": [...]}` leniently: unknown sounds are an error on the Mac, so the whole mix is refused. */
  static fromJSON(value: unknown): FocusMix | undefined {
    if (typeof value !== "object" || value === null) return undefined;
    const layers = (value as Record<string, unknown>).layers;
    if (layers === undefined) return FocusMix.off;
    if (!Array.isArray(layers)) return undefined;
    const decoded: { sound: FocusSound; level: number }[] = [];
    for (const entry of layers) {
      if (typeof entry !== "object" || entry === null) return undefined;
      const { sound, level } = entry as Record<string, unknown>;
      if (!isFocusSound(sound) || typeof level !== "number") return undefined;
      decoded.push({ sound, level });
    }
    return new FocusMix(decoded);
  }
}

/** Every sound in `FocusSound` order, the way the Mac mixer keeps one generator per sound. */
export const MIXER_SOUND_ORDER: readonly FocusSound[] = FOCUS_SOUNDS;
