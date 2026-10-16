import { describe, expect, it } from "vitest";
import {
  BUILT_IN_EDITIONS,
  BUNDLED_EDITION_FILES,
  TABBI_EDITION,
  namedEdition,
  resolveEdition,
} from "../../../src/core/editions/bundledEditions";
import {
  DEFAULT_EDITION_ID,
  decodeEdition,
  editionCatalog,
  editionRunsLocalTools,
  isAppStoreEdition,
  loadEditionFile,
  type Edition,
} from "../../../src/core/editions/edition";
import { EditionStorage } from "../../../src/core/editions/editionStorage";
import { BUNDLED_KITS } from "../../../src/core/kits/bundledKits";
import { kitLayout } from "../../../src/core/kits/kitApplication";
import { decodeKit, kitIssues, missingKitRequirements } from "../../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../../src/core/modules/moduleCatalog";
import { unknownModuleDescriptor } from "../../../src/core/modules/moduleDescriptor";
import { DEFAULT_KIT_ID } from "../../../src/core/kits/kitLibrary";
import { resolvedKitTicker } from "../../../src/core/settings/appSettings";
import { allTickerKinds, tickerKindModule } from "../../../src/core/ticker/tickerKind";
import { BUILT_IN_CATALOG } from "../../support/builtInCatalog";

function decode(json: string): Edition {
  const result = decodeEdition(json);
  if (!result.ok) throw new Error(JSON.stringify(result.error));
  return result.edition;
}

const edition = (fields: string) =>
  `{"formatVersion": 1, "id": "lsat", "name": "LSAT Notch", "bundleIdentifier": "dev.tabbi.LSAT", "defaultKitID": "medicine"${fields}}`;

function appStore(): Edition {
  const found = namedEdition("appstore");
  if (!found) throw new Error("no appstore edition");
  return found;
}

describe("Edition", () => {
  it("runs as Tabbi without an edition id", () => {
    const resolved = resolveEdition(undefined);
    expect(resolved).toEqual(TABBI_EDITION);
    expect(resolved.id).toBe(DEFAULT_EDITION_ID);
    expect(resolved.name).toBe("Tabbi");
    expect(resolved.bundleIdentifier).toBe("dev.tabbi.Tabbi");
    expect(resolved.defaultKitID).toBe(DEFAULT_KIT_ID);
    expect(resolved.icon).toBeUndefined();
    expect(resolveEdition("tabbi")).toEqual(TABBI_EDITION);
  });

  it("falls back to Tabbi for unknown or retired editions", () => {
    expect(resolveEdition("lawnotch")).toEqual(TABBI_EDITION);
    expect(resolveEdition("studynotch")).toEqual(TABBI_EDITION);
    expect(resolveEdition(42)).toEqual(TABBI_EDITION);
    expect(namedEdition("Tabbi")).toEqual(TABBI_EDITION);
    expect(namedEdition("")).toBeUndefined();
  });

  it("loads every edition file under its own name, starting with a bundled kit", () => {
    expect(BUNDLED_EDITION_FILES.map((file) => file.name)).toEqual(["appstore", "tabbi"]);
    for (const file of BUNDLED_EDITION_FILES) expect(loadEditionFile(file.name, file.text).ok, file.name).toBe(true);
    expect(BUILT_IN_EDITIONS.length).toBe(BUNDLED_EDITION_FILES.length);
    expect(BUILT_IN_EDITIONS[0]).toEqual(TABBI_EDITION);
    for (const distribution of ["direct", "appStore"] as const) {
      const editions = BUILT_IN_EDITIONS.filter((e) => e.distribution === distribution);
      expect(new Set(editions.map((e) => e.bundleIdentifier)).size).toBe(editions.length);
      expect(new Set(editions.map((e) => e.name)).size).toBe(editions.length);
    }
    for (const built of BUILT_IN_EDITIONS) expect(BUNDLED_KITS.get(built.defaultKitID), built.id).toBeDefined();
  });

  it("keeps every module in the direct download", () => {
    expect(TABBI_EDITION.distribution).toBe("direct");
    expect(isAppStoreEdition(TABBI_EDITION)).toBe(false);
    expect(editionRunsLocalTools(TABBI_EDITION)).toBe(true);
    expect(TABBI_EDITION.excludedModules).toEqual([]);
    const catalog = new ModuleCatalog([unknownModuleDescriptor("planner"), unknownModuleDescriptor("claudeAsk")]);
    const same = editionCatalog(TABBI_EDITION, catalog);
    expect(same.ids).toEqual(catalog.ids);
    expect(same.unavailableIDs.size).toBe(0);
  });

  it("makes the App Store edition Tabbi without AI Usage and Party", () => {
    const store = appStore();
    expect(isAppStoreEdition(store)).toBe(true);
    expect(editionRunsLocalTools(store)).toBe(false);
    expect(store.name).toBe(TABBI_EDITION.name);
    expect(store.bundleIdentifier).toBe(TABBI_EDITION.bundleIdentifier);
    expect(store.defaultKitID).toBe(DEFAULT_KIT_ID);
    expect(new Set(store.excludedModules)).toEqual(new Set(["claudeUsage", "party"]));
    expect(store.infoPlist.LSApplicationCategoryType).toBe("public.app-category.productivity");
    expect(resolveEdition("appstore")).toEqual(store);
    expect(resolveEdition(undefined, store)).toEqual(store);
    expect(resolveEdition("tabbi", store)).toEqual(TABBI_EDITION);
  });

  it("reads excluded modules and the distribution", () => {
    const custom = decode(edition(`, "distribution": "appStore", "excludedModules": ["anki"]`));
    expect(custom.distribution).toBe("appStore");
    expect(custom.excludedModules).toEqual(["anki"]);
    const plain = decode(edition(""));
    expect(plain.distribution).toBe("direct");
    expect(plain.excludedModules).toEqual([]);
  });

  it("makes a new edition just a file", () => {
    const lsat = decode(
      edition(`, "icon": "LSAT.icns", "infoPlist": {"NSAppleEventsUsageDescription": "LSAT Notch plays music."}`),
    );
    expect(lsat.id).toBe("lsat");
    expect(lsat.name).toBe("LSAT Notch");
    expect(lsat.icon).toBe("LSAT.icns");
    expect(lsat.infoPlist).toEqual({ NSAppleEventsUsageDescription: "LSAT Notch plays music." });
    expect(EditionStorage.forEdition(lsat).root).toBe("LSAT Notch");
  });

  it("refuses edition files that would break packaging", () => {
    const bad = [
      `{"formatVersion": 1, "id": "Bad Id", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}`,
      `{"formatVersion": 1, "id": "x", "name": "../X", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}`,
      `{"formatVersion": 1, "id": "x", "name": " ", "bundleIdentifier": "a.b", "defaultKitID": "medicine"}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "nodots", "defaultKitID": "medicine"}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": ""}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "icon": "../x.icns"}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "infoPlist": {"CFBundleIdentifier": "c.d"}}`,
      `{"id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s"}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "distribution": "beta"}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "excludedModules": ["../x"]}`,
      `{"formatVersion": 1, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s", "excludedModules": "anki"}`,
      "not json",
    ];
    for (const json of bad) {
      const result = decodeEdition(json);
      expect(result.ok, json).toBe(false);
      expect(!result.ok && result.error.kind, json).toBe("invalid");
    }
  });

  it("skips an edition from a newer format", () => {
    expect(
      decodeEdition(`{"formatVersion": 2, "id": "x", "name": "X", "bundleIdentifier": "a.b", "defaultKitID": "s"}`),
    ).toEqual({ ok: false, error: { kind: "unsupportedFormat", version: 2 } });
  });

  it("refuses a file whose id doesn't match its name", () => {
    expect(loadEditionFile("law", edition("")).ok).toBe(false);
    expect(loadEditionFile("lsat", edition("")).ok).toBe(true);
  });

  it("keeps each edition's files in its own folder", () => {
    const tabbi = EditionStorage.forEdition(TABBI_EDITION);
    const lsat = EditionStorage.forEdition(decode(edition("")));
    expect(tabbi.root).not.toBe(lsat.root);
    expect(tabbi.root).toBe("Tabbi");
    expect(tabbi.folder("Planner")).toBe("Tabbi/Planner");
    expect(tabbi.file("pet.json", "Pet")).toBe("Tabbi/Pet/pet.json");
    expect(lsat.folder("Kits")).toBe("LSAT Notch/Kits");
  });
});

describe("edition catalogs", () => {
  const storeCatalog = () => editionCatalog(appStore(), BUILT_IN_CATALOG);

  it("drops excluded modules and remembers them as unavailable", () => {
    const catalog = BUILT_IN_CATALOG.excluding(["claudeAsk", "chess"]);
    expect(catalog.contains("claudeAsk")).toBe(false);
    expect(BUILT_IN_CATALOG.isUnavailable("claudeAsk")).toBe(false);
    expect(catalog.excluding(["party"]).unavailableIDs).toEqual(new Set(["claudeAsk", "chess", "party"]));
  });

  it("never marks a module the catalog has as unavailable", () => {
    const catalog = new ModuleCatalog(BUILT_IN_CATALOG.descriptors, ["planner", "chess"]);
    expect(catalog.contains("planner")).toBe(true);
    expect(catalog.unavailableIDs).toEqual(new Set(["chess"]));
  });

  it("applies every bundled kit cleanly in the App Store edition", () => {
    const catalog = storeCatalog();
    expect(BUNDLED_KITS.kits.length).toBeGreaterThan(0);
    for (const kit of BUNDLED_KITS.kits) {
      expect(kitIssues(kit, catalog), kit.id).toEqual([]);
      expect(missingKitRequirements(kit, catalog), kit.id).toEqual([]);
      const layout = kitLayout(kit, catalog);
      expect(new Set(layout.order)).toEqual(new Set(catalog.ids));
      expect(layout.order.some((id) => appStore().excludedModules.includes(id))).toBe(false);
      expect(layout.tabs.length).toBeGreaterThan(0);
      const ticker = resolvedKitTicker(kit.defaults, catalog);
      expect(ticker?.has("party")).toBe(false);
      for (const kind of ticker ?? []) {
        const module = tickerKindModule(kind);
        expect(module === undefined || catalog.contains(module), kind).toBe(true);
      }
    }
  });

  it("keeps Ask AI in Essentials in the App Store edition", () => {
    const essentials = BUNDLED_KITS.get("essentials");
    expect(essentials).toBeDefined();
    if (!essentials) return;
    const full = kitLayout(essentials, BUILT_IN_CATALOG);
    const store = kitLayout(essentials, storeCatalog());
    expect(full.tabs).toContain("claudeAsk");
    expect(store.tabs).toEqual(full.tabs);
    expect(store.headerShortcuts).toEqual(full.headerShortcuts);
  });

  it("ignores answers that enable an excluded module", () => {
    const result = decodeKit(`{"formatVersion": 1, "id": "ai", "name": "AI", "modules": ["planner"],
      "defaults": {"ticker": ["claudeUsage", "party", "tasks"], "moduleSettings": {"claudeUsage": {"plan": "x"}}},
      "onboarding": [{"id": "q", "prompt": "Q", "options": [{"id": "a", "label": "A", "enables": ["claudeUsage"]}]}]}`);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const catalog = storeCatalog();
    expect(kitIssues(result.kit, catalog)).toEqual([]);
    expect(kitLayout(result.kit, catalog, { q: new Set(["a"]) }).enabled).toEqual(["planner"]);
    expect(resolvedKitTicker(result.kit.defaults, catalog)).toEqual(new Set(["tasks"]));
  });

  it("still reports typos in the App Store edition", () => {
    const result = decodeKit(`{"formatVersion": 1, "id": "typo", "name": "Typo", "modules": ["planner", "claudeAks"],
      "defaults": {"ticker": ["partty"]}}`);
    expect(result.ok && kitIssues(result.kit, storeCatalog())).toEqual([
      { kind: "unknownModule", id: "claudeAks" },
      { kind: "unknownTickerKind", value: "partty" },
    ]);
  });

  it("refuses a kit that requires an excluded module", () => {
    const result = decodeKit(`{"formatVersion": 1, "id": "usage", "name": "Usage", "modules": ["claudeUsage"],
      "requires": {"modules": ["claudeUsage"]}}`);
    expect(result.ok && missingKitRequirements(result.kit, storeCatalog())).toEqual(["claudeUsage"]);
  });

  it("offers no preview for an excluded module", () => {
    const kinds = allTickerKinds(storeCatalog());
    expect(kinds).not.toContain("party");
    expect(kinds).not.toContain("claudeUsage");
    expect(kinds).toContain("pet");
    expect(allTickerKinds(BUILT_IN_CATALOG)).toContain("party");
  });
});
