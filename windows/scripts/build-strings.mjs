#!/usr/bin/env node
/*
 * Builds the app's strings from the String Catalogs: the Mac's
 * Sources/TabbiKitCore/Localization/Localizable.xcstrings, which both apps
 * share, and the Windows-only src/i18n/Windows.xcstrings. Writes one
 * compact JSON per language to src/i18n/generated/<language>.json (git
 * ignores it), which src/i18n/strings.ts imports lazily for the user's
 * language.
 *
 * A key maps to its format, or to its plural forms; a key whose text is the
 * key itself is left out, since tr() shows the key then. This is the same
 * flattening as languageTable() in src/core/localization/catalog.ts, and a
 * test checks the two agree.
 *
 *   node scripts/build-strings.mjs
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const windowsRoot = fileURLToPath(new URL("..", import.meta.url));

/** The catalogs, in merge order: a later catalog's key wins. */
export const CATALOGS = [
  join(windowsRoot, "..", "Sources", "TabbiKitCore", "Localization", "Localizable.xcstrings"),
  join(windowsRoot, "src", "i18n", "Windows.xcstrings"),
];

export const OUTPUT = join(windowsRoot, "src", "i18n", "generated");

/** The shipped languages; LANGUAGES in src/core/localization/languages.ts lists the same. */
export const LANGUAGES = ["en", "ar", "de", "es", "fr", "fil", "ja", "ko", "pt-BR", "ru", "zh-Hans", "zh-Hant"];

const PLURAL_CATEGORIES = ["zero", "one", "two", "few", "many", "other"];

/** One language's table from one parsed catalog. */
export function languageTable(catalog, language) {
  const table = {};
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const localization = entry.localizations?.[language];
    const plural = localization?.variations?.plural;
    if (plural) {
      const forms = {};
      for (const [form, variant] of Object.entries(plural)) {
        const value = variant.stringUnit?.value;
        if (PLURAL_CATEGORIES.includes(form) && value !== undefined) forms[form] = value;
      }
      table[key] = forms;
      continue;
    }
    const value = localization?.stringUnit?.value;
    if (value !== undefined && value !== key) table[key] = value;
  }
  return table;
}

/** Writes every language's merged table to `output`; returns the paths written. */
export function buildStrings({ catalogs = CATALOGS, output = OUTPUT, languages = LANGUAGES } = {}) {
  const parsed = catalogs.map((path) => JSON.parse(readFileSync(path, "utf8")));
  mkdirSync(output, { recursive: true });
  return languages.map((language) => {
    const table = Object.assign({}, ...parsed.map((catalog) => languageTable(catalog, language)));
    const path = join(output, `${language}.json`);
    writeFileSync(path, `${JSON.stringify(table)}\n`);
    return path;
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const written = buildStrings();
  console.log(`build-strings: wrote ${written.length} languages to ${OUTPUT}`);
}
