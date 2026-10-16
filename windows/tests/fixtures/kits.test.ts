import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { BUNDLED_KIT_FILES, BUNDLED_KITS, isBundledKit } from "../../src/core/kits/bundledKits";
import { chosenAnswers, kitAccentModule, kitStarterTasks, type KitAnswers } from "../../src/core/kits/kitApplication";
import { isEmptyKitChange, kitChangePreview } from "../../src/core/kits/kitChangePreview";
import { DEFAULT_KIT_ID, RETIRED_KIT_IDS } from "../../src/core/kits/kitLibrary";
import { CURRENT_KIT_FORMAT_VERSION, kitModuleIDs, type KitManifest } from "../../src/core/kits/kitManifest";
import {
  KitSettingsSchema,
  kitIssueDescription,
  type KitIssue,
  type KitSettingType,
} from "../../src/core/kits/kitSettingsSchema";
import {
  KIT_LIMITS,
  decodeKit,
  kitErrorDescription,
  kitIssues,
  missingKitRequirements,
  type KitError,
} from "../../src/core/kits/kitValidation";
import { ModuleCatalog } from "../../src/core/modules/moduleCatalog";
import { MODULE_CATEGORIES, isLocalNetworkAccess, moduleDescriptor, type ModulePermission } from "../../src/core/modules/moduleDescriptor";
import { ModuleLayout } from "../../src/core/modules/moduleLayout";
import { appSettings, applyKit, resolvedKitTicker, usesKitDefaults, type AppSettings } from "../../src/core/settings/appSettings";
import { DEFAULT_NOTCH_PREVIEW } from "../../src/core/settings/notchPreviewSettings";
import { themeIdForKitValue } from "../../src/core/themes/themeCatalog";
import { allTickerKinds } from "../../src/core/ticker/tickerKind";
import { switchLanguage } from "../support/catalogs";
import { loadFixture } from "../support/fixtures";
import { goldenDiff } from "../support/goldenCompare";

/*
 * Replays shared/fixtures/kits (written by KitGoldenTests on the Mac): every
 * bundled kit plus edge and refused kits, read against the fixture's own
 * module catalogs, then applied to recorded settings. A refused kit has only
 * its error; a usable one has what was decoded, its warnings, and one result
 * per application (layout, settings, change preview).
 */

type SchemaNode =
  | { type: "bool" }
  | { type: "number"; minimum: number; maximum: number }
  | { type: "text"; maxLength: number }
  | { type: "choice"; values: string[] }
  | { type: "lines"; maxLength: number; maxCount: number }
  | { type: "object"; fields: Record<string, SchemaNode> }
  | { type: "list"; item: SchemaNode; maxCount: number };

interface CatalogModule {
  id: string;
  permissions: ModulePermission[];
  network: { host: string; isLocal: boolean; purpose: string }[];
  highlights: boolean;
  kitSettings?: SchemaNode;
}

interface Base {
  name: string;
  catalog: string;
  kitID: string;
  kitAnswers: Record<string, string[]>;
  order: string[];
  disabled: string[];
  disabledPreviews: string[];
  themeID: string;
}

interface KitCase {
  name: string;
  catalog: string;
  source: { file: string } | { json: string; padToBytes?: number };
  applications: { base: string; answers: Record<string, string[]> }[];
  error?: unknown;
  decoded?: unknown;
  validation?: unknown;
  applied: unknown[];
}

interface KitsFile {
  schema: string;
  version: number;
  limits: Record<string, number>;
  catalogs: { name: string; modules: CatalogModule[]; tickerKinds: string[]; unavailable: string[] }[];
  library: {
    bundledFiles: string[];
    bundledIDs: string[];
    defaultKitID: string;
    retiredKitIDs: Record<string, string>;
    lookups: { id?: string; kit?: string }[];
  };
  bases: Base[];
  cases: KitCase[];
}

const fixture = loadFixture<KitsFile>("kits/kits.json");

beforeAll(() => switchLanguage("en"));

function settingType(node: SchemaNode): KitSettingType {
  switch (node.type) {
    case "bool":
      return { type: "bool" };
    case "number":
      return { type: "number", min: node.minimum, max: node.maximum };
    case "text":
      return { type: "text", maxLength: node.maxLength };
    case "choice":
      return { type: "choice", values: node.values };
    case "lines":
      return { type: "lines", maxLength: node.maxLength, maxCount: node.maxCount };
    case "object":
      return { type: "object", fields: Object.fromEntries(Object.entries(node.fields).map(([key, value]) => [key, settingType(value)])) };
    case "list":
      return { type: "list", item: settingType(node.item), maxCount: node.maxCount };
  }
}

function schemaOf(node: SchemaNode | undefined): KitSettingsSchema | undefined {
  if (node === undefined) return undefined;
  const type = settingType(node);
  if (type.type !== "object") throw new Error("a kit settings schema is an object");
  return new KitSettingsSchema(type.fields);
}

/* The fixture's catalogs as ModuleCatalogs: only ids, permissions, hosts, highlights and kit settings matter to kits. */
const catalogs = new Map(
  fixture.catalogs.map((catalog) => [
    catalog.name,
    new ModuleCatalog(
      catalog.modules.map((module) =>
        moduleDescriptor({
          id: module.id,
          title: module.id,
          symbol: "square",
          category: MODULE_CATEGORIES.productivity,
          accent: { red: 0.5, green: 0.5, blue: 0.5 },
          permissions: module.permissions,
          network: module.network.map(({ host, purpose }) => ({ host, purpose })),
          highlightTitle: module.highlights ? module.id : undefined,
          kitSettings: schemaOf(module.kitSettings),
        }),
      ),
      catalog.unavailable,
    ),
  ]),
);

function catalogNamed(name: string): ModuleCatalog {
  const catalog = catalogs.get(name);
  if (catalog === undefined) throw new Error(`no catalog ${name}`);
  return catalog;
}

function answersOf(record: Record<string, string[]>): KitAnswers {
  return Object.fromEntries(Object.entries(record).map(([question, ids]) => [question, new Set(ids)]));
}

function sorted(values: Iterable<string>): string[] {
  return [...values].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

const bases = new Map(
  fixture.bases.map((base) => {
    const catalog = catalogNamed(base.catalog);
    const settings = appSettings({
      kitID: base.kitID,
      hasChosenKit: true,
      kitAnswers: answersOf(base.kitAnswers),
      modules: new ModuleLayout(base.order, base.disabled, catalog),
      notchPreview: { ...DEFAULT_NOTCH_PREVIEW, disabledKinds: new Set(base.disabledPreviews) },
      themeID: base.themeID,
    });
    return [base.name, settings];
  }),
);

function sourceText(source: KitCase["source"]): string {
  if ("file" in source) {
    const url = new URL(`../../../Sources/TabbiKitCore/Kits/Bundled/${source.file}`, import.meta.url);
    return readFileSync(fileURLToPath(url), "utf8");
  }
  const padding = source.padToBytes === undefined ? 0 : source.padToBytes - new TextEncoder().encode(source.json).length;
  return source.json + " ".repeat(Math.max(padding, 0));
}

function errorOutput(error: KitError): Record<string, unknown> {
  const message = kitErrorDescription(error);
  switch (error.kind) {
    case "malformed":
      return { kind: error.kind, reason: error.reason, message };
    case "unsupportedVersion":
    case "invalidFormatVersion":
      return { kind: error.kind, version: error.version, message };
    case "exceedsLimit":
      return { kind: error.kind, value: error.what, message };
    case "questionWithoutOptions":
    case "invalidID":
    case "reservedID":
      return { kind: error.kind, value: error.id, message };
    case "missingRequiredModules":
      return { kind: error.kind, modules: error.ids, message };
    case "tooLarge":
    case "emptyName":
    case "noModules":
      return { kind: error.kind, message };
  }
}

function decodedOutput(kit: KitManifest): Record<string, unknown> {
  const theme = kit.defaults.theme;
  return {
    formatVersion: kit.formatVersion,
    version: kit.version,
    requires: kit.requires.modules,
    id: kit.id,
    name: kit.name,
    summary: kit.summary,
    symbol: kit.symbol,
    accent: kit.accent,
    modules: kit.modules.map((entry) => ({ id: entry.id, enabled: entry.enabled })),
    moduleIDs: kitModuleIDs(kit),
    ticker: kit.defaults.ticker,
    theme,
    resolvedTheme: theme === undefined ? undefined : themeIdForKitValue(theme),
    moduleSettings: kit.defaults.moduleSettings,
    legacyFields: kit.defaults.legacyFields.map((field) => field.name),
    onboarding: kit.onboarding.map((question) => ({
      id: question.id,
      prompt: question.prompt,
      allowsMultiple: question.allowsMultiple,
      options: question.options.map((answer) => ({
        id: answer.id,
        label: answer.label,
        symbol: answer.symbol,
        enables: answer.enables,
        disables: answer.disables,
        tasks: answer.tasks,
      })),
    })),
    starterTasks: kit.starterTasks,
    pickerOrder: kit.pickerOrder,
    unknownFields: kit.unknownFields,
  };
}

function issueOutput(issue: KitIssue): Record<string, unknown> {
  const message = kitIssueDescription(issue);
  switch (issue.kind) {
    case "unknownModule":
    case "duplicateModule":
    case "unknownModuleSettings":
      return { kind: issue.kind, module: issue.id, message };
    case "unknownTickerKind":
    case "unknownTheme":
      return { kind: issue.kind, value: issue.value, message };
    case "duplicateQuestion":
      return { kind: issue.kind, question: issue.id, message };
    case "duplicateAnswer":
      return { kind: issue.kind, question: issue.question, answer: issue.answer, message };
    case "unknownField":
      return { kind: issue.kind, path: issue.path, message };
    case "invalidModuleSetting":
      return { kind: issue.kind, path: issue.path, expected: issue.expected, message };
    case "legacyField":
      return { kind: issue.kind, value: issue.field.name, module: issue.field.module, path: issue.field.newPath, message };
  }
}

function validationOutput(kit: KitManifest, catalog: ModuleCatalog): Record<string, unknown> {
  const ticker = resolvedKitTicker(kit.defaults, catalog);
  return {
    issues: kitIssues(kit, catalog).map(issueOutput),
    missingRequirements: missingKitRequirements(kit, catalog),
    reservedID: isBundledKit(kit.id),
    accentModule: kitAccentModule(kit, catalog),
    resolvedTicker: ticker === undefined ? undefined : allTickerKinds(catalog).filter((kind) => ticker.has(kind)),
  };
}

function settingsOutput(settings: AppSettings): Record<string, unknown> {
  return {
    kitID: settings.kitID,
    hasChosenKit: settings.hasChosenKit,
    kitAnswers: Object.fromEntries(Object.entries(settings.kitAnswers).map(([question, ids]) => [question, sorted(ids)])),
    disabledPreviews: sorted(settings.notchPreview.disabledKinds),
    themeID: settings.themeID,
  };
}

function appliedOutput(kit: KitManifest, catalog: ModuleCatalog, base: AppSettings, answers: KitAnswers): Record<string, unknown> {
  const settings = applyKit(base, kit, catalog, answers);
  const preview = kitChangePreview(kit, base, catalog, answers);
  return {
    chosenAnswers: chosenAnswers(kit, answers).map((answer) => answer.id),
    layout: { order: settings.modules.order, enabled: settings.modules.enabled },
    starterTasks: kitStarterTasks(kit, answers),
    settings: settingsOutput(settings),
    baseUsesDefaults: usesKitDefaults(base, kit, catalog),
    preview: {
      tabs: preview.tabs,
      turnsOn: preview.turnsOn,
      turnsOff: preview.turnsOff,
      newPermissions: preview.newPermissions,
      newNetworkAccess: preview.newNetworkAccess.map((access) => ({
        host: access.host,
        isLocal: isLocalNetworkAccess(access),
        purpose: access.purpose,
      })),
      starterTasks: preview.starterTasks,
      changesNotchPreviews: preview.changesNotchPreviews,
      isEmpty: isEmptyKitChange(preview),
    },
  };
}

function expectGolden(actual: unknown, expected: unknown): void {
  expect(goldenDiff(actual, expected)).toBeUndefined();
}

describe("kits golden fixture", () => {
  it("is the version this suite reads", () => {
    expect(fixture.schema).toBe("tabbi.kits.golden");
    expect(fixture.version).toBe(1);
  });

  it("has the same limits and format version", () => {
    expectGolden({ ...KIT_LIMITS, currentFormatVersion: CURRENT_KIT_FORMAT_VERSION }, fixture.limits);
  });

  it("builds each catalog's previews in rotation order", () => {
    for (const catalog of fixture.catalogs) {
      expect(allTickerKinds(catalogNamed(catalog.name)), catalog.name).toEqual(catalog.tickerKinds);
      expect(sorted(catalogNamed(catalog.name).unavailableIDs), catalog.name).toEqual(sorted(catalog.unavailable));
    }
  });

  it("ships the same kits and looks them up the same way", () => {
    const library = fixture.library;
    expect(BUNDLED_KIT_FILES.map((file) => `${file.name}.json`)).toEqual(library.bundledFiles);
    expect(BUNDLED_KITS.ids).toEqual(library.bundledIDs);
    expect(DEFAULT_KIT_ID).toBe(library.defaultKitID);
    expect(RETIRED_KIT_IDS).toEqual(library.retiredKitIDs);
    for (const lookup of library.lookups) {
      expect(BUNDLED_KITS.kit(lookup.id)?.id, JSON.stringify(lookup)).toBe(lookup.kit);
    }
  });

  it("reads the bases like saved settings", () => {
    for (const base of fixture.bases) {
      const settings = bases.get(base.name);
      expect(settings?.modules.order, base.name).toEqual(base.order);
      expect(sorted(settings?.modules.disabled ?? []), base.name).toEqual(sorted(base.disabled));
    }
  });

  it("covers every case", () => {
    expect(fixture.cases.length).toBe(71);
  });

  for (const testCase of fixture.cases) {
    it(`replays ${testCase.name}`, () => {
      const catalog = catalogNamed(testCase.catalog);
      const result = decodeKit(sourceText(testCase.source));
      if (!result.ok) {
        expectGolden(errorOutput(result.error), testCase.error);
        expect(testCase.decoded).toBeUndefined();
        return;
      }
      expect(testCase.error, "the Mac refused this kit").toBeUndefined();
      const kit = result.kit;
      expectGolden(decodedOutput(kit), testCase.decoded);
      expectGolden(validationOutput(kit, catalog), testCase.validation);
      const applied = testCase.applications.map((application) => {
        const base = bases.get(application.base);
        if (base === undefined) throw new Error(`no base ${application.base}`);
        return appliedOutput(kit, catalog, base, answersOf(application.answers));
      });
      expectGolden(applied, testCase.applied);
    });
  }
});
