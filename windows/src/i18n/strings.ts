/*
 * Loads the user's language at startup. scripts/build-strings.mjs writes
 * one table per language to ./generated (from the Mac's catalog and
 * Windows.xcstrings); only the chosen language is fetched, as its own
 * chunk, so the other eleven never load.
 */

import type { LanguageTable } from "../core/localization/catalog";
import { languageFor, SOURCE_LANGUAGE, textDirection } from "../core/localization/languages";
import { installLanguage } from "../core/localization/lookup";

/** Imports one language's table, keyed by its generated file's path. */
export type TableImporters = Readonly<Record<string, () => Promise<LanguageTable>>>;

const generated: TableImporters = import.meta.glob<LanguageTable>("./generated/*.json", { import: "default" });

export interface LoadedLanguage {
  /** The language `tr` now reads, one of LANGUAGES. */
  readonly language: string;
  /** For `dir` on the document root: Arabic lays out mirrored. */
  readonly direction: "rtl" | "ltr";
}

/**
 * Picks the best shipped language for `preferences` (such as
 * `navigator.languages`), imports its table and installs it into `tr`.
 * Without a built table (the build step has not run) the strings stay the
 * English keys, which still reads correctly in English.
 */
export async function loadLanguage(
  preferences: readonly string[],
  importers: TableImporters = generated,
): Promise<LoadedLanguage> {
  const available = Object.keys(importers).map((path) => path.replace(/^.*\//, "").replace(/\.json$/, ""));
  const language = languageFor(preferences, available.length > 0 ? available : [SOURCE_LANGUAGE]);
  const importer = importers[`./generated/${language}.json`];
  if (importer) installLanguage(await importer(), language);
  return { language, direction: textDirection(language) };
}
