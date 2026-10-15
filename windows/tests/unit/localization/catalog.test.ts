import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { buildStrings, CATALOGS, LANGUAGES as SCRIPT_LANGUAGES } from "../../../scripts/build-strings.mjs";
import { catalogIssues, describeIssue } from "../../../src/core/localization/audit";
import type { StringCatalog } from "../../../src/core/localization/catalog";
import { LANGUAGES, SOURCE_LANGUAGE } from "../../../src/core/localization/languages";
import { macCatalog, tableFor, windowsCatalog } from "./catalogs";

/* The languages a key lacks: the source language counts as present, since the key is its text. */
function missingLanguages(catalog: StringCatalog, key: string): string[] {
  const entry = catalog.strings[key];
  return LANGUAGES.filter((language) => language !== SOURCE_LANGUAGE && !entry?.localizations?.[language]);
}

const catalogs: [string, StringCatalog][] = [
  ["Localizable.xcstrings", macCatalog],
  ["Windows.xcstrings", windowsCatalog],
];

describe("the String Catalogs", () => {
  it("are in the source language the app expects", () => {
    expect(macCatalog.sourceLanguage).toBe(SOURCE_LANGUAGE);
    expect(windowsCatalog.sourceLanguage).toBe(SOURCE_LANGUAGE);
    expect(Object.keys(macCatalog.strings).length).toBeGreaterThan(1000);
  });

  it.each(catalogs)("%s has every key in all 12 languages", (_name, catalog) => {
    const gaps = Object.keys(catalog.strings)
      .map((key) => ({ key, missing: missingLanguages(catalog, key) }))
      .filter((gap) => gap.missing.length > 0);
    expect(gaps).toEqual([]);
  });

  it.each(catalogs)("%s passes the Mac's audit: translated, with the English specifiers", (_name, catalog) => {
    expect(catalogIssues(catalog, LANGUAGES).map(describeIssue)).toEqual([]);
  });

  it("keeps Windows-only keys out of the Mac's catalog", () => {
    const shared = Object.keys(windowsCatalog.strings).filter((key) => key in macCatalog.strings);
    expect(shared).toEqual([]);
    expect(Object.keys(windowsCatalog.strings)).toEqual(
      expect.arrayContaining([
        "Open Tabbi",
        "Quit Tabbi",
        "Another app is using Ctrl+Alt+Space, so open Tabbi from its icon in the tray.",
        "This tab arrives in a later Windows build.",
      ]),
    );
  });
});

describe("build-strings.mjs", () => {
  const output = mkdtempSync(join(tmpdir(), "tabbi-strings-"));
  afterAll(() => rmSync(output, { recursive: true, force: true }));

  it("ships the same languages as the app, from both catalogs", () => {
    expect([...SCRIPT_LANGUAGES]).toEqual([...LANGUAGES]);
    expect(CATALOGS).toHaveLength(2);
  });

  it("writes one table per language, the same the core flattens", () => {
    const written = buildStrings({ output });
    expect(written).toHaveLength(LANGUAGES.length);
    for (const language of LANGUAGES) {
      const table: unknown = JSON.parse(readFileSync(join(output, `${language}.json`), "utf8"));
      expect(table, language).toEqual(tableFor(language));
    }
  });

  it("leaves out text that is just the key, and keeps English plurals", () => {
    const english = tableFor("en");
    expect(english["Open Tabbi"]).toBeUndefined();
    expect(english["%lld cards"]).toEqual({ one: "%lld card", other: "%lld cards" });
    expect(tableFor("de")["Quit Tabbi"]).toBe("Tabbi beenden");
  });
});
