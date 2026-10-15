import { describe, expect, it } from "vitest";
import { isEmptyKitChange, kitChangePreview } from "../../../src/core/kits/kitChangePreview";
import { KitSettingsSchema, kitIssueDescription, kitSetting, type KitIssue } from "../../../src/core/kits/kitSettingsSchema";
import { decodeKit, kitIssues } from "../../../src/core/kits/kitValidation";
import type { KitManifest } from "../../../src/core/kits/kitManifest";
import type { JSONValue } from "../../../src/core/persistence/json";
import { appSettings } from "../../../src/core/settings/appSettings";
import { BUILT_IN_CATALOG, builtInLayout } from "../../support/builtInCatalog";

const schema = new KitSettingsSchema({
  enabled: kitSetting.bool,
  goal: kitSetting.number(1, 10),
  title: kitSetting.text(5),
  mode: kitSetting.choice(["fast", "slow"]),
  lines: kitSetting.lines(4, 2),
  nested: kitSetting.object({ level: kitSetting.number(0, 1) }),
  steps: kitSetting.list(kitSetting.object({ size: kitSetting.number(1, 3) }), 2),
});

function issues(json: string): KitIssue[] {
  return schema.issues(JSON.parse(json) as JSONValue, "moduleSettings.drill");
}

const invalid = (path: string, expected: string): KitIssue => ({ kind: "invalidModuleSetting", path, expected });
const unknown = (path: string): KitIssue => ({ kind: "unknownField", path });

function kit(json: string): KitManifest {
  const result = decodeKit(json);
  if (!result.ok) throw new Error(result.error.kind);
  return result.kit;
}

describe("KitSettingsSchema", () => {
  it("has no issues for values that fit", () => {
    expect(
      issues(`{"enabled": true, "goal": 10, "title": "Hello", "mode": "slow", "lines": ["a", "b"], "nested": {"level": 0.5}}`),
    ).toEqual([]);
    expect(issues(`{"lines": "one"}`)).toEqual([]);
    expect(issues("{}")).toEqual([]);
  });

  it("checks list items one by one", () => {
    expect(issues(`{"steps": [{"size": 1}, {"size": 3}]}`)).toEqual([]);
    expect(issues(`{"steps": [{"size": 1}, {"size": 9, "colour": "red"}]}`)).toEqual([
      unknown("moduleSettings.drill.steps[1].colour"),
      invalid("moduleSettings.drill.steps[1].size", "a number from 1 to 3"),
    ]);
    const tooMany = invalid("moduleSettings.drill.steps", "a list of up to 2 items");
    expect(issues(`{"steps": [{}, {}, {}]}`)).toEqual([tooMany]);
    expect(issues(`{"steps": {"size": 1}}`)).toEqual([tooMany]);
  });

  it("names wrong values by path in key order", () => {
    expect(issues(`{"title": "Too long", "mode": "medium", "goal": "7", "enabled": 1, "nested": {"level": 2}}`)).toEqual([
      invalid("moduleSettings.drill.enabled", "true or false"),
      invalid("moduleSettings.drill.goal", "a number from 1 to 10"),
      invalid("moduleSettings.drill.mode", 'one of "fast", "slow"'),
      invalid("moduleSettings.drill.nested.level", "a number from 0 to 1"),
      invalid("moduleSettings.drill.title", "text of at most 5 characters"),
    ]);
  });

  it("checks the count, length and type of lines", () => {
    const expected = "a line or a list of up to 2 lines, each at most 4 characters";
    for (const json of [`{"lines": ["a", "b", "c"]}`, `{"lines": ["a", "longer"]}`, `{"lines": ["a", 2]}`, `{"lines": "longer"}`]) {
      expect(issues(json), json).toEqual([invalid("moduleSettings.drill.lines", expected)]);
    }
  });

  it("reports unknown keys at any depth", () => {
    expect(issues(`{"gaol": 3, "nested": {"levle": 1}}`)).toEqual([
      unknown("moduleSettings.drill.gaol"),
      unknown("moduleSettings.drill.nested.levle"),
    ]);
    expect(issues(`["not", "an", "object"]`)).toEqual([invalid("moduleSettings.drill", "an object")]);
  });

  it("checks each module's section against its descriptor", () => {
    const manifest = kit(`{"formatVersion": 1, "id": "k", "name": "K", "modules": ["planner"],
      "defaults": {"moduleSettings": {
        "planner": {"planMode": "clever", "dayEndHour": 21, "reviewsFrist": true},
        "study": {"dailyGoalMinutes": 2000},
        "closet": {"coachLines": {"distraction": "Back to it?", "cheer": ["Go!"]}},
        "anki": {"anything": "goes"},
        "chess": {"elo": 1500}
      }}}`);
    expect(kitIssues(manifest, BUILT_IN_CATALOG)).toEqual([
      { kind: "unknownModuleSettings", id: "chess" },
      unknown("moduleSettings.closet.coachLines.cheer"),
      invalid("moduleSettings.planner.planMode", 'one of "local", "claude", "study"'),
      unknown("moduleSettings.planner.reviewsFrist"),
      invalid("moduleSettings.study.dailyGoalMinutes", "a number from 15 to 720"),
    ]);
  });

  it("says what happens in each warning", () => {
    expect(kitIssueDescription({ kind: "unknownModuleSettings", id: "chess" })).toBe(
      'Settings for unknown module "chess" will be ignored.',
    );
    expect(kitIssueDescription(invalid("moduleSettings.study.dailyGoalMinutes", "a number from 15 to 720"))).toBe(
      '"moduleSettings.study.dailyGoalMinutes" should be a number from 15 to 720; other values are skipped or kept in range.',
    );
    expect(kitIssueDescription({ kind: "unknownModule", id: "chess" })).toBe('Unknown module "chess" will be skipped.');
    expect(kitIssueDescription({ kind: "unknownTheme", value: "lava" })).toBe('Unknown theme "lava" will be ignored.');
  });

  it("formats large bounds with grouping, as the Mac does in English", () => {
    expect(new KitSettingsSchema({ elo: kitSetting.number(0, 3000) }).issues({ elo: -1 }, "s")).toEqual([
      invalid("s.elo", "a number from 0 to 3,000"),
    ]);
  });
});

describe("KitChangePreview", () => {
  it("lists tabs that turn on and off with their new permissions", () => {
    const current = appSettings({ modules: builtInLayout(["system", "focus", "planner"]) });
    const study = kit(`{"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner", "spotify", "claudeAsk"],
      "starterTasks": ["Plan the week", "  "]}`);
    const preview = kitChangePreview(study, current, BUILT_IN_CATALOG);
    expect(preview.tabs).toEqual(["planner", "spotify", "claudeAsk"]);
    expect(preview.turnsOn).toEqual(["spotify", "claudeAsk"]);
    expect(preview.turnsOff).toEqual(["system", "focus"]);
    expect(preview.newPermissions).toEqual(["automation", "claudeCLI"]);
    expect(preview.newNetworkAccess.map((access) => access.host)).toEqual(["i.scdn.co"]);
    expect(preview.starterTasks).toEqual(["Plan the week"]);
    expect(preview.changesNotchPreviews).toBe(false);
    expect(isEmptyKitChange(preview)).toBe(false);
  });

  it("follows the onboarding answers", () => {
    const current = appSettings({ modules: builtInLayout(["planner"]) });
    const manifest = kit(`{"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner"],
      "onboarding": [{"id": "music", "prompt": "Music?", "options": [
        {"id": "yes", "label": "Yes", "enables": ["spotify"], "tasks": ["Pick a playlist"]}]}]}`);
    expect(isEmptyKitChange(kitChangePreview(manifest, current, BUILT_IN_CATALOG))).toBe(true);
    const withMusic = kitChangePreview(manifest, current, BUILT_IN_CATALOG, { music: new Set(["yes"]) });
    expect(withMusic.turnsOn).toEqual(["spotify"]);
    expect(withMusic.newPermissions).toEqual(["automation"]);
    expect(withMusic.starterTasks).toEqual(["Pick a playlist"]);
  });

  it("lists only new hosts off this machine", () => {
    const current = appSettings({ modules: builtInLayout(["planner", "spotify"]) });
    const study = kit(`{"formatVersion": 1, "id": "med", "name": "Med", "modules": ["planner", "spotify", "anki", "party"]}`);
    const preview = kitChangePreview(study, current, BUILT_IN_CATALOG);
    expect(preview.turnsOn).toEqual(["anki", "party"]);
    expect(preview.newNetworkAccess).toEqual([{ host: "friends.example.com", purpose: "your presence and parties" }]);
  });

  it("notes when the closed-panel previews change", () => {
    const current = appSettings({ modules: builtInLayout(["planner"]) });
    const manifest = kit(`{"formatVersion": 1, "id": "deep", "name": "Deep", "modules": ["planner"], "defaults": {"ticker": ["focus"]}}`);
    expect(kitChangePreview(manifest, current, BUILT_IN_CATALOG).changesNotchPreviews).toBe(true);
  });
});
