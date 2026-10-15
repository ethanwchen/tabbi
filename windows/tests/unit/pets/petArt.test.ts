import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import {
  PetArtFile,
  backFrameCount,
  auraFrameCount,
  bodyFrame,
  bodyFrameCount,
  headFrameCount,
  headGrid,
  petArt,
} from "../../../src/core/pets/petArt";
import { PropArt, WalkArt } from "../../../src/core/pets/petArtPieces";
import { breedDisplayName, breedHasTail, breedPalette, breedPattern, breedSpecies } from "../../../src/core/pets/petBreed";
import { animationTimeline } from "../../../src/core/pets/petClip";
import { PET_ANIMATIONS, PET_BODY_SHAPES, PET_BREEDS, PET_SPECIES } from "../../../src/core/pets/petKinds";
import { PET_PALETTE_ROLES, PetPalette, petColor, roleSymbol } from "../../../src/core/pets/petPalette";
import { PET_EYES, PET_MOUTHS, SITTING, petPose } from "../../../src/core/pets/petPose";
import { stillIndex } from "../../../src/core/pets/petTimeline";
import { PET_PATTERN_ZONES, SpriteGrid, zoneSymbol } from "../../../src/core/pets/spriteGrid";
import { loadRepoJson } from "../../support/fixtures";

// Port of PetArtTests.swift: the pets.v1 art, breed and animation files load,
// are checked on the way in, and agree with the JSON Schema. Every file is
// also validated against shared/schemas/pets.v1.schema.json with Ajv.

const FAMILIES = ["animations", "breeds", "cat", "costume", "dog", "effect", "paw", "prop", "tail", "walk"];
const ART_FOLDER = "Sources/TabbiKitCore/Pets/PetArt";

type Json = Record<string, unknown>;

function schema(): Json {
  return loadRepoJson<Json>("shared/schemas/pets.v1.schema.json");
}

function object(value: unknown): Json {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("not an object");
  return value as Json;
}

function decode(text: string): PetArtFile {
  return PetArtFile.decode(JSON.parse(text));
}

function grid(text: string): SpriteGrid {
  return SpriteGrid.parse(text);
}

function gridTexts(grids: readonly SpriteGrid[]): string[] {
  return grids.map((g) => g.text);
}

describe("PetArt", () => {
  it("every bundled art file loads", () => {
    const folder = fileURLToPath(new URL(`../../../../${ART_FOLDER}`, import.meta.url));
    const names = readdirSync(folder)
      .filter((name) => name.endsWith(".json"))
      .map((name) => name.slice(0, -".json".length))
      .sort();
    expect(names).toEqual(FAMILIES);
    for (const name of names) expect(() => PetArtFile.decode(loadRepoJson(`${ART_FOLDER}/${name}.json`)), name).not.toThrow();
  });

  it("every bundled art file validates against the pets.v1 schema", () => {
    const ajv = new Ajv2020({ allErrors: true });
    const validate = ajv.compile(schema());
    for (const name of FAMILIES) {
      const valid = validate(loadRepoJson(`${ART_FOLDER}/${name}.json`));
      expect(valid ? [] : validate.errors, name).toEqual([]);
    }
    expect(validate({ schema: "pets.v1", grids: { ear: ["B?"] } }), "a symbol outside the legend fails").toBe(false);
  });

  it("files hold their art", () => {
    expect(petArt("cat").grid("head").width).toBe(20);
    expect(petArt("walk").sequence("catTail").length).toBe(2);
    expect(petArt("costume").bodyItem("superheroCape").rise).toBe(5);
    expect(petArt("costume").bodyItem("scrubs").rise, "rise defaults to 0").toBe(0);
    expect(petArt("costume").faceItem("eyepatch").eyeRow).toBe(3);
    expect(petArt("costume").headItem("graduationCap").sitRow).toBe(5);
  });

  it("grid rows read as sprite text", () => {
    const file = decode('{"schema": "pets.v1", "grids": {"ear": [".ee.", "ePPe", "eBBe"]}}');
    expect(file.grid("ear").equals(grid(".ee.\nePPe\neBBe"))).toBe(true);
  });

  it("rejects another schema version", () => {
    expect(() => decode('{"schema": "pets.v2"}')).toThrow('Unsupported schema "pets.v2"; expected "pets.v1"');
  });

  it("names the broken grid", () => {
    expect(() => decode('{"schema": "pets.v1", "sequences": {"tail": [["BB"], ["BB", "B"]]}}')).toThrow(
      'Grid "tail[1]": Row 2 is 1 wide; expected 2',
    );
  });

  it("items read their loop frames", () => {
    const file = decode(`{"schema": "pets.v1", "itemFrameDuration": 0.2,
      "headItems": {"glint": {"grid": ["YY"], "sitRow": 0, "frames": [["LY"], ["YL"]]}},
      "bodyItems": {"medal": {"cat": ["Y"], "dog": ["Y"], "longDog": ["Y"], "walk": ["Y"], "walkLong": ["Y"],
        "frames": [{"cat": ["L"], "dog": ["L"], "longDog": ["L"], "walk": ["L"], "walkLong": ["L"]}]}}}`);
    expect(file.itemFrameDuration).toBe(0.2);
    const glint = file.headItem("glint");
    expect(headFrameCount(glint)).toBe(3);
    expect([0, 1, 2, 3].map((phase) => headGrid(glint, phase).text), "the still grid opens the loop, which wraps").toEqual([
      "YY",
      "LY",
      "YL",
      "YY",
    ]);
    const medal = file.bodyItem("medal");
    expect(bodyFrameCount(medal)).toBe(2);
    expect(bodyFrame(medal, 1).walkLong.text).toBe("L");
    expect(decode('{"schema": "pets.v1"}').itemFrameDuration).toBeUndefined();
  });

  it("back items read their placements and loops", () => {
    const family = (x: number, frames: string) => `{"x": ${x}, "y": -2, "frames": ${frames}}`;
    const two = '[["UU"], ["VV"]]';
    const wings = (
      [
        ["cat", -5],
        ["dog", -4],
        ["longDog", 12],
        ["walk", 11],
        ["walkLong", 10],
      ] as const
    )
      .map(([name, x]) => `"${name}": ${family(x, two)}`)
      .join(", ");
    const file = (body: string) => decode(`{"schema": "pets.v1", "backItems": {"wings": {${body}}}}`);
    const item = file(wings).backItem("wings");
    expect(backFrameCount(item)).toBe(2);
    expect(item.dog.x).toBe(-4);
    expect(item.walkLong.y).toBe(-2);
    expect(gridTexts(item.walk.frames)).toEqual(["UU", "VV"]);

    const uneven = wings.replace(`"walk": ${family(11, two)}`, `"walk": ${family(11, '[["UU"]]')}`);
    expect(() => file(uneven)).toThrow('Grid "wings.walk": 1 frames differ from the cat\'s 2');
    const resized = wings.replace(`"dog": ${family(-4, two)}`, `"dog": ${family(-4, '[["UU"], ["V"]]')}`);
    expect(() => file(resized)).toThrow('Grid "wings.dog.frames[1]": 1x1 differs from the item\'s 2x1 still grid');
  });

  it("reads aura items and rejects uneven loops", () => {
    const json =
      '{"schema": "pets.v1", "auraItems": {"petals": {' +
      '"front": {"x": 0, "y": 1, "frames": [["H."], [".H"]]}, "side": {"x": 2, "y": 0, "frames": [["Z."], [".Z"]]}}}}';
    const item = decode(json).auraItem("petals");
    expect(auraFrameCount(item)).toBe(2);
    expect(item.front.y).toBe(1);
    expect(item.side.x).toBe(2);
    expect(gridTexts(item.side.frames)).toEqual(["Z.", ".Z"]);
    expect(gridTexts(item.longDog.frames), "the dachshund shares the front loop by default").toEqual(gridTexts(item.front.frames));

    const ownLongDog = json.replace('"side":', '"longDog": {"x": 3, "y": 0, "frames": [["Y"], ["Y"]]}, "side":');
    expect(decode(ownLongDog).auraItem("petals").longDog.x).toBe(3);
    const unevenLongDog = json.replace('"side":', '"longDog": {"x": 3, "y": 0, "frames": [["Y"]]}, "side":');
    expect(() => decode(unevenLongDog)).toThrow('Grid "petals.longDog": 1 frames differ from the front\'s 2');

    const uneven = json.replace('[["Z."], [".Z"]]', '[["Z."]]');
    expect(() => decode(uneven)).toThrow('Grid "petals.side": 1 frames differ from the front\'s 2');
    const resized = json.replace('[".H"]', '["H"]');
    expect(() => decode(resized)).toThrow('Grid "petals.front.frames[1]": 1x1 differs from the item\'s 2x1 still grid');
  });

  it("rejects a loop frame of another size", () => {
    expect(() => decode('{"schema": "pets.v1", "headItems": {"glint": {"grid": ["YY"], "sitRow": 0, "frames": [["Y"]]}}}')).toThrow(
      'Grid "glint.frames[0]": 1x1 differs from the item\'s 2x1 still grid',
    );
    const body =
      '{"schema": "pets.v1", "bodyItems": {"medal": {"cat": ["Y"], "dog": ["Y"], "longDog": ["Y"], ' +
      '"walk": ["Y"], "walkLong": ["Y"], "frames": [{"cat": ["Y"], "dog": ["YY"], "longDog": ["Y"], ' +
      '"walk": ["Y"], "walkLong": ["Y"]}]}}}';
    expect(() => decode(body)).toThrow('Grid "medal.frames[0].dog": 2x1 differs from the item\'s 1x1 still grid');
    expect(() => decode('{"schema": "pets.v1", "itemFrameDuration": 0}')).toThrow('itemFrameDuration: unknown value "0"');
  });

  it("the breed file covers every case", () => {
    const breeds = petArt("breeds");
    expect(breeds.breedOrder).toEqual([...PET_BREEDS]);
    expect([...breeds.bodyShapes.keys()].sort()).toEqual([...PET_BODY_SHAPES].sort());
    expect(Object.keys(breeds.basePalette).sort()).toEqual([...PET_PALETTE_ROLES].sort());
  });

  it("breeds read their definitions", () => {
    const file = decode(`{"schema": "pets.v1",
      "bodyShapes": {"longDog": {"species": "dog"}},
      "breeds": [{"id": "dachshund", "name": "Wiener", "bodyShape": "longDog", "hasTail": false,
                  "palette": {"belly": "#C9803F"}, "pattern": {"paws": "belly"}}]}`);
    expect(file.species("longDog")).toBe("dog");
    expect(file.breed("dachshund")).toEqual({
      name: "Wiener",
      bodyShape: "longDog",
      hasTail: false,
      palette: { belly: petColor(0xc9, 0x80, 0x3f) },
      pattern: { paws: "belly" },
    });
    expect(breedDisplayName("corgi")).toBe("Corgi");
    expect(breedHasTail("corgi")).toBe(false);
    expect(breedSpecies("corgi")).toBe("dog");
    expect(breedPattern("calico").role("patchB")).toBe("furSpot");
    expect(breedPalette("calico").color("eye"), "unset roles keep the base color").toEqual(new PetPalette({}).color("eye"));
  });

  it("names the unknown breed value", () => {
    const json = `{"schema": "pets.v1", "breeds": [{"id": "corgi", "name": "Corgi", "bodyShape": "pointyEaredDog",
      "hasTail": false, "palette": {"furBase": "#E88D3C"}, "pattern": {"tail": "belly"}}]}`;
    expect(() => decode(json)).toThrow('breeds[0].pattern: unknown value "tail"');
    expect(() => decode('{"schema": "pets.v1", "basePalette": {"eye": "#12345"}}')).toThrow(
      'basePalette.eye: unknown value "#12345"',
    );
  });

  it("the animation file covers every case", () => {
    expect([...petArt("animations").animations.keys()].sort()).toEqual([...PET_ANIMATIONS].sort());
  });

  it("timelines reference real art", () => {
    for (const animation of PET_ANIMATIONS) {
      animationTimeline(animation).frames.forEach((frame, index) => {
        const label = `${animation}[${index}]`;
        for (const effect of frame.effects) {
          expect(petArt("effect").grids.has(effect.grid), `${label} effect ${effect.grid}`).toBe(true);
        }
        if (frame.steam !== undefined) {
          expect(frame.steam >= 0 && frame.steam < PropArt.steam().length, `${label} steam ${frame.steam}`).toBe(true);
        }
        if (frame.stance.kind === "walking") {
          const step = frame.stance.step;
          expect(step >= 0 && step < WalkArt.cycle.length, `${label} step ${step}`).toBe(true);
        }
      });
    }
  });

  it("timelines read their frames", () => {
    const file = decode(`{"schema": "pets.v1", "animations": {"nap": {"loops": true, "still": 1, "frames": [
      {"duration": 1},
      {"duration": 0.5, "pose": {"eyes": "sleepy", "prop": {"kind": "toy", "roll": 3, "bat": true}, "lift": 2},
       "stance": {"kind": "curled", "breath": 1}, "shiftY": -4, "steam": 1, "dust": true, "bubble": true,
       "effects": [{"grid": "zLarge", "x": 28, "y": {"head": -9}}]}
    ]}}}`);
    const timeline = file.timeline("nap");
    expect(timeline).toEqual({
      loops: true,
      still: 1,
      frames: [
        { duration: 1, pose: petPose(), stance: SITTING, shiftY: 0, effects: [], dust: false, bubble: false },
        {
          duration: 0.5,
          pose: petPose({ eyes: "sleepy", prop: { kind: "toy", roll: 3, bounce: 0, bat: true }, lift: 2 }),
          stance: { kind: "curled", breath: 1 },
          shiftY: -4,
          effects: [{ grid: "zLarge", x: { frame: 28 }, y: { head: -9 } }],
          steam: 1,
          dust: true,
          bubble: true,
        },
      ],
    });
    expect(stillIndex(timeline)).toBe(1);
    const oneShot = { loops: false, frames: timeline.frames };
    expect(stillIndex(oneShot), "a one-shot clip holds its last frame").toBe(1);
  });

  it("names the broken timeline value", () => {
    const error = (animations: string) => () => decode(`{"schema": "pets.v1", "animations": ${animations}}`);
    expect(error('{"dance": {"loops": true, "frames": [{"duration": 1}]}}')).toThrow('animations: unknown value "dance"');
    expect(error('{"sit": {"loops": true, "frames": [{"duration": 1, "pose": {"eyes": "wink"}}]}}')).toThrow(
      'animations.sit.frames[0].pose.eyes: unknown value "wink"',
    );
    expect(error('{"sit": {"loops": true, "frames": [{"duration": 0}]}}')).toThrow(
      'animations.sit.frames[0].duration: unknown value "0"',
    );
    expect(error('{"sit": {"loops": true, "still": 1, "frames": [{"duration": 1}]}}')).toThrow(
      'animations.sit.still: unknown value "1"',
    );
    expect(error('{"sit": {"loops": true, "frames": [{"duration": 1, "stance": {"kind": "rolling"}}]}}')).toThrow(
      'animations.sit.frames[0].stance.kind: unknown value "rolling"',
    );
  });

  it("the schema's poses match the port", () => {
    const properties = object(schema().properties);
    const names = object(object(properties.animations).propertyNames).enum;
    expect(names).toEqual([...PET_ANIMATIONS]);
    const pose = object(object(object(schema().$defs).pose).properties);
    expect(object(pose.eyes).enum).toEqual([...PET_EYES]);
    expect(object(pose.mouth).enum).toEqual([...PET_MOUTHS]);
  });

  it("the schema's roles and zones match the port", () => {
    const defs = object(schema().$defs);
    const roles = object(defs.role).enum;
    expect(roles).toEqual([...PET_PALETTE_ROLES]);
    expect(object(defs.zone).enum).toEqual([...PET_PATTERN_ZONES]);
    const properties = object(schema().properties);
    expect(object(properties.basePalette).required).toEqual(roles);
    const shape = object(object(properties.bodyShapes).additionalProperties);
    expect(object(object(shape.properties).species).enum).toEqual([...PET_SPECIES]);
  });

  it("the schema's row pattern matches the sprite legend", () => {
    const pattern = object(object(object(schema().$defs).grid).items).pattern;
    if (typeof pattern !== "string") expect.fail("a pattern");
    expect(pattern.startsWith("^[") && pattern.endsWith("]+$"), pattern).toBe(true);
    const allowed = new Set(pattern.slice(2, -3));
    const legend = new Set([".", " ", "x", ...PET_PALETTE_ROLES.map(roleSymbol), ...PET_PATTERN_ZONES.map(zoneSymbol)]);
    expect([...allowed].sort()).toEqual([...legend].sort());
    expect(allowed.size, "no symbol is listed twice").toBe(pattern.length - 5);
  });
});
