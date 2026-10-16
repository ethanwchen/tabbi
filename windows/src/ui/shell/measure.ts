/*
 * Text widths in the island's type, measured on a canvas the way the page
 * draws them, so layouts that must be known before drawing (the header's
 * title, the pill's wings) agree with what shows. Widths are cached per
 * font and text; the font family follows the theme's variable.
 */

const cache = new Map<string, number>();
let context: CanvasRenderingContext2D | null | undefined;

function canvasContext(): CanvasRenderingContext2D | null {
  if (context === undefined) context = typeof document === "undefined" ? null : document.createElement("canvas").getContext("2d");
  return context;
}

/** The font family the island draws with (the kit's `--font`). */
export function islandFontFamily(): string {
  if (typeof document === "undefined") return "sans-serif";
  const family = getComputedStyle(document.documentElement).getPropertyValue("--font").trim();
  return family === "" ? "sans-serif" : family;
}

/** The width of `text` in `weight` and `size` px of the island's font; a rough estimate without a canvas. */
export function textWidth(text: string, size: number, weight: number, family: string = islandFontFamily()): number {
  const font = `${weight} ${size}px ${family}`;
  const key = `${font}\u0000${text}`;
  const known = cache.get(key);
  if (known !== undefined) return known;
  const canvas = canvasContext();
  let width = text.length * size * 0.55;
  if (canvas) {
    canvas.font = font;
    width = canvas.measureText(text).width;
  }
  cache.set(key, width);
  return width;
}

/** Forgets measured widths, after the fonts finish loading. */
export function clearTextWidths(): void {
  cache.clear();
}
