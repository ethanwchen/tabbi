import { badgePalette } from "../../progression/badgeArt";
import { PetCanvas } from "../petCanvas";
import type { PetColor } from "../petPalette";
import type { PetBitmap } from "../petRenderer";
import { SpriteGrid } from "../spriteGrid";
import { radiantArt } from "./radiantArt";

/*
 * Port of RadiantMarkerArt: the Radiant marker, a 9 by 9 four-pointed star
 * pip on the corner of a Closet tile once its item is upgraded. It is drawn
 * like the Goals badges: the grid in `radiant.json` uses the badge slots
 * (`C` rim, `D` shade, `W` bright core, `L` highlight, `O` outline), colored
 * from the Gold badge palette by a plain lookup, with no dark-coat rim.
 */

/** The marker's side, in sprite pixels. */
export function radiantMarkerSize(): number {
  return radiantArt().marker.length;
}

export function radiantMarkerCanvas(): PetCanvas {
  const rows = radiantArt().marker;
  const canvas = new PetCanvas(rows[0]?.length ?? 0, rows.length);
  canvas.stamp(SpriteGrid.fromRows(rows), 0, 0);
  return canvas;
}

/** The marker's pixels as colors, row-major, undefined for transparent. */
export function radiantMarkerColors(): (PetColor | undefined)[] {
  const palette = badgePalette("gold");
  return Array.from(radiantMarkerCanvas().pixels, (pixel) => (pixel === 0 ? undefined : palette.colorAt(pixel - 1)));
}

const bitmaps = new Map<number, PetBitmap>();

/** The marker at a whole number of device pixels per sprite pixel, straight RGBA, never smoothed. Port of RadiantMarkerArt.image(scale:). */
export function radiantMarkerBitmap(scaleIn: number): PetBitmap {
  const scale = Math.max(1, Math.trunc(scaleIn));
  const hit = bitmaps.get(scale);
  if (hit) return hit;
  const side = radiantMarkerSize();
  const colors = radiantMarkerColors();
  const width = side * scale;
  const data = new Uint8ClampedArray(width * width * 4);
  colors.forEach((color, i) => {
    if (!color) return;
    const sx = i % side;
    const sy = Math.trunc(i / side);
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
  });
  const bitmap: PetBitmap = { width, height: width, data };
  bitmaps.set(scale, bitmap);
  return bitmap;
}
