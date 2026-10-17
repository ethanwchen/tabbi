import { brightestPetBackdrop } from "../themes/appTheme";
import { allThemes, standardGlassSheen } from "../themes/themeCatalog";
import type { ThemeColor } from "../themes/themeColor";
import type { PetCanvas } from "./petCanvas";
import { PET_SILHOUETTE_CONTRAST, colorsEqual, contrastRatio, luminance, petColor, type PetColor, type PetPalette } from "./petPalette";

/*
 * Port of PetVisibility: how well a rendered pet's silhouette (the ring of
 * pixels touching transparency) stands out from what is behind it. An edge
 * pixel reads when it, or the fill just inside it, reaches the silhouette
 * contrast against the backdrop.
 */

/** What a silhouette looks like against one backdrop. */
export interface PetVisibilityReport {
  readonly edgePixels: number;
  readonly readablePixels: number;
  /** The weakest silhouette pixel's contrast. */
  readonly weakest: number;
  /** Silhouette pixels right outside the main coat (furBase), and how many of those read. */
  readonly coatEdgePixels: number;
  readonly coatReadablePixels: number;
}

export function readableShare(report: PetVisibilityReport): number {
  return report.edgePixels === 0 ? 1 : report.readablePixels / report.edgePixels;
}

/** A named, opaque color a pet is drawn on. */
export interface PetBackdrop {
  readonly name: string;
  readonly color: PetColor;
}

function byte(value: number): number {
  return Math.round(Math.min(Math.max(value, 0), 1) * 255);
}

function themePetColor(color: ThemeColor): PetColor {
  return petColor(byte(color.red), byte(color.green), byte(color.blue));
}

/** The closed notch (pure black) and each theme's brightest card. */
export function petBackdrops(): PetBackdrop[] {
  return [
    { name: "notch", color: petColor(0, 0, 0) },
    ...allThemes.map((theme) => ({
      name: theme.id,
      color: themePetColor(brightestPetBackdrop(theme, standardGlassSheen)),
    })),
  ];
}

/** Row-major indices of the silhouette: opaque pixels with a transparent (or off-canvas) direct neighbor. */
export function silhouetteEdge(canvas: PetCanvas): number[] {
  const indices: number[] = [];
  for (let y = 0; y < canvas.height; y++) {
    for (let x = 0; x < canvas.width; x++) {
      if (canvas.pixel(x, y) === 0) continue;
      const direct = [canvas.pixel(x - 1, y), canvas.pixel(x + 1, y), canvas.pixel(x, y - 1), canvas.pixel(x, y + 1)];
      if (direct.includes(0)) indices.push(y * canvas.width + x);
    }
  }
  return indices;
}

/** The rendered colors of the silhouette, in row-major order. */
export function silhouetteColors(canvas: PetCanvas, palette: PetPalette): PetColor[] {
  const colors = canvas.colors(palette);
  return silhouetteEdge(canvas).flatMap((index) => {
    const color = colors[index];
    return color ? [color] : [];
  });
}

/** How `canvas` drawn with `palette` reads on `backdrop`. */
export function visibilityReport(canvas: PetCanvas, palette: PetPalette, backdrop: PetColor): PetVisibilityReport {
  const colors = canvas.colors(palette);
  const edge = silhouetteEdge(canvas);
  const onEdge = new Set(edge);
  const background = luminance(backdrop);
  const coat = palette.color("furBase");
  let readable = 0;
  let coatEdge = 0;
  let coatReadable = 0;
  let weakest = Number.POSITIVE_INFINITY;
  for (const index of edge) {
    const color = colors[index];
    if (!color) continue;
    const x = index % canvas.width;
    const y = Math.floor(index / canvas.width);
    let best = contrastRatio(luminance(color), background);
    let outlinesCoat = false;
    for (const [nx, ny] of [
      [x - 1, y],
      [x + 1, y],
      [x, y - 1],
      [x, y + 1],
    ] as const) {
      if (nx < 0 || ny < 0 || nx >= canvas.width || ny >= canvas.height) continue;
      const neighbor = ny * canvas.width + nx;
      const inside = colors[neighbor];
      if (onEdge.has(neighbor) || !inside) continue;
      best = Math.max(best, contrastRatio(luminance(inside), background));
      outlinesCoat ||= colorsEqual(inside, coat);
    }
    const reads = best >= PET_SILHOUETTE_CONTRAST;
    if (reads) readable++;
    if (outlinesCoat) {
      coatEdge++;
      if (reads) coatReadable++;
    }
    weakest = Math.min(weakest, best);
  }
  return {
    edgePixels: edge.length,
    readablePixels: readable,
    weakest: edge.length === 0 ? 21 : weakest,
    coatEdgePixels: coatEdge,
    coatReadablePixels: coatReadable,
  };
}
