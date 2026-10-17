import { describe, expect, it } from "vitest";
import { PetCloset, RARE_FURS } from "../../../src/core/closet/petCloset";
import { breedPalette } from "../../../src/core/pets/petBreed";
import { sitting } from "../../../src/core/pets/petComposer";
import { PET_BREEDS } from "../../../src/core/pets/petKinds";
import {
  PET_BACKDROP_CEILING,
  colorHex,
  colorsEqual,
  contrastRatio,
  petColor,
  type PetColor,
} from "../../../src/core/pets/petPalette";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { petBackdrops, readableShare, silhouetteColors, visibilityReport } from "../../../src/core/pets/petVisibility";
import { brightestPetBackdrop } from "../../../src/core/themes/appTheme";
import { allThemes, standardGlassSheen } from "../../../src/core/themes/themeCatalog";
import { luminance as themeLuminance } from "../../../src/core/themes/themeColor";

// Port of PetVisibilityTests.swift: dark coats never vanish on the black
// notch or any theme's brightest card.

const tints: (PetColor | undefined)[] = [undefined, ...PetCloset.furSwatches, ...RARE_FURS.map((fur) => fur.color)];

describe("PetVisibility", () => {
  it("every theme keeps pet backdrops under the ceiling", () => {
    for (const theme of allThemes) {
      expect(themeLuminance(brightestPetBackdrop(theme, standardGlassSheen)), theme.name).toBeLessThanOrEqual(
        PET_BACKDROP_CEILING,
      );
    }
  });

  it("every silhouette reads on every backdrop", () => {
    const backdrops = petBackdrops();
    expect(backdrops.length).toBe(allThemes.length + 1);
    for (const breed of PET_BREEDS) {
      const canvas = sitting(breed);
      for (const tint of tints) {
        const profile = new PetProfile("", breed, { furTint: tint });
        const label = `${breed} ${tint ? colorHex(tint) : "own colors"}`;
        for (const backdrop of backdrops) {
          const report = visibilityReport(canvas, profile.palette, backdrop.color);
          expect(report.coatReadablePixels, `${label} on ${backdrop.name}`).toBe(report.coatEdgePixels);
          expect(readableShare(report), `${label} on ${backdrop.name}`).toBeGreaterThanOrEqual(0.9);
          expect(report.weakest, `${label} on ${backdrop.name}`).toBeGreaterThanOrEqual(1.35);
        }
      }
    }
  });

  it("dark coats are fully outlined by the rim", () => {
    for (const breed of ["blackCat", "shihTzu", "britishLonghair", "labrador"] as const) {
      const palette = breedPalette(breed);
      const canvas = sitting(breed);
      const edge = new Set(silhouetteColors(canvas, palette).map(colorHex));
      expect([...edge], breed).toEqual([colorHex(palette.rim)]);
      for (const backdrop of petBackdrops()) {
        expect(readableShare(visibilityReport(canvas, palette, backdrop.color)), `${breed} on ${backdrop.name}`).toBe(1);
      }
    }
  });

  it("rims dark markings on light coats only where they meet the edge", () => {
    for (const breed of ["siamese", "calico", "frenchBulldog", "beagle"] as const) {
      const palette = breedPalette(breed);
      const edge = silhouetteColors(sitting(breed), palette);
      expect(edge, breed).toContainEqual(palette.rim);
      expect(edge, breed).toContainEqual(palette.color("outline"));
    }
  });

  it("keeps the dark outline around light patches on a dark coat", () => {
    const palette = breedPalette("tuxedo");
    const edge = silhouetteColors(sitting("tuxedo"), palette);
    expect(edge).toContainEqual(palette.color("outline"));
    expect(edge.filter((color) => colorsEqual(color, palette.rim)).length).toBeGreaterThan(edge.length / 2);
  });

  it("draws the rim as one opaque color", () => {
    for (const breed of PET_BREEDS) expect(breedPalette(breed).rim.alpha, breed).toBe(255);
  });

  it("measures contrast like WCAG", () => {
    expect(contrastRatio(1, 0)).toBeCloseTo(21, 2);
    expect(contrastRatio(0, 0)).toBeCloseTo(1, 3);
    expect(petColor(0, 0, 0).alpha).toBe(255);
  });
});
