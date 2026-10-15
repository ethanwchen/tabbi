import { NO_BOND_LOOK, type PetBondLook } from "../../../src/core/pets/petBond";
import { breedBodyShape } from "../../../src/core/pets/petBreed";
import type { PetCanvas } from "../../../src/core/pets/petCanvas";
import { composeClip, type PetClip } from "../../../src/core/pets/petClip";
import { FRAME_SIZE } from "../../../src/core/pets/petComposer";
import type { PetAccessory, PetOutfit } from "../../../src/core/pets/petCostume";
import { PET_BODY_SHAPES, PET_BREEDS, type PetAnimation, type PetBreed } from "../../../src/core/pets/petKinds";
import type { PetPaletteRole } from "../../../src/core/pets/petPalette";

// Shared helpers for the pet unit tests, mirroring the Swift tests' idioms.

export const BASELINE = FRAME_SIZE - 1;

export interface ClipOptions {
  outfit?: PetOutfit;
  accessories?: readonly PetAccessory[];
  bond?: PetBondLook;
  ceiling?: number;
}

const clipCache = new Map<string, PetClip>();

// PetComposer.clip, memoized: many tests compare the same bare clips.
export function clip(animation: PetAnimation, breed: PetBreed, options: ClipOptions = {}): PetClip {
  const bond = options.bond ?? NO_BOND_LOOK;
  const key = JSON.stringify([
    animation,
    breed,
    options.outfit ?? "none",
    options.accessories ?? [],
    bond.collar,
    bond.happyIdle,
    bond.sparkle,
    options.ceiling ?? null,
  ]);
  let built = clipCache.get(key);
  if (!built) {
    built = composeClip(animation, breed, options);
    clipCache.set(key, built);
  }
  return built;
}

// Every role in the canvas, row-major, undefined for transparent pixels.
export function roles(canvas: PetCanvas): (PetPaletteRole | undefined)[] {
  const out: (PetPaletteRole | undefined)[] = [];
  for (let y = 0; y < canvas.height; y++) for (let x = 0; x < canvas.width; x++) out.push(canvas.role(x, y));
  return out;
}

export function contains(canvas: PetCanvas, role: PetPaletteRole): boolean {
  return roles(canvas).includes(role);
}

export function count(canvas: PetCanvas, ...wanted: PetPaletteRole[]): number {
  return roles(canvas).filter((role) => role !== undefined && wanted.includes(role)).length;
}

export function opaqueCount(canvas: PetCanvas): number {
  return roles(canvas).filter((role) => role !== undefined).length;
}

export function bounds(canvas: PetCanvas): { minX: number; minY: number; maxX: number; maxY: number } {
  const found = canvas.opaqueBounds;
  if (!found) throw new Error("the canvas is blank");
  return found;
}

// A text key for a canvas, so canvases can go in sets.
export function key(canvas: PetCanvas): string {
  return canvas.symbols();
}

export function distinct(canvases: readonly PetCanvas[]): number {
  return new Set(canvases.map(key)).size;
}

export function same(a: PetCanvas | undefined, b: PetCanvas | undefined): boolean {
  return a !== undefined && b !== undefined && a.equals(b);
}

// Which pixels are opaque, as a 0/1 string.
export function silhouette(canvas: PetCanvas): string {
  return roles(canvas)
    .map((role) => (role === undefined ? "0" : "1"))
    .join("");
}

export function points(role: PetPaletteRole, canvas: PetCanvas): { x: number; y: number }[] {
  const found: { x: number; y: number }[] = [];
  for (let y = 0; y < canvas.height; y++) {
    for (let x = 0; x < canvas.width; x++) if (canvas.role(x, y) === role) found.push({ x, y });
  }
  return found;
}

// The left, right and top frame edges, as the Swift tests read them.
export function edges(canvas: PetCanvas): (PetPaletteRole | undefined)[] {
  const last = FRAME_SIZE - 1;
  const out: (PetPaletteRole | undefined)[] = [];
  for (let i = 0; i <= last; i++) out.push(canvas.role(0, i), canvas.role(last, i), canvas.role(i, 0));
  return out;
}

export function onlyOutline(values: readonly (PetPaletteRole | undefined)[]): boolean {
  return values.every((role) => role === undefined || role === "outline");
}

// One breed per body shape, in body shape order (PetGallery.bodyShapeBreeds).
export const BODY_SHAPE_BREEDS: readonly PetBreed[] = PET_BODY_SHAPES.flatMap((shape) => {
  const breed = PET_BREEDS.find((candidate) => breedBodyShape(candidate) === shape);
  return breed ? [breed] : [];
});

export function max<T>(values: readonly T[], by: (value: T) => number): T {
  let best = values[0];
  if (best === undefined) throw new Error("empty");
  for (const value of values) if (by(value) > by(best)) best = value;
  return best;
}
