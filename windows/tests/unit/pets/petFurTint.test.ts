import { describe, expect, it } from "vitest";
import { PetCloset } from "../../../src/core/closet/petCloset";
import { breedFurTint, breedPalette, breedPattern } from "../../../src/core/pets/petBreed";
import { PET_BREEDS, type PetBreed } from "../../../src/core/pets/petKinds";
import {
  PetFurTone,
  TINTABLE_FUR_ROLES,
  colorFromHex,
  colorFromOKLCH,
  colorHex,
  luminance,
  oklch,
  type PetColor,
  type PetPalette,
  type PetPaletteRole,
} from "../../../src/core/pets/petPalette";
import { PetProfile } from "../../../src/core/pets/petProfile";

// Port of PetFurTintTests.swift: every breed in every Closet swatch looks
// intentional, white stays white and faces stay readable.

function hex(value: string): PetColor {
  const color = colorFromHex(value);
  if (!color) throw new Error(`bad color ${value}`);
  return color;
}

function tinted(breed: PetBreed, pick: PetColor): PetPalette {
  const profile = new PetProfile("", breed);
  profile.tintFur(pick);
  return profile.palette;
}

// WCAG contrast ratio between two colors.
function contrast(a: PetColor, b: PetColor): number {
  const light = Math.max(luminance(a), luminance(b));
  const dark = Math.min(luminance(a), luminance(b));
  return (light + 0.05) / (dark + 0.05);
}

// OKLab distance: about 0.02 is barely visible, 0.1 clearly different.
function difference(a: PetColor, b: PetColor): number {
  const p = oklch(a);
  const q = oklch(b);
  const da = p.chroma * Math.cos(p.hue) - q.chroma * Math.cos(q.hue);
  const db = p.chroma * Math.sin(p.hue) - q.chroma * Math.sin(q.hue);
  const dl = p.lightness - q.lightness;
  return Math.sqrt(dl * dl + da * da + db * db);
}

const SWATCHES = PetCloset.furSwatches;

describe("PetFurTint", () => {
  it("OKLCH round-trips sRGB", () => {
    for (const value of ["#F2A65A", "#5E5856", "#9EC3EC", "#FFFFFF", "#000000", "#2B2830"]) {
      const color = hex(value);
      const lch = oklch(color);
      expect(colorHex(colorFromOKLCH(lch.lightness, lch.chroma, lch.hue)), value).toBe(colorHex(color));
    }
  });

  it("tones never clip to black or white", () => {
    for (const pick of [...SWATCHES, hex("#000000"), hex("#FFFFFF")]) {
      for (const breed of PET_BREEDS) {
        for (const [role, color] of Object.entries(breedFurTint(breed, pick))) {
          if (!color) continue;
          const lightness = oklch(color).lightness;
          const label = `${breed} ${role} ${colorHex(pick)}`;
          expect(lightness, label).toBeGreaterThanOrEqual(PetFurTone.darkest - 0.01);
          expect(lightness, label).toBeLessThanOrEqual(PetFurTone.lightest + 0.01);
        }
      }
    }
  });

  it("darker and lighter tones keep their direction on every swatch", () => {
    for (const pick of SWATCHES) {
      const base = oklch(pick).lightness;
      expect(oklch(PetFurTone.darker(0.2).color(pick)).lightness, colorHex(pick)).toBeLessThan(base - 0.02);
      expect(oklch(PetFurTone.lighter(0.2).color(pick)).lightness, colorHex(pick)).toBeGreaterThan(base + 0.005);
    }
  });

  it("white markings stay white", () => {
    for (const breed of ["tuxedo", "calico", "britishShorthair", "corgi", "beagle", "frenchBulldog"] as const) {
      for (const pick of SWATCHES) {
        expect(tinted(breed, pick).color("belly"), `${breed} ${colorHex(pick)}`).toEqual(breedPalette(breed).color("belly"));
      }
    }
    for (const breed of ["calico", "frenchBulldog"] as const) {
      for (const pick of SWATCHES) {
        expect(tinted(breed, pick).color("furBase"), `${breed} ${colorHex(pick)}`).toEqual(breedPalette(breed).color("furBase"));
      }
    }
  });

  it("patches on white stay visible", () => {
    const markings: [PetBreed, PetPaletteRole][] = [
      ["calico", "furAccent"],
      ["calico", "furSpot"],
      ["frenchBulldog", "furSpot"],
    ];
    for (const [breed, role] of markings) {
      for (const pick of SWATCHES) {
        const palette = tinted(breed, pick);
        expect(oklch(palette.color("furBase")).lightness - oklch(palette.color(role)).lightness, `${breed} ${role} ${colorHex(pick)}`).toBeGreaterThan(0.1);
      }
    }
  });

  it("Shih Tzu keeps its mouth stain on every swatch", () => {
    const stain = breedPalette("shihTzu").color("furSpot");
    expect(luminance(breedPalette("shihTzu").color("furBase")), "black by default").toBeLessThan(0.05);
    expect(breedPattern("shihTzu").role("muzzle")).toBe("furSpot");
    for (const pick of SWATCHES) {
      const palette = tinted("shihTzu", pick);
      expect(colorHex(palette.color("furBase")), colorHex(pick)).toBe(colorHex(pick));
      expect(palette.color("furSpot"), colorHex(pick)).toEqual(stain);
    }
  });

  it("Siamese points are a darker, softer pick", () => {
    for (const pick of SWATCHES) {
      const palette = tinted("siamese", pick);
      const body = oklch(palette.color("furBase")).lightness;
      const points = oklch(palette.color("furAccent")).lightness;
      expect(body - points, `${colorHex(pick)}: points stand out from the body`).toBeGreaterThan(0.15);
      expect(points, `${colorHex(pick)}: points are never near-black`).toBeGreaterThan(0.35);
      expect(oklch(palette.color("furSpot")).lightness, `${colorHex(pick)}: the mask is darker than the body`).toBeLessThan(body);
    }
  });

  it("stripes are a gentle darker shade", () => {
    for (const breed of ["orangeTabby", "grayTabby"] as const) {
      for (const pick of SWATCHES) {
        const palette = tinted(breed, pick);
        const step = oklch(palette.color("furBase")).lightness - oklch(palette.color("furAccent")).lightness;
        expect(step >= 0.05 && step <= 0.25, `${breed} ${colorHex(pick)}: ${step}`).toBe(true);
        expect(oklch(palette.color("furAccent")).chroma, "no harsh saturation").toBeLessThanOrEqual(oklch(pick).chroma + 0.005);
      }
    }
  });

  it("faces stay readable on every swatch", () => {
    for (const breed of PET_BREEDS) {
      for (const pick of SWATCHES) {
        const profile = new PetProfile("", breed);
        profile.tintFur(pick);
        const canvas = profile.sittingCanvas();
        const colors = canvas.colors(profile.palette);
        const colorAt = (x: number, y: number) => {
          const color = colors[y * canvas.width + x];
          if (!color) throw new Error("an opaque pixel");
          return color;
        };
        // The fur pixels touching a face feature: the feature's colors and the lightest fur.
        const furAround = (wanted: PetPaletteRole[]): { feature: PetColor[]; fur: PetColor } | undefined => {
          const feature: PetColor[] = [];
          const fur: PetColor[] = [];
          for (let y = 0; y < canvas.height; y++) {
            for (let x = 0; x < canvas.width; x++) {
              const role = canvas.role(x, y);
              if (role === undefined || !wanted.includes(role)) continue;
              feature.push(colorAt(x, y));
              for (const [dx, dy] of [
                [-1, 0],
                [1, 0],
                [0, -1],
                [0, 1],
              ] as const) {
                const around = canvas.role(x + dx, y + dy);
                if (around === undefined || !TINTABLE_FUR_ROLES.includes(around)) continue;
                fur.push(colorAt(x + dx, y + dy));
              }
            }
          }
          if (fur.length === 0) return undefined;
          let lightest = fur[0] ?? fur[0];
          for (const color of fur) if (lightest && luminance(color) > luminance(lightest)) lightest = color;
          return lightest ? { feature, fur: lightest } : undefined;
        };
        const label = `${breed} on ${colorHex(pick)}`;
        const eye = furAround(["eye", "pupil"]);
        if (eye) expect(Math.max(...eye.feature.map((c) => contrast(c, eye.fur))), `eye: ${label}`).toBeGreaterThan(2);
        const mouth = furAround(["mouth"]);
        if (mouth) expect(Math.min(...mouth.feature.map((c) => contrast(c, mouth.fur))), `mouth: ${label}`).toBeGreaterThan(1.8);
        const nose = furAround(["nose"]);
        const noseColor = nose?.feature[0];
        if (nose && noseColor) expect(difference(noseColor, nose.fur), `nose: ${label}`).toBeGreaterThan(0.07);
      }
    }
  });

  it("swatches need no rim, so no ring around dark picks", () => {
    for (const pick of SWATCHES) {
      for (const breed of PET_BREEDS) {
        expect(tinted(breed, pick).color("outline"), `${breed} ${colorHex(pick)}`).toEqual(breedPalette(breed).color("outline"));
      }
    }
  });
});
