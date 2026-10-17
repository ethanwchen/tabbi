import { describe, expect, it } from "vitest";
import { breedDisplayName, breedPalette, breedPattern, breedSpecies, breedsOf } from "../../../src/core/pets/petBreed";
import { PetCanvas, PetPattern } from "../../../src/core/pets/petCanvas";
import { PetClipSet } from "../../../src/core/pets/petAnimator";
import { FRAME_SIZE, sitting } from "../../../src/core/pets/petComposer";
import { PET_ACCESSORIES, PET_OUTFITS } from "../../../src/core/pets/petCostume";
import { PET_ANIMATIONS, PET_BREEDS, type PetBreed } from "../../../src/core/pets/petKinds";
import {
  PET_BACKDROP_CEILING,
  PET_PALETTE_ROLES,
  PET_SILHOUETTE_CONTRAST,
  PetPalette,
  contrastRatio,
  colorFromHex,
  colorHex,
  luminance,
  petColor,
  roleFromSymbol,
  roleSymbol,
  type PetColor,
} from "../../../src/core/pets/petPalette";
import { petPose, type PetEyes } from "../../../src/core/pets/petPose";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { PetRenderCache, renderPet } from "../../../src/core/pets/petRenderer";
import { silhouetteColors } from "../../../src/core/pets/petVisibility";
import { PET_PATTERN_ZONES, SpriteGrid, zoneFromSymbol, zoneSymbol } from "../../../src/core/pets/spriteGrid";
import { bounds, clip, contains, count, roles, silhouette } from "./support";

// Port of PetsSpriteTests.swift: colors, palettes, sprite grids, canvases,
// the renderer, breeds and eyes.

function hex(value: string): PetColor {
  const color = colorFromHex(value);
  if (!color) throw new Error(`bad color ${value}`);
  return color;
}

function grid(text: string): SpriteGrid {
  return SpriteGrid.parse(text);
}

describe("PetColor", () => {
  it("parses and formats hex", () => {
    expect(colorFromHex("#FF8000")).toEqual(petColor(255, 128, 0));
    expect(colorFromHex("ff800080")?.alpha).toBe(128);
    expect(colorHex(petColor(1, 2, 3))).toBe("#010203");
    expect(colorHex(petColor(1, 2, 3, 4))).toBe("#01020304");
    expect(colorFromHex("#12345")).toBeUndefined();
    expect(colorFromHex("#GG0000")).toBeUndefined();
  });

  it("luminance orders dark below light", () => {
    expect(luminance(hex("#000000"))).toBeCloseTo(0, 4);
    expect(luminance(hex("#FFFFFF"))).toBeCloseTo(1, 4);
    expect(luminance(hex("#2B2830"))).toBeLessThan(luminance(hex("#F2A65A")));
  });
});

describe("PetPalette", () => {
  it("every role has a color and overrides win", () => {
    const palette = new PetPalette({ furBase: hex("#112233") });
    for (const role of PET_PALETTE_ROLES) expect(palette.color(role)).toBeDefined();
    const recolored = palette.applying({ furBase: hex("#445566") });
    expect(colorHex(recolored.color("furBase"))).toBe("#445566");
    expect(recolored.color("eye")).toEqual(palette.color("eye"));
  });

  it("round-trips through JSON as hex strings", () => {
    const palette = new PetPalette({ costumeBase: hex("#ABCDEF") });
    const text = JSON.stringify(palette);
    expect(text).toContain('"costumeBase":"#ABCDEF"');
    expect(PetPalette.fromJSON(JSON.parse(text) as Record<string, unknown>).equals(palette)).toBe(true);
  });

  it("dark fur gets a light rim so it never vanishes on black", () => {
    const black = breedPalette("blackCat").applying({ furBase: hex("#1A1A1A"), outline: hex("#000000") });
    const edge = new Set(silhouetteColors(sitting("blackCat"), black).map(colorHex));
    expect([...edge]).toEqual([colorHex(black.rim)]);
  });

  it("light coats keep their dark outline pixel for pixel", () => {
    for (const breed of ["whiteCat", "britishShorthair", "sphynx", "goldenRetriever", "corgi", "poodle"] as const) {
      const canvas = sitting(breed);
      const palette = breedPalette(breed);
      const colors = canvas.colors(palette);
      const all = roles(canvas);
      all.forEach((role, index) => {
        if (role === "mouth") return;
        expect(colors[index], `${breed} pixel ${index}`).toEqual(role ? palette.color(role) : undefined);
      });
    }
  });

  it("cat mouth contrasts with the fur it sits on", () => {
    const mouthColors = (breed: PetBreed, tint?: PetColor): string[] => {
      const profile = new PetProfile("", breed);
      profile.tintFur(tint);
      const canvas = sitting(breed);
      const colors = canvas.colors(profile.palette);
      const all = roles(canvas);
      const mouth = all.flatMap((role, index) => (role === "mouth" ? [index] : []));
      expect(mouth.length, `${breed} draws a mouth`).toBeGreaterThan(0);
      return [...new Set(mouth.flatMap((index) => {
        const color = colors[index];
        return color ? [colorHex(color)] : [];
      }))];
    };
    const dark = colorHex(new PetPalette({}).color("mouth"));
    // The tuxedo is black fur with a white muzzle: a rim-colored mouth would smudge it.
    expect(mouthColors("tuxedo")).toEqual([dark]);
    expect(mouthColors("orangeTabby")).toEqual([dark]);
    // A dark mouth vanishes into black fur.
    expect(mouthColors("blackCat")).toEqual([colorHex(breedPalette("blackCat").sheen)]);
    // The Siamese mask is a soft mid-brown, light enough for the dark mouth.
    expect(mouthColors("siamese")).toEqual([dark]);
    expect(mouthColors("blackCat", hex("#F4F0EA")), "recolors adapt too").toEqual([dark]);
  });

  it("Siamese mask is softer than its points so the face stays readable", () => {
    const palette = breedPalette("siamese");
    const pattern = breedPattern("siamese");
    const maskRole = pattern.role("muzzle");
    expect(pattern.role("mask"), "one even mask, no dark diamond on top").toBe(maskRole);
    const mask = luminance(palette.color(maskRole));
    expect(mask).toBeLessThan(luminance(palette.color("furBase")));
    expect(mask).toBeGreaterThan(luminance(palette.color(pattern.role("ears"))));
  });

  it("calico patches are big enough to read as calico", () => {
    const palette = breedPalette("calico");
    const orange = colorHex(palette.color("furAccent"));
    const black = colorHex(palette.color("furSpot"));
    const canvases: [PetCanvas, number][] = [
      [sitting("calico"), 32],
      [clip("walk", "calico").frames[0]?.canvas ?? new PetCanvas(32, 32), 24],
    ];
    for (const [canvas, minimum] of canvases) {
      const colors = canvas.colors(palette).map((color) => (color ? colorHex(color) : ""));
      expect(colors.filter((color) => color === orange).length).toBeGreaterThanOrEqual(minimum);
      expect(colors.filter((color) => color === black).length).toBeGreaterThanOrEqual(minimum);
    }
  });

  it("role symbols are unique and round-trip", () => {
    const symbols = [...PET_PALETTE_ROLES.map(roleSymbol), ...PET_PATTERN_ZONES.map(zoneSymbol)];
    expect(new Set(symbols).size).toBe(symbols.length);
    for (const role of PET_PALETTE_ROLES) expect(roleFromSymbol(roleSymbol(role))).toBe(role);
    for (const zone of PET_PATTERN_ZONES) expect(zoneFromSymbol(zoneSymbol(zone))).toBe(zone);
  });
});

describe("SpriteGrid", () => {
  it("parses roles, zones, empty and erase", () => {
    const parsed = grid("\n.BxW\nm S.\n\n");
    expect(parsed.width).toBe(4);
    expect(parsed.height).toBe(2);
    expect(parsed.cell(0, 0)).toEqual({ kind: "empty" });
    expect(parsed.cell(1, 0)).toEqual({ kind: "role", role: "furBase" });
    expect(parsed.cell(2, 0)).toEqual({ kind: "erase" });
    expect(parsed.cell(0, 1)).toEqual({ kind: "zone", zone: "muzzle" });
    expect(parsed.cell(1, 1)).toEqual({ kind: "empty" });
    expect(parsed.text).toBe(".BxW\nm.S.");
  });

  it("reports ragged rows and unknown symbols with positions", () => {
    expect(() => grid("BB\nB")).toThrow("Row 2 is 1 wide; expected 2");
    expect(() => grid("BB\nB?")).toThrow("Unknown symbol '?' at row 2, column 2");
    expect(() => grid("\n  \n")).toThrow("Sprite grid has no rows");
  });

  it("mirrors left to right", () => {
    expect(grid("BS.\nW..").mirrored().text).toBe(".SB\n..W");
  });
});

describe("PetCanvas", () => {
  it("later layers paint over and erase clears", () => {
    const canvas = new PetCanvas(3, 1);
    canvas.stamp(grid("BBB"), 0, 0);
    canvas.stamp(grid(".Cx"), 0, 0);
    expect(roles(canvas)).toEqual(["furBase", "costumeBase", undefined]);
  });

  it("zones resolve through the pattern with defaults", () => {
    const canvas = new PetCanvas(3, 1);
    canvas.stamp(grid("pms"), 0, 0, new PetPattern({ paws: "belly" }));
    expect(roles(canvas)).toEqual(["belly", "belly", "furBase"]);
  });

  it("stamping clips outside the canvas", () => {
    const canvas = new PetCanvas(2, 2);
    canvas.stamp(grid("BS\nWE"), 1, -1);
    expect(roles(canvas), "top row and right column fall outside").toEqual([undefined, "belly", undefined, undefined]);
  });

  it("outline uses direct neighbors so corners stay round", () => {
    const canvas = new PetCanvas(3, 3);
    canvas.stamp(grid("B"), 1, 1);
    const outlined = canvas.outlined();
    expect(outlined.role(1, 0)).toBe("outline");
    expect(outlined.role(0, 1)).toBe("outline");
    expect(outlined.role(0, 0), "diagonal corners stay empty").toBeUndefined();
    expect(outlined.role(1, 1)).toBe("furBase");
  });

  it("outline skips excluded effect pixels", () => {
    const canvas = new PetCanvas(3, 1);
    canvas.stamp(grid(".Z."), 0, 0);
    expect(roles(canvas.outlined("outline", ["effect"]))).toEqual([undefined, "effect", undefined]);
  });
});

describe("PetRenderer", () => {
  it("scales with exact pixel blocks", () => {
    const canvas = new PetCanvas(2, 1);
    canvas.stamp(grid("B."), 0, 0);
    const palette = new PetPalette({ furBase: hex("#FF0000") });
    const image = renderPet(canvas, palette, 3);
    expect(image.width).toBe(6);
    expect(image.height).toBe(3);
    expect([...image.data.slice(0, 4)]).toEqual([255, 0, 0, 255]);
    expect([...image.data.slice((2 * 6 + 2) * 4, (2 * 6 + 3) * 4)]).toEqual([255, 0, 0, 255]);
    expect(image.data[(2 * 6 + 3) * 4 + 3], "transparent half stays clear").toBe(0);
  });

  it("caches identical requests", () => {
    const renderer = new PetRenderCache(2);
    const canvas = sitting("tuxedo");
    const first = renderer.bitmap(canvas, breedPalette("tuxedo"));
    const second = renderer.bitmap(canvas, breedPalette("tuxedo"));
    expect(first).toBe(second);
    renderer.bitmap(canvas, breedPalette("calico"));
    renderer.bitmap(canvas, breedPalette("siamese"));
    expect(renderer.size, "oldest entry is evicted at capacity").toBe(2);
  });
});

describe("PetBreed", () => {
  it("catalog has every cat and dog breed", () => {
    expect(breedsOf("cat").length).toBe(11);
    expect(breedsOf("cat").at(-1)).toBe("britishLonghair");
    expect(breedsOf("dog")).toEqual([
      "goldenRetriever",
      "labrador",
      "frenchBulldog",
      "corgi",
      "dachshund",
      "beagle",
      "poodle",
      "shihTzu",
    ]);
  });

  it("dogs use distinct silhouettes where color alone is not enough", () => {
    const shapes: PetBreed[] = ["goldenRetriever", "labrador", "frenchBulldog", "corgi", "dachshund", "poodle", "shihTzu"];
    expect(new Set(shapes.map((breed) => silhouette(sitting(breed)))).size).toBe(shapes.length);
  });

  it("Sphynx has its own hairless silhouette", () => {
    const sphynx = sitting("sphynx");
    const outline = silhouette(sphynx);
    for (const other of breedsOf("cat")) {
      if (other === "sphynx") continue;
      expect(silhouette(sitting(other)), other).not.toBe(outline);
    }
    expect(contains(sphynx, "furAccent")).toBe(false);
    expect(contains(sphynx, "furSpot")).toBe(false);
    expect(contains(sphynx, "blush")).toBe(true);
    expect(contains(sphynx, "furShade"), "wrinkles are hinted with shading").toBe(true);
  });

  it("Scottish Fold loads as a gray cat with its own folded ear silhouette", () => {
    expect(PET_BREEDS.includes("scottishFold")).toBe(true);
    expect(breedSpecies("scottishFold")).toBe("cat");
    expect(breedDisplayName("scottishFold")).toBe("Scottish Fold");
    const profile = new PetProfile("Moon", "scottishFold");
    expect(PetProfile.fromJSON(JSON.parse(JSON.stringify(profile))).breed).toBe("scottishFold");

    // Gray by default: a low-saturation, mid-light coat that can be recolored.
    const fur = breedPalette("scottishFold").color("furBase");
    expect(Math.max(fur.red, fur.green, fur.blue) - Math.min(fur.red, fur.green, fur.blue)).toBeLessThan(30);
    expect(luminance(fur)).toBeGreaterThanOrEqual(0.3);
    expect(luminance(fur)).toBeLessThanOrEqual(0.7);
    const tinted = new PetProfile("", "scottishFold", { paletteOverrides: { furBase: hex("#F2A65A") } });
    const tintedBase = colorHex(tinted.palette.color("furBase"));
    expect(tinted.sittingCanvas().colors(tinted.palette).some((color) => color && colorHex(color) === tintedBase)).toBe(true);

    // Folded ears: one round dome centered over the face, no taller than any upright-eared cat.
    const fold = sitting("scottishFold");
    const top = bounds(fold).minY;
    const crown: number[] = [];
    for (let x = 0; x < fold.width; x++) if (fold.role(x, top) !== undefined) crown.push(x);
    const first = crown[0] ?? 0;
    const last = crown.at(-1) ?? 0;
    expect(crown.length, "one dome, no separate ear tips").toBe(last - first + 1);
    expect(first + last, "centered over the head").toBe(6 * 2 + 19);
    for (const other of breedsOf("cat")) {
      if (other === "scottishFold") continue;
      expect(top, other).toBeGreaterThanOrEqual(bounds(sitting(other)).minY);
      expect(silhouette(sitting(other))).not.toBe(silhouette(fold));
    }
    // Folded ears hide their pink insides.
    for (let y = 0; y < 14; y++) {
      for (let x = 0; x < fold.width; x++) expect(fold.role(x, y)).not.toBe("blush");
    }
  });

  it("Scottish Fold has the shared cat eyes in every animation", () => {
    const eyePixels = (canvas: PetCanvas): string[] => {
      const out: string[] = [];
      for (let y = 0; y < canvas.height; y++) {
        for (let x = 0; x < canvas.width; x++) {
          const role = canvas.role(x, y);
          if (role === "eye" || role === "eyeLight") out.push(`${x},${y},${roleSymbol(role)}`);
        }
      }
      return out;
    };
    const fold = new PetClipSet({ breed: "scottishFold" });
    const tabby = new PetClipSet({ breed: "orangeTabby" });
    for (const animation of PET_ANIMATIONS) {
      const plain = tabby.clip(animation).frames;
      fold.clip(animation).frames.forEach((frame, index) => {
        const other = plain[index];
        if (other) expect(eyePixels(frame.canvas), animation).toEqual(eyePixels(other.canvas));
      });
    }
  });

  it("Scottish Fold renders every animation in every costume", () => {
    const palette = breedPalette("scottishFold");
    const fur = colorHex(palette.color("furBase"));
    const looks = [
      { outfit: "none" as const, accessories: [] },
      ...PET_OUTFITS.slice(1).map((outfit) => ({ outfit, accessories: [] })),
      ...PET_ACCESSORIES.map((accessory) => ({ outfit: "none" as const, accessories: [accessory] })),
    ];
    for (const look of looks) {
      for (const animation of PET_ANIMATIONS) {
        const label = `${animation} ${look.outfit} ${look.accessories.join(",")}`;
        // A peek starts or ends hidden inside the notch.
        const shown = clip(animation, "scottishFold", look).frames.filter((frame) => frame.canvas.opaqueBounds);
        expect(shown.length, label).toBeGreaterThan(0);
        for (const frame of shown) {
          const has = frame.canvas.colors(palette).some((color) => color && colorHex(color) === fur);
          expect(has, `the gray fur shows: ${label}`).toBe(true);
        }
      }
    }
  });

  it("poodle has a curly coat, a topknot and a pom tail", () => {
    const poodle = sitting("poodle");
    for (const role of ["furBase", "furShade", "furAccent"] as const) expect(contains(poodle, role)).toBe(true);
    const top = bounds(poodle).minY;
    for (const other of ["goldenRetriever", "labrador", "beagle"] as const) {
      expect(top, other).toBeLessThan(bounds(sitting(other)).minY);
    }
    expect(bounds(poodle).maxX).toBeGreaterThan(bounds(sitting("goldenRetriever")).maxX);
  });

  it("Shih Tzu has a flowing coat, a topknot and big round eyes", () => {
    const shihTzu = sitting("shihTzu");
    const golden = sitting("goldenRetriever");
    const floor = FRAME_SIZE - 1;
    const width = (canvas: PetCanvas) => {
      let n = 0;
      for (let x = 0; x < canvas.width; x++) if (canvas.role(x, floor) !== undefined) n++;
      return n;
    };
    expect(width(shihTzu)).toBeGreaterThan(width(golden));
    const top = bounds(shihTzu).minY;
    for (const other of ["goldenRetriever", "labrador", "beagle"] as const) {
      expect(top, other).toBeLessThan(bounds(sitting(other)).minY);
    }
    expect(count(shihTzu, "eye")).toBeGreaterThan(count(golden, "eye"));
    for (const role of ["furBase", "furAccent", "belly"] as const) expect(contains(shihTzu, role)).toBe(true);
  });

  it("Shih Tzu tongue sits in a mouth with brown eyes", () => {
    const shihTzu = sitting("shihTzu");
    let framedTongue = false;
    for (let x = 1; x < shihTzu.width - 1; x++) {
      for (let y = 0; y < shihTzu.height; y++) {
        if (shihTzu.role(x, y) === "blush" && (shihTzu.role(x - 1, y) === "nose" || shihTzu.role(x + 1, y) === "nose")) {
          framedTongue = true;
        }
      }
    }
    expect(framedTongue).toBe(true);
    const palette = breedPalette("shihTzu");
    expect(luminance(palette.color("eye"))).toBeGreaterThan(luminance(palette.color("pupil")) + 0.05);
  });

  it("dark dogs still get the light rim", () => {
    const palette = breedPalette("dachshund");
    expect(silhouetteColors(sitting("dachshund"), palette)).toContainEqual(palette.rim);
  });

  it("the rim is a soft sheen in the coat's own hue", () => {
    for (const breed of ["blackCat", "tuxedo", "dachshund"] as const) {
      const palette = breedPalette(breed);
      const rim = palette.rim;
      expect(contrastRatio(luminance(rim), PET_BACKDROP_CEILING), breed).toBeGreaterThanOrEqual(PET_SILHOUETTE_CONTRAST);
      expect(luminance(rim), `the edge reads brighter than inner lines: ${breed}`).toBeGreaterThan(
        luminance(palette.sheen),
      );
      expect(luminance(rim), breed).toBeGreaterThan(luminance(palette.color("furBase")) * 4);
      expect(luminance(rim), breed).toBeLessThan(luminance(palette.color("eyeLight")) / 2);
      const channels = [rim.red, rim.green, rim.blue];
      expect(Math.max(...channels) - Math.min(...channels), breed).toBeLessThan(40);
    }
    const blackCatRim = breedPalette("blackCat").rim;
    expect(blackCatRim.blue).toBeGreaterThan(blackCatRim.red);
    const navy = new PetPalette({ furBase: hex("#14203A") }).rim;
    expect(navy.blue).toBeGreaterThan(navy.red);
  });

  it("black cat chest has a soft sheen so the coat is not a flat blob", () => {
    const palette = breedPalette("blackCat");
    const chest = palette.color(breedPattern("blackCat").role("chest"));
    expect(luminance(chest)).toBeGreaterThan(luminance(palette.color("furBase")));
    expect(luminance(chest), "still reads as a black cat").toBeLessThan(0.06);
  });

  it("every breed sits inside the frame with a margin", () => {
    for (const breed of PET_BREEDS) {
      const found = bounds(sitting(breed));
      expect(found.minX, breed).toBeGreaterThan(0);
      expect(found.maxX, breed).toBeLessThan(FRAME_SIZE - 1);
      expect(found.minY, breed).toBeGreaterThan(0);
      expect(found.maxY, `${breed} paws rest on the baseline`).toBe(FRAME_SIZE - 1);
    }
  });

  it("breeds with the same art still look different", () => {
    const looks = PET_BREEDS.map((breed) =>
      sitting(breed)
        .colors(breedPalette(breed))
        .map((color) => (color ? colorHex(color) : "-"))
        .join(","),
    );
    expect(new Set(looks).size).toBe(PET_BREEDS.length);
  });
});

describe("PetEyes", () => {
  it("every breed has a pupil and a white highlight", () => {
    for (const breed of PET_BREEDS) {
      const palette = breedPalette(breed);
      const canvas = sitting(breed);
      expect(contains(canvas, "pupil"), breed).toBe(true);
      expect(contains(canvas, "eyeLight"), breed).toBe(true);
      expect(luminance(palette.color("eyeLight")), `a white catchlight: ${breed}`).toBeGreaterThan(0.9);
      expect(luminance(palette.color("pupil")), `the pupil is never lighter than the iris: ${breed}`).toBeLessThan(
        luminance(palette.color("eye")) + 0.001,
      );
      expect(luminance(palette.color("pupil")), `a dark pupil: ${breed}`).toBeLessThan(0.15);
    }
  });

  it("pupils stand out from dark fur", () => {
    for (const breed of ["blackCat", "tuxedo", "dachshund"] as const) {
      const palette = breedPalette(breed);
      expect(palette.color("pupil"), breed).not.toEqual(new PetPalette({}).color("pupil"));
      expect(luminance(palette.color("pupil")), breed).toBeGreaterThan(luminance(palette.color("furBase")));
    }
  });

  it("dachshund eyes stay darker than its tan brows", () => {
    const palette = breedPalette("dachshund");
    expect(luminance(palette.color("eye")) * 2).toBeLessThan(luminance(palette.color("belly")));
  });

  it("pupils are round, not slits", () => {
    for (const breed of PET_BREEDS) {
      const canvas = sitting(breed);
      let widest = 0;
      for (let y = 0; y < canvas.height; y++) {
        let run = 0;
        for (let x = 0; x < canvas.width; x++) {
          run = canvas.role(x, y) === "pupil" ? run + 1 : 0;
          widest = Math.max(widest, run);
        }
      }
      expect(widest, breed).toBeGreaterThanOrEqual(2);
    }
  });

  it("closed eyes leave no pupil behind", () => {
    for (const breed of PET_BREEDS) {
      for (const eyes of ["closed", "sleepy", "happy", "squeezed"] as PetEyes[]) {
        const canvas = sitting(breed, { pose: petPose({ eyes }) });
        expect(contains(canvas, "pupil"), `${breed} ${eyes}`).toBe(false);
        expect(contains(canvas, "eyeLight"), `${breed} ${eyes}`).toBe(false);
      }
    }
  });
});

