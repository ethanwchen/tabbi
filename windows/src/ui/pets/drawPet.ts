import type { PetCanvas } from "../../core/pets/petCanvas";
import type { PetPalette } from "../../core/pets/petPalette";
import { PetRenderCache } from "../../core/pets/petRenderer";

/*
 * Draws composed pet frames onto a canvas 2D context, crisp at any display
 * scale. The pet is pixel art, so each sprite pixel must cover a whole
 * number of device pixels: at 125 or 150 percent a fractional scale would
 * make some pixels one device pixel wider than others. `pixelScale` picks
 * the largest whole-pixel scale that fits the box, and `drawPet` writes the
 * frame at exactly that size with smoothing off.
 */

/** How to size a `<canvas>` for a pet in a CSS box. */
export interface PetPixelScale {
  /** Device pixels per sprite pixel, a whole number (0 when nothing fits). */
  readonly scale: number;
  /** The canvas backing store size, in device pixels. */
  readonly deviceWidth: number;
  readonly deviceHeight: number;
  /** The canvas's CSS size, so its backing store maps one to one onto device pixels. */
  readonly cssWidth: number;
  readonly cssHeight: number;
}

/**
 * The largest whole number of device pixels per sprite pixel such that a
 * `spriteWidth` x `spriteHeight` sprite fits in a `boxWidth` x `boxHeight`
 * CSS box on a display with `devicePixelRatio`. The CSS size is the device
 * size divided by the ratio, so the browser maps the backing store one to
 * one onto device pixels and never resamples it.
 */
export function pixelScale(
  boxWidth: number,
  boxHeight: number,
  devicePixelRatio: number,
  spriteWidth = 32,
  spriteHeight = spriteWidth,
): PetPixelScale {
  const ratio = Number.isFinite(devicePixelRatio) && devicePixelRatio > 0 ? devicePixelRatio : 1;
  const deviceBoxWidth = Math.max(0, boxWidth) * ratio;
  const deviceBoxHeight = Math.max(0, boxHeight) * ratio;
  /* A hair of tolerance, so 32 CSS px at 150 percent (exactly 48 device px) is not lost to rounding. */
  const epsilon = 1e-6;
  const scale =
    spriteWidth > 0 && spriteHeight > 0
      ? Math.max(0, Math.floor(Math.min(deviceBoxWidth / spriteWidth, deviceBoxHeight / spriteHeight) + epsilon))
      : 0;
  const deviceWidth = spriteWidth * scale;
  const deviceHeight = spriteHeight * scale;
  return { scale, deviceWidth, deviceHeight, cssWidth: deviceWidth / ratio, cssHeight: deviceHeight / ratio };
}

/** The slice of `CanvasRenderingContext2D` drawing needs, so tests can pass a stand-in. */
export interface PetDrawingContext {
  imageSmoothingEnabled: boolean;
  putImageData(data: ImageData, dx: number, dy: number): void;
  createImageData(width: number, height: number): ImageData;
}

const sharedCache = new PetRenderCache();

/**
 * Draws `canvas` in `palette` at a whole-number device-pixel `scale`, its
 * top-left corner at device pixel (`x`, `y`). Pixels are written directly,
 * so nothing is ever interpolated; smoothing is turned off as well for
 * anything else drawn on the context. Writing replaces what was under the
 * frame, so the pet gets a canvas of its own over the panel.
 */
export function drawPet(
  context: PetDrawingContext,
  canvas: PetCanvas,
  palette: PetPalette,
  scale: number,
  x = 0,
  y = 0,
  cache: PetRenderCache = sharedCache,
): void {
  context.imageSmoothingEnabled = false;
  const whole = Math.trunc(scale);
  if (whole < 1) return;
  const bitmap = cache.bitmap(canvas, palette, whole);
  const image = context.createImageData(bitmap.width, bitmap.height);
  image.data.set(bitmap.data);
  context.putImageData(image, Math.round(x), Math.round(y));
}

/** Sizes a `<canvas>` element for `scale` (backing store in device pixels, CSS size in CSS pixels). */
export function sizePetCanvas(element: HTMLCanvasElement, size: PetPixelScale): void {
  element.width = size.deviceWidth;
  element.height = size.deviceHeight;
  element.style.width = `${size.cssWidth}px`;
  element.style.height = `${size.cssHeight}px`;
  element.style.imageRendering = "pixelated";
}
