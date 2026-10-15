import { describe, expect, it } from "vitest";
import {
  KIT_LEGACY_FIELDS,
  encodeKitManifest,
  kitAnswer,
  kitDefaults,
  kitManifest,
  kitModuleEntry,
  kitModuleIDs,
  kitModuleSettings,
  kitQuestion,
  readKitManifest,
  type KitManifest,
} from "../../../src/core/kits/kitManifest";
import {
  KIT_LIMITS,
  decodeKit,
  kitErrorDescription,
  kitIssues,
  missingKitRequirements,
  type KitError,
} from "../../../src/core/kits/kitValidation";
import { kitIssueDescription, type KitIssue } from "../../../src/core/kits/kitSettingsSchema";
import { stringifyJSON } from "../../../src/core/persistence/json";
import { resolvedKitTicker } from "../../../src/core/settings/appSettings";
import { BUILT_IN_CATALOG, PET_BREEDS, STUDY_METHODS } from "../../support/builtInCatalog";

function decode(json: string): KitManifest {
  const result = decodeKit(json);
  if (!result.ok) throw new Error(kitErrorDescription(result.error));
  return result.kit;
}

function refusal(json: string): KitError | undefined {
  const result = decodeKit(json);
  return result.ok ? undefined : result.error;
}

function issues(kit: KitManifest): KitIssue[] {
  return kitIssues(kit, BUILT_IN_CATALOG);
}

/* Reads a kit section the way the defaults decoder does, for tests that start from `defaults` JSON. */
function defaultsFrom(json: string) {
  return readKitManifest({ formatVersion: 1, id: "k", name: "K", modules: ["planner"], defaults: JSON.parse(json) })
    .defaults;
}

describe("kit decoding", () => {
  it("fills optional fields with defaults", () => {
    const kit = decode(`{"formatVersion": 1, "id": "tiny", "name": "Tiny", "modules": ["planner"]}`);
    expect(kitModuleIDs(kit)).toEqual(["planner"]);
    expect(kit.summary).toBe("");
    expect(kit.symbol).toBe("square.grid.2x2");
    expect(kit.defaults).toEqual(kitDefaults());
    expect(kit.onboarding).toEqual([]);
    expect(kit.starterTasks).toEqual([]);
  });

  it("accepts bare ids and objects as module entries", () => {
    const kit = decode(`{"formatVersion": 1, "id": "k", "name": "K",
      "modules": ["planner", {"id": "system", "enabled": false}, {"id": "spotify"}]}`);
    expect(kit.modules).toEqual([kitModuleEntry("planner"), kitModuleEntry("system", false), kitModuleEntry("spotify")]);
  });

  it("round-trips through JSON", () => {
    const kit = kitManifest({
      id: "round-trip",
      name: "Round trip",
      summary: "s",
      symbol: "star",
      accent: "planner",
      modules: [kitModuleEntry("planner"), kitModuleEntry("anki", false)],
      defaults: kitDefaults({
        ticker: ["focus"],
        theme: "notch",
        moduleSettings: {
          study: { methods: ["pomodoro"] },
          closet: { pet: { breed: "corgi", name: "Biscuit" } },
          anki: { deck: "Step 1", goal: 200 },
        },
      }),
      onboarding: [kitQuestion({ id: "q", prompt: "?", options: [kitAnswer({ id: "a", label: "A", enables: ["anki"] })] })],
      starterTasks: ["Read"],
    });
    expect(decode(JSON.stringify(encodeKitManifest(kit)))).toEqual(kit);
  });

  it("encodes enabled entries as bare ids", () => {
    const kit = kitManifest({
      id: "k",
      name: "K",
      summary: "",
      symbol: "star",
      modules: [kitModuleEntry("planner"), kitModuleEntry("system", false)],
    });
    expect(stringifyJSON(encodeKitManifest(kit).modules, { sortedKeys: true })).toBe(
      `["planner",{"enabled":false,"id":"system"}]`,
    );
  });

  it("refuses a newer format", () => {
    expect(refusal(`{"formatVersion": 2, "id": "k", "name": "K", "modules": ["planner"]}`)).toEqual({
      kind: "unsupportedVersion",
      version: 2,
    });
  });

  it("refuses bad ids and names and empty module lists", () => {
    expect(refusal(`{"formatVersion": 1, "id": "My Kit", "name": "K", "modules": ["planner"]}`)).toEqual({
      kind: "invalidID",
      id: "My Kit",
    });
    expect(refusal(`{"formatVersion": 1, "id": "k", "name": "  ", "modules": ["planner"]}`)).toEqual({
      kind: "emptyName",
    });
    expect(refusal(`{"formatVersion": 1, "id": "k", "name": "K", "modules": []}`)).toEqual({ kind: "noModules" });
  });

  it("explains what is wrong with a malformed file", () => {
    expect(refusal("not json")).toEqual({ kind: "malformed", reason: "not valid JSON" });
    expect(refusal(`{"formatVersion": 1, "id": "k", "modules": ["planner"]}`)).toEqual({
      kind: "malformed",
      reason: 'missing "name"',
    });
    expect(refusal(`{"formatVersion": 1, "id": "k", "name": "K", "modules": [3]}`)).toEqual({
      kind: "malformed",
      reason: "unexpected value at modules.[0]",
    });
    expect(refusal(`[1]`)).toEqual({ kind: "malformed", reason: "unexpected value at the top level" });
    expect(
      refusal(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"],
        "onboarding": [{"id": "q", "prompt": 5, "options": []}]}`),
    ).toEqual({ kind: "malformed", reason: "unexpected value at onboarding.[0].prompt" });
  });

  it("never throws, whatever the input", () => {
    for (const text of ["", "null", "42", "{}", `{"formatVersion": "1"}`, `{"formatVersion": 1.5}`]) {
      expect(decodeKit(text).ok).toBe(false);
    }
  });
});

describe("kit defaults", () => {
  it("drops unknown previews when resolving the ticker", () => {
    expect(resolvedKitTicker(kitDefaults({ ticker: ["focus", "weather"] }), BUILT_IN_CATALOG)).toEqual(new Set(["focus"]));
    expect(resolvedKitTicker(kitDefaults(), BUILT_IN_CATALOG)).toBeUndefined();
  });

  it("moves old top-level fields into their module sections", () => {
    const defaults = defaultsFrom(`{"studyMethods": ["flowtime"], "studyMethod": "flowtime",
      "focusSounds": [{"sound": "rain"}], "pet": {"breed": "corgi"},
      "moduleSettings": {"study": {"dailyGoalMinutes": 60}}}`);
    expect(defaults.moduleSettings).toEqual({
      study: { methods: ["flowtime"], method: "flowtime", dailyGoalMinutes: 60 },
      focus: { sounds: [{ sound: "rain" }] },
      closet: { pet: { breed: "corgi" } },
    });
    expect(defaults.legacyFields.map((field) => field.name)).toEqual(["studyMethods", "studyMethod", "focusSounds", "pet"]);
  });

  it("lets a new module section key win over its old name", () => {
    const defaults = defaultsFrom(`{"studyMethod": "flowtime", "moduleSettings": {"study": {"method": "ultradian"}}}`);
    expect(kitModuleSettings(defaults, "study")).toEqual({ method: "ultradian" });
    expect(defaults.legacyFields.map((field) => field.name)).toEqual(["studyMethod"]);
  });

  it("encodes only the module sections", () => {
    const kit = readKitManifest({
      formatVersion: 1,
      id: "k",
      name: "K",
      modules: ["planner"],
      defaults: { focusSounds: [{ sound: "rain", level: 0.5 }] },
    });
    expect(stringifyJSON(encodeKitManifest(kit).defaults, { sortedKeys: true })).toBe(
      `{"moduleSettings":{"focus":{"sounds":[{"level":0.5,"sound":"rain"}]}}}`,
    );
  });

  it("hands each module its own section with JSON types kept", () => {
    const defaults = defaultsFrom(`{"moduleSettings": {"anki": {"deck": "Step 1", "goal": 200,
      "list": [null, true, 1.5, "x", [false], {"k": 2}]}}}`);
    expect(kitModuleSettings(defaults, "anki")).toEqual({
      deck: "Step 1",
      goal: 200,
      list: [null, true, 1.5, "x", [false], { k: 2 }],
    });
    expect(kitModuleSettings(defaults, "planner")).toBeUndefined();
  });
});

describe("kit safety", () => {
  const base = (fields = "") => `{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"]${fields}}`;

  it("refuses format versions below one", () => {
    expect(refusal(`{"formatVersion": 0, "id": "k", "name": "K", "modules": ["planner"]}`)).toEqual({
      kind: "invalidFormatVersion",
      version: 0,
    });
    expect(refusal(`{"formatVersion": -3, "id": "k", "name": "K", "modules": ["planner"]}`)).toEqual({
      kind: "invalidFormatVersion",
      version: -3,
    });
  });

  it("refuses files over the size limit", () => {
    expect(refusal(base() + " ".repeat(KIT_LIMITS.maxFileBytes))).toEqual({ kind: "tooLarge" });
  });

  it("refuses kits past the caps", () => {
    const modules = Array.from({ length: KIT_LIMITS.maxModules + 1 }, (_, i) => `"m${i}"`).join(",");
    expect(refusal(`{"formatVersion": 1, "id": "k", "name": "K", "modules": [${modules}]}`)).toEqual({
      kind: "exceedsLimit",
      what: "more than 16 modules",
    });
    const tasks = Array.from({ length: KIT_LIMITS.maxTasks + 1 }, (_, i) => `"Task ${i}"`).join(",");
    expect(refusal(base(`, "starterTasks": [${tasks}]`))).toEqual({
      kind: "exceedsLimit",
      what: "more than 20 starter tasks",
    });
    const longName = "x".repeat(KIT_LIMITS.maxNameLength + 1);
    expect(refusal(`{"formatVersion": 1, "id": "k", "name": "${longName}", "modules": ["planner"]}`)).toEqual({
      kind: "exceedsLimit",
      what: "a name longer than 80 characters",
    });
    const longTask = "x".repeat(KIT_LIMITS.maxTaskLength + 1);
    expect(
      refusal(base(`, "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "tasks": ["${longTask}"]}]}]`)),
    ).toEqual({ kind: "exceedsLimit", what: "a task title longer than 120 characters" });
    const options = Array.from({ length: KIT_LIMITS.maxOptions + 1 }, (_, i) => `{"id": "a${i}", "label": "A"}`).join(",");
    expect(refusal(base(`, "onboarding": [{"id": "q", "prompt": "?", "options": [${options}]}]`))).toEqual({
      kind: "exceedsLimit",
      what: 'more than 8 answers in question "q"',
    });
    const longID = "a".repeat(KIT_LIMITS.maxIDLength + 1);
    expect(refusal(`{"formatVersion": 1, "id": "${longID}", "name": "K", "modules": ["planner"]}`)).toEqual({
      kind: "invalidID",
      id: longID,
    });
  });

  it("counts characters the way Swift does, by grapheme", () => {
    /* A family emoji is one character to Swift, though several code points; written as escapes. */
    const family = "\u{1F468}‍\u{1F469}‍\u{1F467}";
    expect(decodeKit(base(`, "summary": "${family.repeat(160)}"`)).ok).toBe(true);
    expect(refusal(base(`, "summary": "${family.repeat(161)}"`))).toEqual({
      kind: "exceedsLimit",
      what: "a summary longer than 160 characters",
    });
  });

  it("refuses questions without answers", () => {
    expect(refusal(base(`, "onboarding": [{"id": "q", "prompt": "?", "options": []}]`))).toEqual({
      kind: "questionWithoutOptions",
      id: "q",
    });
  });

  it("warns about duplicate answers and out-of-range levels", () => {
    const kit = decode(
      base(`, "defaults": {"moduleSettings": {"focus": {"sounds": [{"sound": "rain", "level": 1.5}, {"sound": "brown", "level": 0.5}]}}},
      "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A"}, {"id": "a", "label": "B"}]}]`),
    );
    expect(issues(kit)).toEqual([
      { kind: "duplicateAnswer", question: "q", answer: "a" },
      { kind: "invalidModuleSetting", path: "moduleSettings.focus.sounds[0].level", expected: "a number from 0 to 1" },
    ]);
  });

  it("warns about fields the format does not read", () => {
    const kit = decode(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner", {"id": "system", "on": false}],
      "colour": "red",
      "defaults": {"tickers": ["focus"], "moduleSettings": {"anything": {"goes": true}}},
      "onboarding": [{"id": "q", "prompt": "?", "options": [{"id": "a", "label": "A", "lable": "B"}]}],
      "requires": {"modules": ["planner"], "app": "2.0"}}`);
    expect(kit.unknownFields).toEqual([
      "colour",
      "defaults.tickers",
      "modules[1].on",
      "onboarding[0].options[0].lable",
      "requires.app",
    ]);
    expect(issues(kit).filter((issue) => issue.kind === "unknownField").length).toBe(5);
  });

  it("still reads old top-level fields with a warning and checks them by their module", () => {
    const kit = decode(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["study"],
      "defaults": {"studyMethods": ["pomodoro", "telepathy"], "pet": {"breed": "dragon", "nmae": "Biscuit"}}}`);
    expect(kitModuleSettings(kit.defaults, "study")).toEqual({ methods: ["pomodoro", "telepathy"] });
    const methods = STUDY_METHODS.map((method) => `"${method}"`).join(", ");
    const breeds = PET_BREEDS.map((breed) => `"${breed}"`).join(", ");
    const [studyMethods, , , pet] = KIT_LEGACY_FIELDS;
    expect(studyMethods && pet).toBeTruthy();
    if (!studyMethods || !pet) return;
    expect(issues(kit)).toEqual([
      { kind: "legacyField", field: studyMethods },
      { kind: "legacyField", field: pet },
      { kind: "invalidModuleSetting", path: "moduleSettings.closet.pet.breed", expected: `one of ${breeds}` },
      { kind: "unknownField", path: "moduleSettings.closet.pet.nmae" },
      { kind: "invalidModuleSetting", path: "moduleSettings.study.methods[1]", expected: `one of ${methods}` },
    ]);
    expect(kitIssueDescription({ kind: "legacyField", field: studyMethods })).toBe(
      '"defaults.studyMethods" has moved to "defaults.moduleSettings.study.methods". It still works for now.',
    );
  });

  it("has no issues for a kit with every known field", () => {
    const kit = decode(base(`, "version": "1.3", "requires": {"modules": ["planner"]}, "summary": "s"`));
    expect(kit.version).toBe("1.3");
    expect(kit.requires).toEqual({ modules: ["planner"] });
    expect(issues(kit)).toEqual([]);
    expect(missingKitRequirements(kit, BUILT_IN_CATALOG)).toEqual([]);
    expect(decode(JSON.stringify(encodeKitManifest(kit)))).toEqual(kit);
  });

  it("lists missing requirements once", () => {
    const kit = decode(base(`, "requires": {"modules": ["leetcode", "planner", "leetcode"]}`));
    expect(missingKitRequirements(kit, BUILT_IN_CATALOG)).toEqual(["leetcode"]);
  });

  it("describes every refusal in the Mac's words", () => {
    expect(kitErrorDescription({ kind: "malformed", reason: "not valid JSON" })).toBe(
      "This isn't a valid kit file (not valid JSON).",
    );
    expect(kitErrorDescription({ kind: "unsupportedVersion", version: 2 })).toBe(
      "This kit needs a newer Tabbi (format 2, this version reads 1).",
    );
    expect(kitErrorDescription({ kind: "tooLarge" })).toBe("The kit file is larger than 64 KB.");
    expect(kitErrorDescription({ kind: "missingRequiredModules", ids: ["chess", "go"] })).toBe(
      'This kit needs a newer Tabbi with "chess", "go".',
    );
    expect(kitErrorDescription({ kind: "reservedID", id: "medicine" })).toBe(
      'The kit id "medicine" belongs to a built-in kit. Give your kit its own id.',
    );
  });
});
