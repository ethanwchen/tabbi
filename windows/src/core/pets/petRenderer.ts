import type { PetCanvas } from "./petCanvas";
import type { PetPalette } from "./petPalette";

/*
 * Port of PetRenderer: turns a composed frame into pixels. Scaling writes
 * each sprite pixel as an exact `scale` x `scale` block, so the result is
 * nearest-neighbor however it is drawn later. The output is straight
 * (unpremultiplied) RGBA, the layout of the web's `ImageData`.
 */

/** RGBA pixels, row-major, four bytes per pixel. */
export interface PetBitmap {
  readonly width: number;
  readonly height: number;
  readonly data: Uint8ClampedArray;
}

/** Uncached rendering at a whole-number `scale` (at least 1). */
export function renderPet(canvas: PetCanvas, palette: PetPalette, scaleIn = 1): PetBitmap {
  const scale = Math.max(1, Math.trunc(scaleIn));
  const width = canvas.width * scale;
  const height = canvas.height * scale;
  const data = new Uint8ClampedArray(width * height * 4);
  const colors = canvas.colors(palette);
  for (let sy = 0; sy < canvas.height; sy++) {
    for (let sx = 0; sx < canvas.width; sx++) {
      const color = colors[sy * canvas.width + sx];
      if (!color) continue;
      for (let dy = 0; dy < scale; dy++) {
        let offset = ((sy * scale + dy) * width + sx * scale) * 4;
        for (let dx = 0; dx < scale; dx++) {
          data[offset] = color.red;
          data[offset + 1] = color.green;
          data[offset + 2] = color.blue;
          data[offset + 3] = color.alpha;
          offset += 4;
        }
      }
    }
  }
  return { width, height, data };
}

/**
 * A bounded cache of rendered frames: the same few frames repeat forever in
 * an idle animation. A plain pet uses about 40 distinct frames; an animated
 * costume multiplies that, and then the oldest simply render again.
 */
export class PetRenderCache {
  private readonly cache = new Map<string, PetBitmap>();

  constructor(readonly capacity = 256) {}

  get size(): number {
    return this.cache.size;
  }

  bitmap(canvas: PetCanvas, palette: PetPalette, scale = 1): PetBitmap {
    /* Keyed by content, so a frame composed again still hits. */
    const key = `${canvas.width}x${canvas.height}:${canvas.symbols()}|${palette.key}|${Math.max(1, Math.trunc(scale))}`;
    const hit = this.cache.get(key);
    if (hit) return hit;
    const bitmap = renderPet(canvas, palette, scale);
    this.cache.set(key, bitmap);
    if (this.cache.size > this.capacity) {
      const oldest = this.cache.keys().next().value;
      if (oldest !== undefined) this.cache.delete(oldest);
    }
    return bitmap;
  }
}
